import Foundation

enum CSVParser {
    static func parse(_ text: String) -> [CSVRecord] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let headerLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return []
        }
        let headers = parseLine(headerLine).map(normalizeHeader)
        guard !headers.isEmpty else {
            return []
        }

        var records: [CSVRecord] = []
        var started = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !started {
                if trimmed == headerLine.trimmingCharacters(in: .whitespaces) {
                    started = true
                }
                continue
            }

            if trimmed.isEmpty {
                continue
            }

            let columns = parseLine(line)
            if columns.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                continue
            }

            var fields: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                let value = index < columns.count ? columns[index] : ""
                fields[header] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            records.append(CSVRecord(fields: fields))
        }

        return records
    }

    private static func parseLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]
            if char == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(char)
            }
            i = line.index(after: i)
        }

        values.append(current)
        return values
    }

    private static func normalizeHeader(_ header: String) -> String {
        header
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
