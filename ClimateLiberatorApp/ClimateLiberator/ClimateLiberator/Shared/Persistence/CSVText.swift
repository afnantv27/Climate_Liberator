import Foundation

/// RFC 4180 CSV: quoted fields, doubled quotes, newlines inside quotes.
nonisolated enum CSVText {
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    static func write(header: [String], rows: [[String]]) -> String {
        ([line(header)] + rows.map(line)).joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if characters.first == "\u{FEFF}" { characters.removeFirst() }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default: field.append(character)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}
