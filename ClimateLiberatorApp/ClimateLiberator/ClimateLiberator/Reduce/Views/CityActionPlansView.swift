import SwiftUI

/// City and cluster action plans live with their GHG inventories (GHG Accounting);
/// this list gathers them so all reduction work is reachable from one place.
struct CityActionPlansView: View {
    @ObservedObject var ghgStore: GPCInventoryStore
    /// Opens the inventory in GHG Accounting.
    let openInventory: (UUID) -> Void

    var body: some View {
        DSCard("City Action Plans", subtitle: "Scenarios and measures built on GPC inventories in GHG Accounting.") {
            if ghgStore.inventories.isEmpty {
                Text("No GHG inventories yet.").font(.callout).foregroundStyle(DSStyle.subtle)
            }
            VStack(spacing: 6) {
                ForEach(ghgStore.inventories) { inventory in
                    let scenarios = inventory.scenarios ?? []
                    let measures = scenarios.reduce(0) { $0 + $1.measures.count }
                    HStack(spacing: 10) {
                        Image(systemName: "building.columns").foregroundStyle(DSStyle.subtle).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inventory.displayName).font(.callout.weight(.medium))
                            Text(scenarios.isEmpty ? "No scenarios yet"
                                 : "\(scenarios.count) scenario(s) · \(measures) measure(s) · targets "
                                   + scenarios.map { String($0.targetYear) }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(DSStyle.subtle)
                        }
                        Spacer()
                        Button("Open in GHG Accounting") { openInventory(inventory.id) }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
                }
            }
        }
    }
}
