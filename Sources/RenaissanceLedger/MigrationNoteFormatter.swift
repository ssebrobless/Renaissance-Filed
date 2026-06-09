import Foundation

private let migrationImportTag = "[staging-import]"
let historicalInvoicePlaceholderDescription = "Historical imported invoice"
let historicalEstimatePlaceholderDescription = "Historical imported estimate"
private let genericHistoricalNoiseNotes: Set<String> = [
    "estimates",
    "accounts receivable",
    "accounts payable",
]

func isMigrationAuditMemo(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return trimmed.localizedCaseInsensitiveContains(migrationImportTag)
}

func userFacingMemo(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if genericHistoricalNoiseNotes.contains(trimmed.lowercased()) {
        return ""
    }
    guard isMigrationAuditMemo(trimmed) else { return trimmed }

    let parts = trimmed
        .split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    var visibleBits: [String] = []
    var typeTag = ""

    for part in parts where !part.isEmpty {
        if part.localizedCaseInsensitiveContains(migrationImportTag) {
            typeTag = part
                .replacingOccurrences(of: migrationImportTag, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            continue
        }

        if let value = migrationValue(for: "memo", in: part), !value.isEmpty {
            visibleBits.append(value)
            continue
        }

        if let value = migrationValue(for: "job", in: part), !value.isEmpty {
            visibleBits.append("Job: \(value)")
            continue
        }

        if let value = migrationValue(for: "kind", in: part), value == "refund_deposit" {
            visibleBits.append("Historical refund deposit")
            continue
        }
    }

    if !visibleBits.isEmpty {
        return visibleBits.joined(separator: " | ")
    }

    switch typeTag {
    case "CHECK":
        return "Historical QuickBooks check"
    case "AP":
        return "Historical QuickBooks bill"
    default:
        return ""
    }
}

func editableMemo(_ raw: String) -> String {
    userFacingMemo(raw)
}

func resolvedMemoForSave(editedMemo: String, originalRawMemo: String?) -> String {
    let edited = editedMemo.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let originalRawMemo else { return edited }
    guard isMigrationAuditMemo(originalRawMemo) else { return edited }

    let originalVisible = userFacingMemo(originalRawMemo).trimmingCharacters(in: .whitespacesAndNewlines)
    if edited == originalVisible {
        return originalRawMemo
    }
    return edited
}

func isHistoricalInvoicePlaceholderOnly(_ lines: [InvoiceLineRow]) -> Bool {
    lines.count == 1 && lines.first?.description == historicalInvoicePlaceholderDescription
}

func isHistoricalEstimatePlaceholderOnly(_ lines: [EstimateLineRow]) -> Bool {
    lines.count == 1 && lines.first?.description == historicalEstimatePlaceholderDescription
}

private func migrationValue(for key: String, in part: String) -> String? {
    let prefix = "\(key)="
    guard part.lowercased().hasPrefix(prefix) else { return nil }
    return String(part.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
}
