import SwiftUI

/// Draft reports with a live preview and export to Markdown, HTML (print to PDF) or CSV.
struct ReportsView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let accent: Color

    @State private var kind: ReportKind = .brsr

    private func isInScope(_ kind: ReportKind) -> Bool {
        switch kind {
        case .brsr: return engagement.frameworks.contains(.brsr)
        case .brsrCore, .assurancePack: return engagement.frameworks.contains(.brsrCore)
        case .ifrsS2: return engagement.frameworks.contains(.ifrsS2)
        case .auditTrail: return true
        }
    }

    var body: some View {
        let available = ReportKind.allCases.filter(isInScope)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(available) { item in reportRow(item) }
                Text("Reports are drafts built from the data entered here. Check them against the latest SEBI and ISSB texts before filing.")
                    .font(.caption)
                    .foregroundStyle(DSStyle.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(width: 300)
            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !isInScope(kind) { kind = available.first ?? .auditTrail }
        }
    }

    private func reportRow(_ item: ReportKind) -> some View {
        let isSelected = kind == item
        return Button { kind = item } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.systemImage).frame(width: 20).foregroundStyle(isSelected ? accent : DSStyle.subtle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.callout.weight(.semibold))
                    Text(item.detail).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? DSStyle.rowSelected : DSStyle.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Preview

    private var preview: some View {
        let paragraphs = kind == .ifrsS2 ? PhysicalRiskDrafting.paragraphs(for: engagement) : []
        let document = ReportBuilder.build(kind, engagement: engagement, physicalRiskParagraphs: paragraphs)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Preview").font(.headline)
                Spacer()
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        if let url = store.exportReport(kind, format: format, id: engagement.id) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Label(format.title, systemImage: format == .html ? "printer" : "square.and.arrow.up")
                    }
                    .disabled(format == .csv && document.tables.isEmpty)
                    .help("Writes the file to the Exports folder and shows it in Finder")
                }
            }
            .controlSize(.small)
            ScrollView {
                ReportPreview(document: document)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.28)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
    }
}

/// Native rendering of a `ReportDocument`, matching what the exports contain.
struct ReportPreview: View {
    let document: ReportDocument

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text(document.title).font(.title2.weight(.bold)).textSelection(.enabled)
            if !document.subtitle.isEmpty {
                Text(document.subtitle).font(.callout).foregroundStyle(DSStyle.subtle)
            }
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ReportBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(level <= 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, level <= 2 ? 10 : 4)
        case .paragraph(let text):
            Text(text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(item).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let table):
            tableView(table)
        case .note(let text):
            Label(text, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(DSStyle.subtle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.yellow.opacity(0.08)))
        }
    }

    private func tableView(_ table: ReportTable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !table.caption.isEmpty {
                Text(table.caption).font(.caption.weight(.semibold)).foregroundStyle(DSStyle.subtle)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow {
                        ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                            Text(column).font(.caption.weight(.semibold)).foregroundStyle(DSStyle.faint)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                                Text(cell)
                                    .font(.caption.monospacedDigit())
                                    .frame(maxWidth: index == 0 ? 320 : 200, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }
}
