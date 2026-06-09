import Foundation

enum ImportServiceError: Error, LocalizedError {
    case invalidTransferRoot
    case manifestMissing

    var errorDescription: String? {
        switch self {
        case .invalidTransferRoot:
            return "Could not find a RenaissanceTransfer folder in the selected path."
        case .manifestMissing:
            return "Could not find manifest.json in the RenaissanceTransfer folder."
        }
    }
}

final class ImportService {
    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    func importTransferFolder(selectedURL: URL) throws -> ImportSummary {
        let transferRoot = try resolveTransferRoot(from: selectedURL)
        let manifestURL = transferRoot.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ImportServiceError.manifestMissing
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(TransferManifest.self, from: manifestData)

        let entries = manifest.allEntries
        let sessionID = try database.beginImportSession(transferRoot: transferRoot.path)

        var documentsCount = 0
        var transactionsCount = 0
        var invoicesCount = 0
        var payoutsCount = 0
        var issuesCount = 0

        for entry in entries {
            do {
                guard let storedURL = resolveStoredURL(for: entry, transferRoot: transferRoot) else {
                    issuesCount += 1
                    try database.insertIssue(
                        sessionID: sessionID,
                        level: "warning",
                        message: "Stored file not found for manifest entry.",
                        context: entry.relativePath
                    )
                    continue
                }

                let documentID = try database.insertDocument(
                    sessionID: sessionID,
                    category: entry.category,
                    relativePath: entry.relativePath,
                    storedPath: storedURL.path,
                    sourcePath: entry.sourcePath,
                    sha256: entry.sha256,
                    sizeBytes: entry.sizeBytes
                )
                documentsCount += 1

                if entry.category == "exports_csv" {
                    let text = try readText(from: storedURL)
                    let records = CSVParser.parse(text)
                    let importKind = classifyCSV(relativePath: entry.relativePath)

                    for record in records {
                        switch importKind {
                        case .invoice:
                            try database.insertInvoice(
                                sessionID: sessionID,
                                sourceDocumentID: documentID,
                                invoiceNumber: firstValue(record.fields, keys: ["invoice_number", "invoice_no", "invoice", "ref_number"]),
                                customer: firstValue(record.fields, keys: ["customer", "name", "client"]),
                                issueDate: parseDate(firstValue(record.fields, keys: ["date", "issue_date", "invoice_date"])),
                                dueDate: parseDate(firstValue(record.fields, keys: ["due_date", "due"])),
                                amount: parseAmount(firstValue(record.fields, keys: ["amount", "total", "balance"])),
                                status: firstValue(record.fields, keys: ["status", "state"]),
                                rawJSON: encodeRaw(record.fields)
                            )
                            invoicesCount += 1
                        case .payout:
                            try database.insertPayout(
                                sessionID: sessionID,
                                sourceDocumentID: documentID,
                                payee: firstValue(record.fields, keys: ["payee", "vendor", "employee", "contractor", "name"]),
                                payoutType: firstValue(record.fields, keys: ["type", "category", "payout_type"]),
                                date: parseDate(firstValue(record.fields, keys: ["date", "payment_date", "check_date"])),
                                amount: parseAmount(firstValue(record.fields, keys: ["amount", "total", "payment", "debit"])),
                                memo: firstValue(record.fields, keys: ["memo", "description", "notes"]),
                                rawJSON: encodeRaw(record.fields)
                            )
                            payoutsCount += 1
                        case .transaction:
                            try database.insertTransaction(
                                sessionID: sessionID,
                                sourceDocumentID: documentID,
                                date: parseDate(firstValue(record.fields, keys: ["date", "txn_date", "transaction_date"])),
                                payee: firstValue(record.fields, keys: ["payee", "name", "vendor", "customer"]),
                                memo: firstValue(record.fields, keys: ["memo", "description", "notes"]),
                                account: firstValue(record.fields, keys: ["account", "category", "account_name"]),
                                amount: parseAmount(firstValue(record.fields, keys: ["amount", "debit", "credit", "total"])),
                                rawJSON: encodeRaw(record.fields)
                            )
                            transactionsCount += 1
                        }
                    }
                }
            } catch {
                issuesCount += 1
                try database.insertIssue(
                    sessionID: sessionID,
                    level: "error",
                    message: "Import failure: \(error.localizedDescription)",
                    context: entry.relativePath
                )
            }
        }

        let summary =
            "docs=\(documentsCount), txns=\(transactionsCount), invoices=\(invoicesCount), payouts=\(payoutsCount), issues=\(issuesCount)"
        let finalStatus = issuesCount == 0 ? "completed" : "completed_with_issues"
        try database.finishImportSession(sessionID: sessionID, status: finalStatus, summary: summary)

        return ImportSummary(
            sessionID: sessionID,
            importedDocuments: documentsCount,
            importedTransactions: transactionsCount,
            importedInvoices: invoicesCount,
            importedPayouts: payoutsCount,
            issues: issuesCount
        )
    }

    private func resolveTransferRoot(from selectedURL: URL) throws -> URL {
        let fm = FileManager.default
        let candidate = selectedURL.appendingPathComponent("RenaissanceTransfer")
        if fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        if selectedURL.lastPathComponent == "RenaissanceTransfer" {
            return selectedURL
        }

        throw ImportServiceError.invalidTransferRoot
    }

    private func resolveStoredURL(for entry: ManifestEntry, transferRoot: URL) -> URL? {
        let fm = FileManager.default

        if let storedRelPath = entry.storedRelPath {
            let primary = transferRoot.appendingPathComponent(storedRelPath)
            if fm.fileExists(atPath: primary.path) {
                return primary
            }
        }

        let fallback = transferRoot.appendingPathComponent(entry.relativePath)
        if fm.fileExists(atPath: fallback.path) {
            return fallback
        }

        return nil
    }

    private func readText(from fileURL: URL) throws -> String {
        let data: Data
        if fileURL.pathExtension.lowercased() == "gz" {
            data = try runGunzip(fileURL)
        } else {
            data = try Data(contentsOf: fileURL)
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin = String(data: data, encoding: .isoLatin1) {
            return latin
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func runGunzip(_ fileURL: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", fileURL.path]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let err = error.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: err, encoding: .utf8) ?? "gunzip failed"
            throw NSError(domain: "ImportService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }

    private func firstValue(_ row: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = row[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return ""
    }

    private func parseAmount(_ raw: String) -> Double {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }

    private func parseDate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let formatters = [
            "MM/dd/yyyy",
            "M/d/yyyy",
            "yyyy-MM-dd",
            "MM-dd-yyyy",
            "M-d-yyyy",
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                let output = DateFormatter()
                output.locale = Locale(identifier: "en_US_POSIX")
                output.timeZone = TimeZone(secondsFromGMT: 0)
                output.dateFormat = "yyyy-MM-dd"
                return output.string(from: date)
            }
        }

        return trimmed
    }

    private func encodeRaw(_ row: [String: String]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "{}"
    }

    private func classifyCSV(relativePath: String) -> CSVImportKind {
        let lower = relativePath.lowercased()
        if lower.contains("invoice") {
            return .invoice
        }
        if lower.contains("payroll") ||
            lower.contains("contractor") ||
            lower.contains("owner") ||
            lower.contains("labor") ||
            lower.contains("1099")
        {
            return .payout
        }
        return .transaction
    }
}

private enum CSVImportKind {
    case transaction
    case invoice
    case payout
}

private struct TransferManifest: Decodable {
    let verifiedFiles: [ManifestVerifiedFile]?
    let files: [ManifestLegacyFile]?

    enum CodingKeys: String, CodingKey {
        case verifiedFiles = "verified_files"
        case files
    }

    var allEntries: [ManifestEntry] {
        if let verifiedFiles {
            return verifiedFiles.map {
                ManifestEntry(
                    category: $0.category,
                    relativePath: $0.relTarget,
                    storedRelPath: $0.storedRelPath,
                    sourcePath: $0.sourcePath,
                    sizeBytes: $0.sizeBytes,
                    sha256: $0.sourceSHA256
                )
            }
        }
        if let files {
            return files.map {
                ManifestEntry(
                    category: $0.category,
                    relativePath: $0.relativePath,
                    storedRelPath: $0.relativePath,
                    sourcePath: $0.sourcePath,
                    sizeBytes: $0.sizeBytes,
                    sha256: $0.sha256
                )
            }
        }
        return []
    }
}

private struct ManifestVerifiedFile: Decodable {
    let category: String
    let relTarget: String
    let storedRelPath: String
    let sourcePath: String
    let sizeBytes: Int64
    let sourceSHA256: String?

    enum CodingKeys: String, CodingKey {
        case category
        case relTarget = "rel_target"
        case storedRelPath = "stored_rel_path"
        case sourcePath = "source_path"
        case sizeBytes = "size_bytes"
        case sourceSHA256 = "source_sha256"
    }
}

private struct ManifestLegacyFile: Decodable {
    let category: String
    let relativePath: String
    let sourcePath: String
    let sizeBytes: Int64
    let sha256: String?

    enum CodingKeys: String, CodingKey {
        case category
        case relativePath = "relative_path"
        case sourcePath = "source_path"
        case sizeBytes = "size_bytes"
        case sha256
    }
}

private struct ManifestEntry {
    let category: String
    let relativePath: String
    let storedRelPath: String?
    let sourcePath: String
    let sizeBytes: Int64
    let sha256: String?
}
