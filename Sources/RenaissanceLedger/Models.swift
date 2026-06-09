import Foundation

struct ImportSummary {
    let sessionID: Int64
    let importedDocuments: Int
    let importedTransactions: Int
    let importedInvoices: Int
    let importedPayouts: Int
    let issues: Int
}

struct ImportSessionRow: Identifiable {
    let id: Int64
    let startedAt: String
    let transferRoot: String
    let status: String
    let summary: String
}

struct TransactionRow: Identifiable {
    let id: Int64
    let date: String
    let payee: String
    let memo: String
    let account: String
    let amount: Double
    let sourceDocumentID: Int64?
}

struct InvoiceRow: Identifiable {
    let id: Int64
    let invoiceNumber: String
    let customer: String
    let issueDate: String
    let dueDate: String
    let amount: Double
    let status: String
    let sourceDocumentID: Int64?
}

struct PayoutRow: Identifiable {
    let id: Int64
    let payee: String
    let payoutType: String
    let date: String
    let amount: Double
    let memo: String
    let sourceDocumentID: Int64?
}

struct DocumentRow: Identifiable {
    let id: Int64
    let category: String
    let relativePath: String
    let storedPath: String
    let sourcePath: String
    let sha256: String
    let sizeBytes: Int64
    let importedAt: String
    var documentFileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }
}

struct ImportIssueRow: Identifiable {
    let id: Int64
    let level: String
    let message: String
    let context: String
    let createdAt: String
}

struct CSVRecord {
    let fields: [String: String]
}
