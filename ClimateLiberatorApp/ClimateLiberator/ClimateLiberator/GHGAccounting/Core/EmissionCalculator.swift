import Foundation

/// One line of the calculation trail, e.g. "Energy: 398,200 kg × 47.3 MJ/kg (NCV) = 18.83 TJ".
nonisolated struct CalculationStep: Codable, Hashable, Sendable {
    /// Short name of the quantity, e.g. "Activity", "Mass", "Energy", "Emissions".
    let label: String
    /// How it was obtained; empty for the input row.
    let operation: String
    let value: Double
    let unit: String

    var text: String {
        let result = "\(EmissionCalculator.format(value)) \(unit)"
        return operation.isEmpty ? "\(label): \(result)" : "\(label): \(operation) = \(result)"
    }
}

nonisolated struct EmissionCalculationResult: Codable, Hashable, Sendable {
    /// Absolute gas masses in kg (biogenic CO2 included for separate reporting).
    let gasesKg: GasAmounts
    /// Total CO2e in kg, excluding biogenic CO2.
    let co2eKg: Double
    let gwpSet: GWPSet
    /// Activity quantity expressed in the factor's unit.
    let quantityInFactorUnit: Double
    let factorUnit: String
    /// Gas amounts and CO2e per factor unit that were applied.
    let perUnitGases: GasAmounts
    let perUnitCO2eKg: Double
    /// Every conversion from the activity to the result, in order.
    let trail: [CalculationStep]
    let warnings: [String]

    var steps: [String] { trail.map(\.text) }
    var co2eTonnes: Double { co2eKg / 1_000 }
    var biogenicCO2Kg: Double { gasesKg.co2Biogenic }
}

nonisolated enum EmissionCalculationError: LocalizedError, Equatable, Sendable {
    case unknownUnit(String)
    case factorUnitUnknown(String)
    case incompatibleUnits(activity: String, factor: String)
    case currencyMismatch(activity: String, factor: String)
    case missingDensity(String)
    case missingCalorificValue(String)
    case missingFactorValue(String)
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .unknownUnit(let unit):
            return "Unit \"\(unit)\" is not recognised. Use a symbol such as kWh, L, kg, t, km, t·km or a currency code."
        case .factorUnitUnknown(let unit):
            return "The emission factor's unit \"\(unit)\" is not recognised."
        case .incompatibleUnits(let activity, let factor):
            return "\(activity) cannot be converted to the factor's unit (\(factor)). Pick a factor with a compatible unit."
        case .currencyMismatch(let activity, let factor):
            return "Spend is in \(activity) but the factor is per \(factor). Convert the spend to \(factor) first (state the exchange rate in your notes)."
        case .missingDensity(let factor):
            return "Converting volume ↔ mass needs a fuel density, and \"\(factor)\" has none. Enter the quantity in the factor's unit or add a density."
        case .missingCalorificValue(let factor):
            return "Converting mass ↔ energy needs a net calorific value, and \"\(factor)\" has none. Enter the quantity in the factor's unit."
        case .missingFactorValue(let factor):
            return "\"\(factor)\" has no numeric value in this database. Use the remote estimate (Climatiq) or pick another factor."
        case .invalidQuantity:
            return "Enter a finite activity quantity."
        }
    }
}

/// Activity data × emission factor, with unit conversion and GWP weighting.
nonisolated enum EmissionCalculator {

    static func calculate(quantity: Double,
                          unit activityUnitSymbol: String,
                          factor: EmissionFactor,
                          gwp: GWPSet) throws -> EmissionCalculationResult {
        guard quantity.isFinite else { throw EmissionCalculationError.invalidQuantity }
        guard let activityUnit = UnitRegistry.resolve(activityUnitSymbol) else {
            throw EmissionCalculationError.unknownUnit(activityUnitSymbol)
        }
        guard let factorUnit = factor.unitDefinition else {
            throw EmissionCalculationError.factorUnitUnknown(factor.activityUnit)
        }

        var trail = [CalculationStep(label: "Activity", operation: "", value: quantity, unit: activityUnit.symbol)]
        var warnings: [String] = []
        let converted = try convertQuantity(quantity, from: activityUnit, to: factorUnit,
                                            factor: factor, trail: &trail)

        let perUnit: GasAmounts
        if let gases = factor.gases, !gases.isEmpty,
           factor.co2ePerUnit == nil || factor.co2eBasis != gwp {
            perUnit = gases
            if factor.co2ePerUnit != nil {
                let basis = factor.co2eBasis?.title ?? "an unstated GWP set"
                warnings.append("Recomputed CO2e with \(gwp.title) GWPs from the factor's gases (source total uses \(basis)).")
            }
        } else if let total = factor.co2ePerUnit {
            perUnit = GasAmounts(otherCO2e: total)
            if let basis = factor.co2eBasis, basis != gwp {
                warnings.append("Factor CO2e uses \(basis.title) GWPs and has no gas breakdown, so it cannot be re-weighted to \(gwp.title).")
            } else if factor.co2eBasis == nil {
                warnings.append("The source does not state which GWP set its CO2e uses.")
            }
        } else {
            throw EmissionCalculationError.missingFactorValue(factor.name)
        }

        if quantity < 0 {
            warnings.append("Negative activity treated as a removal; check this is intended (e.g. AFOLU land sinks).")
        }

        let absolute = perUnit.scaled(by: converted)
        let co2e = absolute.co2e(gwp)
        let perUnitCO2e = perUnit.co2e(gwp)
        trail.append(CalculationStep(
            label: "Emissions",
            operation: "\(Self.format(converted)) \(factor.activityUnit) × \(Self.format(perUnitCO2e)) kg CO2e/\(factor.activityUnit)",
            value: co2e, unit: "kg CO2e"))

        return EmissionCalculationResult(gasesKg: absolute, co2eKg: co2e, gwpSet: gwp,
                                         quantityInFactorUnit: converted, factorUnit: factor.activityUnit,
                                         perUnitGases: perUnit, perUnitCO2eKg: perUnitCO2e,
                                         trail: trail, warnings: warnings)
    }

    /// Converts within a dimension, or across volume → mass → energy using the
    /// factor's density and net calorific value.
    static func convertQuantity(_ quantity: Double,
                                from activity: UnitDefinition,
                                to target: UnitDefinition,
                                factor: EmissionFactor,
                                trail: inout [CalculationStep]) throws -> Double {
        if activity.dimension == target.dimension {
            if activity.dimension == .money, activity.currency != target.currency {
                throw EmissionCalculationError.currencyMismatch(activity: activity.symbol, factor: target.symbol)
            }
            let value = UnitRegistry.convert(quantity, from: activity, to: target) ?? quantity
            if activity.symbol != target.symbol {
                trail.append(CalculationStep(label: "Converted", operation: "\(activity.symbol) → \(target.symbol)",
                                             value: value, unit: target.symbol))
            }
            return value
        }

        let fuelPath: [UnitDimension] = [.volume, .mass, .energy]
        guard let startIndex = fuelPath.firstIndex(of: activity.dimension),
              let endIndex = fuelPath.firstIndex(of: target.dimension) else {
            throw EmissionCalculationError.incompatibleUnits(activity: activity.symbol, factor: target.symbol)
        }

        // Walk the chain in base units (litres ↔ kg ↔ kWh). Each step is shown in the
        // target unit when it reaches the factor's dimension, otherwise in L or kg.
        var value = quantity * activity.toBase
        var index = startIndex
        while index != endIndex {
            let forward = endIndex > index
            let from = fuelPath[index]
            let to = fuelPath[forward ? index + 1 : index - 1]
            let isLast = (forward ? index + 1 : index - 1) == endIndex
            switch (from, to) {
            case (.volume, .mass), (.mass, .volume):
                guard let density = factor.densityKgPerLitre, density > 0 else {
                    throw EmissionCalculationError.missingDensity(factor.name)
                }
                let next = from == .volume ? value * density : value / density
                let operation = from == .volume
                    ? "\(format(value)) L × \(format(density)) kg/L (density)"
                    : "\(format(value)) kg ÷ \(format(density)) kg/L (density)"
                trail.append(step(label: to == .mass ? "Mass" : "Volume", operation: operation,
                                  baseValue: next, baseUnit: to == .mass ? "kg" : "L", target: isLast ? target : nil))
                value = next
            case (.mass, .energy), (.energy, .mass):
                guard let ncv = factor.netCalorificValueMJPerKg, ncv > 0 else {
                    throw EmissionCalculationError.missingCalorificValue(factor.name)
                }
                let kWhPerKg = ncv / 3.6
                let next = from == .mass ? value * kWhPerKg : value / kWhPerKg
                let operation = from == .mass
                    ? "\(format(value)) kg × \(format(ncv)) MJ/kg (NCV)"
                    : "\(format(value * 3.6)) MJ ÷ \(format(ncv)) MJ/kg (NCV)"
                trail.append(step(label: to == .energy ? "Energy" : "Mass", operation: operation,
                                  baseValue: next, baseUnit: to == .energy ? "kWh" : "kg", target: isLast ? target : nil))
                value = next
            default:
                throw EmissionCalculationError.incompatibleUnits(activity: activity.symbol, factor: target.symbol)
            }
            index += forward ? 1 : -1
        }
        return value / target.toBase
    }

    private static func step(label: String, operation: String, baseValue: Double, baseUnit: String,
                             target: UnitDefinition?) -> CalculationStep {
        guard let target else { return CalculationStep(label: label, operation: operation, value: baseValue, unit: baseUnit) }
        return CalculationStep(label: label, operation: operation, value: baseValue / target.toBase, unit: target.symbol)
    }

    /// Plain, grouped numbers (no scientific notation): 18,834,860 · 18.83 · 0.0942.
    static func format(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude == 0 { return "0" }
        if magnitude >= 1e15 || magnitude < 1e-6 { return String(format: "%.3g", value) }
        if magnitude >= 1_000 { return value.formatted(.number.precision(.fractionLength(0))) }
        if magnitude >= 1 { return value.formatted(.number.precision(.significantDigits(1...4))) }
        return value.formatted(.number.precision(.significantDigits(1...3)))
    }
}
