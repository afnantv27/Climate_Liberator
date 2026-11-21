import SwiftUI

/// Compact, readable result of activity × emission factor. Shared by the
/// calculator and the activity-data entry editor so both explain results the same way.
struct EmissionResultView: View {
    let result: EmissionCalculationResult
    let factor: EmissionFactor

    @State private var showingInfo = false

    private struct GasShare: Identifiable {
        let id: String
        let massKg: Double
        let co2eKg: Double
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(GHGFormat.mass(result.co2eKg)) CO2e")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("GWP \(result.gwpSet.title)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { showingInfo.toggle() } label: {
                    Image(systemName: "info.circle").imageScale(.large)
                }
                .buttonStyle(.borderless)
                .help("How this result is calculated")
                .popover(isPresented: $showingInfo, arrowEdge: .trailing) { infoPopover }
            }
            gasShareBar
            trail
            if result.biogenicCO2Kg != 0 {
                Text("Biogenic CO2 \(GHGFormat.mass(result.biogenicCO2Kg)) — reported separately, not in the total.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(result.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(.yellow)
            }
            Text("\(factor.name) · \(factor.source)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: Gas split

    private var gasShares: [GasShare] {
        let gases = result.gasesKg
        let gwp = result.gwpSet
        let shares = [
            GasShare(id: "CO2", massKg: gases.co2, co2eKg: gases.co2, color: .cyan),
            GasShare(id: "CH4", massKg: gases.ch4Total,
                     co2eKg: gases.ch4Fossil * gwp.ch4Fossil + gases.ch4NonFossil * gwp.ch4NonFossil, color: .orange),
            GasShare(id: "N2O", massKg: gases.n2o, co2eKg: gases.n2o * gwp.n2o, color: .pink),
            GasShare(id: "F-gases", massKg: gases.sf6 + gases.nf3, co2eKg: gases.sf6 * gwp.sf6 + gases.nf3 * gwp.nf3, color: .purple),
            GasShare(id: "CO2e as published", massKg: gases.otherCO2e, co2eKg: gases.otherCO2e, color: .gray),
        ]
        return shares.filter { $0.co2eKg != 0 }
    }

    /// Thin bar showing each gas's share of the CO2e total, with a one-line legend.
    @ViewBuilder
    private var gasShareBar: some View {
        let shares = gasShares
        let total = shares.reduce(0) { $0 + abs($1.co2eKg) }
        if total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(shares) { share in
                            Rectangle()
                                .fill(share.color)
                                .frame(width: max(2, geometry.size.width * abs(share.co2eKg) / total))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                HStack(spacing: 10) {
                    ForEach(shares) { share in
                        HStack(spacing: 4) {
                            Circle().fill(share.color).frame(width: 6, height: 6)
                            Text(share.id == "CO2e as published" ? share.id : "\(share.id) \(GHGFormat.mass(share.massKg))")
                            Text(GHGFormat.percent(abs(share.co2eKg) / total)).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
            }
        }
    }

    // MARK: Steps

    private var trail: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 3) {
            ForEach(Array(result.trail.enumerated()), id: \.offset) { _, step in
                let isTotal = step.label == "Emissions"
                GridRow {
                    Text(step.label)
                        .foregroundStyle(.secondary)
                    Text(step.operation)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(displayValue(step))
                        .fontWeight(isTotal ? .semibold : .regular)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func displayValue(_ step: CalculationStep) -> String {
        step.unit == "kg CO2e" ? "\(GHGFormat.mass(step.value)) CO2e" : "\(GHGFormat.plain(step.value)) \(step.unit)"
    }

    // MARK: Info

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How This Is Calculated").font(.headline)
            Text("Emissions = activity × emission factor.")
            if result.trail.contains(where: { ["Mass", "Energy", "Volume"].contains($0.label) }) {
                Text("This factor is per \(result.factorUnit), so the activity is first converted using the fuel's density and/or net calorific value (NCV).")
            } else if result.trail.contains(where: { $0.label == "Converted" }) {
                Text("The activity is first converted to the factor's unit (\(result.factorUnit)).")
            }
            Text("Factor per \(result.factorUnit)").font(.subheadline.weight(.semibold)).padding(.top, 2)
            Text(factorBreakdown).font(.caption.monospacedDigit())
            Text("GWP (\(result.gwpSet.title), 100-year) weights each gas by how much it warms compared with CO2. Combustion CH4 uses the non-fossil value.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(factor.name).font(.caption.weight(.semibold))
            if let notes = factor.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
            if let link = factor.sourceURL.flatMap({ URL(string: $0) }) {
                Link("View Source: \(factor.source)", destination: link).font(.caption)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(width: 340)
    }

    /// e.g. "CO2 63,100 + CH4 5 × 27 + N2O 0.1 × 273 = 63,262 kg CO2e"
    private var factorBreakdown: String {
        let gases = result.perUnitGases
        let gwp = result.gwpSet
        func f(_ value: Double) -> String { GHGFormat.plain(value) }
        var parts: [String] = []
        if gases.co2 != 0 { parts.append("CO2 \(f(gases.co2))") }
        if gases.ch4Fossil != 0 { parts.append("CH4 \(f(gases.ch4Fossil)) × \(f(gwp.ch4Fossil))") }
        if gases.ch4NonFossil != 0 { parts.append("CH4 \(f(gases.ch4NonFossil)) × \(f(gwp.ch4NonFossil))") }
        if gases.n2o != 0 { parts.append("N2O \(f(gases.n2o)) × \(f(gwp.n2o))") }
        if gases.sf6 != 0 { parts.append("SF6 \(f(gases.sf6)) × \(f(gwp.sf6))") }
        if gases.nf3 != 0 { parts.append("NF3 \(f(gases.nf3)) × \(f(gwp.nf3))") }
        if gases.otherCO2e != 0 { parts.append("\(f(gases.otherCO2e)) CO2e as published") }
        var text = parts.joined(separator: " + ") + " = \(f(result.perUnitCO2eKg)) kg CO2e"
        if gases.co2Biogenic != 0 { text += "\n(+ biogenic CO2 \(f(gases.co2Biogenic)) kg, reported separately)" }
        return text
    }
}
