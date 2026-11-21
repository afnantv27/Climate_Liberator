import SwiftUI

/// Step 3: quality checks before results are shared — completeness against the
/// reporting level, entries that fail, missing notation-key explanations and
/// the largest lines that rest on weak data.
struct GPCReviewView: View {
    @ObservedObject var store: GPCInventoryStore
    let inventory: GPCInventory
    let accent: Color

    private struct QualityItem: Identifiable {
        let entry: GPCInventoryEntry
        let tonnes: Double
        var id: UUID { entry.id }
    }

    var body: some View {
        let summary = GPCInventorySummary.make(inventory)
        let breakdown = GPCResultBreakdown.make(inventory, summary: summary)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overview(summary, breakdown: breakdown)
                HStack(alignment: .top, spacing: 14) {
                    completeness(summary)
                    VStack(spacing: 14) {
                        fixList(summary)
                        qualityList(summary, total: breakdown.total)
                    }
                    .frame(width: 440)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: Overview

    private func overview(_ summary: GPCInventorySummary, breakdown: GPCResultBreakdown) -> some View {
        let items = summary.completeness
        let reported = items.filter { if case .reported = $0.status { return true }; return false }.count
        let notation = items.filter { if case .notation = $0.status { return true }; return false }.count
        return HStack(spacing: 12) {
            GHGMetricCard(title: "Required for \(inventory.targetLevel.title)", value: "\(items.count)", detail: "GPC sources")
            GHGMetricCard(title: "Reported", value: "\(reported)", detail: "With a number")
            GHGMetricCard(title: "Notation keys", value: "\(notation)", detail: "NO, IE, NE or C")
            GHGMetricCard(title: "Gaps", value: "\(summary.missingCount)",
                          detail: summary.missingCount == 0 ? "Complete" : "Missing or failing")
            GHGMetricCard(title: "Low-quality data", value: GHGFormat.percent(breakdown.lowQualityShare),
                          detail: "Share of the \(inventory.targetLevel.title) total")
        }
    }

    // MARK: Completeness

    private func completeness(_ summary: GPCInventorySummary) -> some View {
        GHGPanelCard(title: "Completeness",
                     subtitle: "Every required source needs a number or a notation key (NO, IE, NE, C).") {
            Picker("Reporting level", selection: Binding(get: { inventory.targetLevel },
                                                         set: { level in store.mutateSelected { $0.targetLevel = level } })) {
                ForEach(GPCReportingLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } content: {
            ForEach(summary.completeness) { item in
                HStack(spacing: 8) {
                    statusIcon(item.status)
                    Text(item.reference.id).font(.caption.monospacedDigit()).frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GPCCatalog.subSector(item.reference.subSectorID)?.title ?? "").font(.caption.weight(.semibold))
                        Text(item.reference.title).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Text(statusText(item.status)).font(.caption)
                    if !isSatisfied(item.status) {
                        Menu("Notation Key") {
                            ForEach(GPCNotationKey.allCases) { key in
                                Button("\(key.rawValue) — \(key.meaning)") {
                                    store.upsertEntry(GPCInventoryEntry(referenceID: item.reference.id,
                                                                        label: item.reference.title,
                                                                        method: .notationKey,
                                                                        notationKey: key))
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: Fix list

    @ViewBuilder
    private func fixList(_ summary: GPCInventorySummary) -> some View {
        let failing = inventory.entries.filter { summary.outcomes[$0.id]?.error != nil }
        let unexplained = inventory.entries.filter { entry in
            entry.method == .notationKey
                && (entry.notationKey == .includedElsewhere || entry.notationKey == .notEstimated)
                && entry.notationExplanation.trimmingCharacters(in: .whitespaces).isEmpty
        }
        GHGPanelCard(title: "Fix First", subtitle: "Excluded from totals or incomplete until fixed in Activity data.") {
            if failing.isEmpty && unexplained.isEmpty {
                Label("No failing entries.", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
            ForEach(failing) { entry in
                Label("\(entry.referenceID) \(entry.label): \(summary.outcomes[entry.id]?.error ?? "")",
                      systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(unexplained) { entry in
                Label("\(entry.referenceID): \(entry.notationKey?.rawValue ?? "") needs an explanation (GPC requires one for IE and NE).",
                      systemImage: "text.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Data quality

    private func qualityList(_ summary: GPCInventorySummary, total: Double) -> some View {
        let items: [QualityItem] = inventory.entries.compactMap { entry in
            guard entry.method != .notationKey, entry.dataQuality != .high,
                  let outcome = summary.outcomes[entry.id], outcome.error == nil, outcome.co2eTonnes > 0 else { return nil }
            return QualityItem(entry: entry, tonnes: outcome.co2eTonnes)
        }
        .sorted { $0.tonnes > $1.tonnes }
        return GHGPanelCard(title: "Improve Data Quality",
                            subtitle: "Largest lines on low or medium-quality data. Better local data here moves the total most.") {
            if items.isEmpty {
                Text("All emitting lines are rated high quality.").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            ForEach(items.prefix(6)) { item in
                HStack(spacing: 8) {
                    GHGTag(text: item.entry.dataQuality.title, color: item.entry.dataQuality == .low ? .orange : .yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.entry.referenceID) \(item.entry.label)").font(.caption.weight(.semibold)).lineLimit(1)
                        if !item.entry.dataSource.isEmpty {
                            Text(item.entry.dataSource).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(GHGFormat.plain(item.tonnes)) t").font(.caption.monospacedDigit())
                    if total > 0 {
                        Text(GHGFormat.percent(item.tonnes / total)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func isSatisfied(_ status: GPCCompletenessStatus) -> Bool {
        switch status {
        case .reported, .notation: return true
        case .missing, .error: return false
        }
    }

    private func statusText(_ status: GPCCompletenessStatus) -> String {
        switch status {
        case .reported: return "Reported"
        case .notation(let key): return key.rawValue
        case .missing: return "Missing"
        case .error: return "Error"
        }
    }

    private func statusIcon(_ status: GPCCompletenessStatus) -> some View {
        let (name, color): (String, Color) = {
            switch status {
            case .reported: return ("checkmark.circle.fill", .green)
            case .notation: return ("tag.fill", .teal)
            case .missing: return ("exclamationmark.circle", .orange)
            case .error: return ("xmark.octagon.fill", .red)
            }
        }()
        return Image(systemName: name).foregroundStyle(color)
    }
}
