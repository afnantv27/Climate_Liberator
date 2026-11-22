import Foundation

/// CSV tables shaped like the GPC reporting template.
nonisolated enum GPCReportExporter {
    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func number(_ value: Double) -> String { String(format: "%.3f", value) }

    static func entriesCSV(_ inventory: GPCInventory, summary: GPCInventorySummary) -> String {
        var lines = [[
            "GPC ref", "Sector", "Sub-sector", "Scope", "Inclusion", "Label", "Method", "Notation key",
            "Activity quantity", "Activity unit", "Emission factor", "Factor source", "Factor region", "Factor year",
            "CO2 (t)", "CH4 (t)", "N2O (t)", "Other CO2e (t)", "Total CO2e (t)", "Biogenic CO2 (t)",
            "Data quality", "Data source", "Facility", "Notes", "Warnings or errors",
        ].joined(separator: ",")]

        for entry in inventory.entries {
            let reference = entry.reference
            let outcome = summary.outcomes[entry.id]
            let gases = outcome?.gasesTonnes ?? .zero
            let subSector = reference.flatMap { GPCCatalog.subSector($0.subSectorID)?.title } ?? ""
            let messages = ([outcome?.error].compactMap { $0 } + (outcome?.warnings ?? [])).joined(separator: " | ")
            let isNumeric = entry.method != .notationKey && outcome?.error == nil
            let row: [String] = [
                entry.referenceID,
                reference?.sector.title ?? "",
                subSector,
                reference?.scope.title ?? "",
                reference?.inclusionLabel ?? "",
                entry.label,
                entry.method.title,
                entry.method == .notationKey ? (entry.notationKey?.rawValue ?? "") : "",
                entry.activityQuantity.map { String($0) } ?? "",
                entry.activityUnit,
                entry.factor?.name ?? "",
                entry.factor?.source ?? "",
                entry.factor?.region ?? "",
                entry.factor?.year.map(String.init) ?? "",
                isNumeric ? number(gases.co2) : "",
                isNumeric ? number(gases.ch4Total) : "",
                isNumeric ? number(gases.n2o) : "",
                isNumeric ? number(gases.otherCO2e + gases.sf6 * inventory.gwpSet.sf6 + gases.nf3 * inventory.gwpSet.nf3) : "",
                isNumeric ? number(outcome?.co2eTonnes ?? 0) : "",
                isNumeric ? number(gases.co2Biogenic) : "",
                entry.dataQuality.rawValue,
                entry.dataSource,
                inventory.facility(entry.facilityID)?.name ?? "",
                entry.method == .notationKey ? entry.notationExplanation : entry.notes,
                messages,
            ]
            lines.append(row.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func summaryCSV(_ inventory: GPCInventory, summary: GPCInventorySummary) -> String {
        var lines: [String] = []
        lines.append("City,\(csvField(inventory.cityName))")
        lines.append("Region,\(csvField(inventory.region))")
        lines.append("Country,\(csvField(inventory.country))")
        lines.append("Inventory year,\(inventory.inventoryYear)")
        lines.append("Boundary,\(csvField(inventory.boundaryType.title))")
        lines.append("Boundary area (km2),\(String(format: "%.3f", inventory.boundary.areaSquareKilometres))")
        lines.append("Population,\(inventory.population.map(String.init) ?? "")")
        lines.append("GWP values,IPCC \(inventory.gwpSet.title) 100-year")
        lines.append("")
        lines.append("Sector,Scope 1 (tCO2e),Scope 2 (tCO2e),Scope 3 (tCO2e),Total (tCO2e)")
        for sector in GPCSector.allCases {
            let values = GPCScope.allCases.map { summary.total(sector, $0) }
            lines.append(([csvField(sector.title)] + values.map(number) + [number(values.reduce(0, +))]).joined(separator: ","))
        }
        lines.append("")
        lines.append("BASIC total (tCO2e),\(number(summary.basicTotal))")
        lines.append("BASIC+ total (tCO2e),\(number(summary.basicPlusTotal))")
        lines.append("Scope 1 territorial total (tCO2e),\(number(summary.territorialTotal))")
        lines.append("Other scope 3, reported separately (tCO2e),\(number(summary.otherScope3Total))")
        lines.append("Biogenic CO2, reported separately (t),\(number(summary.biogenicCO2Tonnes))")
        if let perCapita = summary.perCapitaBasic { lines.append("BASIC per capita (tCO2e/person),\(String(format: "%.4f", perCapita))") }
        if let perCapita = summary.perCapitaBasicPlus { lines.append("BASIC+ per capita (tCO2e/person),\(String(format: "%.4f", perCapita))") }
        lines.append("")
        lines.append("Completeness for \(inventory.targetLevel.title),GPC ref,Status")
        for item in summary.completeness {
            let status: String
            switch item.status {
            case .reported: status = "Reported"
            case .notation(let key): status = "Notation key \(key.rawValue)"
            case .missing: status = "Missing"
            case .error(let message): status = "Error: \(message)"
            }
            lines.append("\(csvField(item.reference.title)),\(item.reference.id),\(csvField(status))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
