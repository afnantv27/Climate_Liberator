import Foundation

// A format-neutral report: builders produce it, renderers turn it into Markdown,
// HTML or CSV, and the app previews it natively. A new format is a new renderer.

nonisolated struct ReportTable: Hashable, Sendable {
    var caption = ""
    var columns: [String]
    var rows: [[String]]
}

nonisolated enum ReportBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case table(ReportTable)
    /// A highlighted remark: draft status, missing data, sources.
    case note(String)
}

nonisolated struct ReportDocument: Hashable, Sendable {
    var title: String
    var subtitle: String
    var blocks: [ReportBlock] = []

    mutating func heading(_ text: String, level: Int = 2) { blocks.append(.heading(level: level, text: text)) }
    mutating func paragraph(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.paragraph(trimmed)) }
    }
    mutating func bullets(_ items: [String]) { if !items.isEmpty { blocks.append(.bullets(items)) } }
    mutating func table(_ table: ReportTable) { blocks.append(.table(table)) }
    mutating func note(_ text: String) { blocks.append(.note(text)) }

    /// All tables, for CSV export.
    var tables: [ReportTable] {
        blocks.compactMap { block in
            if case .table(let table) = block { return table }
            return nil
        }
    }
}

nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown, html, csv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .html: return "HTML (print to PDF)"
        case .csv: return "CSV tables"
        }
    }
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        case .csv: return "csv"
        }
    }
}

nonisolated enum ReportRenderer {

    static func render(_ document: ReportDocument, as format: ExportFormat) -> String {
        switch format {
        case .markdown: return markdown(document)
        case .html: return html(document)
        case .csv: return csv(document)
        }
    }

    // MARK: Markdown

    static func markdown(_ document: ReportDocument) -> String {
        var lines = ["# \(document.title)", "", "_\(document.subtitle)_", ""]
        for block in document.blocks {
            switch block {
            case .heading(let level, let text):
                lines.append(String(repeating: "#", count: min(max(level, 2), 6)) + " " + text)
            case .paragraph(let text):
                lines.append(text)
            case .bullets(let items):
                lines.append(contentsOf: items.map { "- \($0)" })
            case .note(let text):
                lines.append("> \(text)")
            case .table(let table):
                if !table.caption.isEmpty { lines.append("**\(table.caption)**"); lines.append("") }
                func row(_ cells: [String]) -> String {
                    "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
                        .joined(separator: " | ") + " |"
                }
                lines.append(row(table.columns))
                lines.append("|" + table.columns.map { _ in "---" }.joined(separator: "|") + "|")
                lines.append(contentsOf: table.rows.map(row))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: HTML

    static func html(_ document: ReportDocument) -> String {
        var body: [String] = ["<h1>\(escape(document.title))</h1>", "<p class=\"subtitle\">\(escape(document.subtitle))</p>"]
        for block in document.blocks {
            switch block {
            case .heading(let level, let text):
                let tag = "h\(min(max(level, 2), 6))"
                body.append("<\(tag)>\(escape(text))</\(tag)>")
            case .paragraph(let text):
                body.append(text.components(separatedBy: "\n\n").map { "<p>\(escape($0).replacingOccurrences(of: "\n", with: "<br>"))</p>" }.joined())
            case .bullets(let items):
                body.append("<ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>")
            case .note(let text):
                body.append("<p class=\"note\">\(escape(text))</p>")
            case .table(let table):
                var html = "<table>"
                if !table.caption.isEmpty { html += "<caption>\(escape(table.caption))</caption>" }
                html += "<thead><tr>" + table.columns.map { "<th>\(escape($0))</th>" }.joined() + "</tr></thead><tbody>"
                for row in table.rows {
                    html += "<tr>" + row.map { "<td>\(escape($0))</td>" }.joined() + "</tr>"
                }
                html += "</tbody></table>"
                body.append(html)
            }
        }
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><title>\(escape(document.title))</title>
        <style>
        body{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;color:#1d2327;max-width:960px;margin:40px auto;padding:0 24px;line-height:1.5;font-size:14px}
        h1{font-size:26px;margin-bottom:4px} h2{font-size:19px;margin-top:32px;border-bottom:1px solid #d0d7de;padding-bottom:4px}
        h3{font-size:16px;margin-top:22px} .subtitle{color:#57606a;margin-top:0}
        table{border-collapse:collapse;width:100%;margin:10px 0 18px;font-size:12.5px} caption{text-align:left;font-weight:600;margin-bottom:6px}
        th,td{border:1px solid #d0d7de;padding:6px 8px;text-align:left;vertical-align:top} th{background:#f3f5f7}
        .note{background:#fff8e1;border-left:3px solid #e0a800;padding:8px 12px;color:#5c4a00}
        @media print{body{margin:0;max-width:none} h2{page-break-after:avoid} table{page-break-inside:auto} tr{page-break-inside:avoid}}
        </style></head><body>
        \(body.joined(separator: "\n"))
        </body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: CSV

    /// Every table, one after another, separated by a blank line and its caption.
    static func csv(_ document: ReportDocument) -> String {
        document.tables.map { table in
            let caption = table.caption.isEmpty ? "" : DisclosureCSV.line([table.caption]) + "\n"
            return caption + DisclosureCSV.write(header: table.columns, rows: table.rows)
        }.joined(separator: "\n")
    }
}
