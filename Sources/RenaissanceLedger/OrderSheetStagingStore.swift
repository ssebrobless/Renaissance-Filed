import CryptoKit
import Foundation
import SQLite3

private let ORDER_SHEET_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum OrderSheetStatus: String, Codable, CaseIterable {
    case pending
    case inReview = "in_review"
    case converted
    case discarded
}

enum OrderSheetApprovalError: LocalizedError {
    case missingCustomer
    case missingLines
    case testingModeEnabled

    var errorDescription: String? {
        switch self {
        case .missingCustomer:
            return "Select a customer before approving this order sheet."
        case .missingLines:
            return "Add at least one line item with description and amount before approval."
        case .testingModeEnabled:
            return "Order sheet testing mode is enabled, so approval into official estimates is blocked."
        }
    }
}

struct OrderSheetOCRLine: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let confidence: Double
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
}

struct OrderSheetDraftLine: Identifiable, Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id
        case selectedItemID
        case itemName
        case description
        case quantity
        case rate
        case reviewHint
    }

    var id: UUID = UUID()
    var selectedItemID: Int64 = 0
    var itemName: String = ""
    var description: String = ""
    var quantity: String = "1"
    var rate: String = ""
    var reviewHint: String = ""

    init(
        id: UUID = UUID(),
        selectedItemID: Int64 = 0,
        itemName: String = "",
        description: String = "",
        quantity: String = "1",
        rate: String = "",
        reviewHint: String = ""
    ) {
        self.id = id
        self.selectedItemID = selectedItemID
        self.itemName = itemName
        self.description = description
        self.quantity = quantity
        self.rate = rate
        self.reviewHint = reviewHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        selectedItemID = try container.decodeIfPresent(Int64.self, forKey: .selectedItemID) ?? 0
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? "1"
        rate = try container.decodeIfPresent(String.self, forKey: .rate) ?? ""
        reviewHint = try container.decodeIfPresent(String.self, forKey: .reviewHint) ?? ""
    }

    var amount: Double {
        let resolvedQuantity = Double(quantity) ?? 1
        let resolvedRate = Double(rate) ?? 0
        return resolvedQuantity * resolvedRate
    }

    func asInvoiceLineEntry() -> InvoiceLineEntry {
        InvoiceLineEntry(
            id: id,
            selectedItemID: selectedItemID,
            itemName: itemName,
            description: description,
            quantity: quantity,
            rate: rate,
            reviewHint: reviewHint
        )
    }

    static func from(_ line: InvoiceLineEntry) -> OrderSheetDraftLine {
        OrderSheetDraftLine(
            id: line.id,
            selectedItemID: line.selectedItemID,
            itemName: line.itemName,
            description: line.description,
            quantity: line.quantity,
            rate: line.rate,
            reviewHint: line.reviewHint
        )
    }

    static func blank() -> OrderSheetDraftLine {
        OrderSheetDraftLine()
    }
}

struct OrderSheetReviewDraft: Codable, Hashable {
    var customerID: Int64?
    var issueDate: String
    var validUntil: String
    var memo: String
    var status: String
    var lines: [OrderSheetDraftLine]

    static func emptyDefault(now: Date = Date()) -> OrderSheetReviewDraft {
        OrderSheetReviewDraft(
            customerID: nil,
            issueDate: DateFormatter.isoDate.string(from: now),
            validUntil: DateFormatter.isoDate.string(from: now.addingTimeInterval(30 * 86_400)),
            memo: "",
            status: "draft",
            lines: [.blank()]
        )
    }
}

struct OrderSheetRow: Identifiable, Hashable {
    let id: Int64
    let originalFilename: String
    let storedPath: String
    let sha256: String
    let ocrLines: [OrderSheetOCRLine]
    let reviewDraft: OrderSheetReviewDraft
    let status: OrderSheetStatus
    let linkedEstimateID: Int64?
    let createdAt: String
    let updatedAt: String

    var imageURL: URL { URL(fileURLWithPath: storedPath) }

    var ocrTranscript: String {
        ocrLines.map(\.text).joined(separator: "\n")
    }

    var ocrSummary: String {
        let lines = ocrLines
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(4)).joined(separator: "  •  ")
    }
}

enum OrderSheetImportResult {
    case imported(OrderSheetRow)
    case restaged(OrderSheetRow)
    case duplicate(OrderSheetRow)
}

final class OrderSheetStagingStore {
    static let shared = OrderSheetStagingStore()

    private var db: OpaquePointer?
    private let databaseURL: URL
    private let imagesDirectoryURL: URL

    private init() {
        let root = renaissanceLedgerSupportDirectory()
        databaseURL = root.appendingPathComponent("order-sheet-staging.sqlite")
        imagesDirectoryURL = root.appendingPathComponent("order_sheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
    }

    static func newWorker() -> OrderSheetStagingStore {
        OrderSheetStagingStore()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func fetchOrderSheets(
        statuses: [OrderSheetStatus]? = nil,
        linkedEstimateID: Int64? = nil
    ) throws -> [OrderSheetRow] {
        try open()
        let sql = """
            SELECT id, original_filename, stored_path, sha256, ocr_json, review_draft_json,
                   status, linked_estimate_id, created_at, updated_at
            FROM order_sheets
            ORDER BY updated_at DESC, id DESC
            """

        var rows: [OrderSheetRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let row = decodeRow(from: stmt)
                if let statuses, !statuses.contains(row.status) {
                    continue
                }
                if let linkedEstimateID, row.linkedEstimateID != linkedEstimateID {
                    continue
                }
                rows.append(row)
            }
        }
        return rows
    }

    func fetchOrderSheet(id: Int64) throws -> OrderSheetRow? {
        try open()
        let sql = """
            SELECT id, original_filename, stored_path, sha256, ocr_json, review_draft_json,
                   status, linked_estimate_id, created_at, updated_at
            FROM order_sheets
            WHERE id = ?
            LIMIT 1
            """

        var row: OrderSheetRow?
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                row = decodeRow(from: stmt)
            }
        }
        return row
    }

    func importOrderSheet(imageURL: URL) throws -> OrderSheetImportResult {
        try open()

        let data = try Data(contentsOf: imageURL)
        let sha256 = sha256Hex(for: data)
        if let existing = try fetchOrderSheet(sha256: sha256) {
            if existing.status == .discarded {
                let revivedDraft = existing.reviewDraft.lines.isEmpty ? OrderSheetReviewDraft.emptyDefault() : existing.reviewDraft
                try saveReviewDraft(id: existing.id, draft: revivedDraft, status: .pending)
                guard let refreshed = try fetchOrderSheet(id: existing.id) else {
                    throw DBError.stepFailed("Failed to reload restaged order sheet row.")
                }
                return .restaged(refreshed)
            }
            return .duplicate(existing)
        }

        let storedURL = try OrderSheetOCR.prepareStagedDocument(
            from: imageURL,
            sha256: sha256,
            destinationDirectory: imagesDirectoryURL
        )

        let ocrLines = try OrderSheetOCR.recognizeLines(in: storedURL)
        let draft = OrderSheetReviewDraft.emptyDefault()
        let now = isoNow()
        let sql = """
            INSERT INTO order_sheets(
                original_filename, stored_path, sha256, ocr_json, review_draft_json,
                status, linked_estimate_id, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?)
            """

        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: imageURL.lastPathComponent)
            bindText(stmt: stmt, index: 2, value: storedURL.path)
            bindText(stmt: stmt, index: 3, value: sha256)
            bindText(stmt: stmt, index: 4, value: encodeJSONString(ocrLines))
            bindText(stmt: stmt, index: 5, value: encodeJSONString(draft))
            bindText(stmt: stmt, index: 6, value: OrderSheetStatus.pending.rawValue)
            bindText(stmt: stmt, index: 7, value: now)
            bindText(stmt: stmt, index: 8, value: now)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }

        let rowID = sqlite3_last_insert_rowid(db)
        guard let row = try fetchOrderSheet(id: rowID) else {
            throw DBError.stepFailed("Failed to load imported order sheet row.")
        }
        return .imported(row)
    }

    func updateStatus(id: Int64, status: OrderSheetStatus) throws {
        try open()
        let sql = "UPDATE order_sheets SET status=?, updated_at=? WHERE id=?"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: status.rawValue)
            bindText(stmt: stmt, index: 2, value: isoNow())
            sqlite3_bind_int64(stmt, 3, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func saveReviewDraft(id: Int64, draft: OrderSheetReviewDraft, status: OrderSheetStatus? = nil) throws {
        try open()
        let sql = """
            UPDATE order_sheets
            SET review_draft_json = ?, status = COALESCE(?, status), updated_at = ?
            WHERE id = ?
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: encodeJSONString(draft))
            if let status {
                bindText(stmt: stmt, index: 2, value: status.rawValue)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            bindText(stmt: stmt, index: 3, value: isoNow())
            sqlite3_bind_int64(stmt, 4, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func saveOCRLines(id: Int64, ocrLines: [OrderSheetOCRLine]) throws {
        try open()
        let sql = """
            UPDATE order_sheets
            SET ocr_json = ?, updated_at = ?
            WHERE id = ?
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: encodeJSONString(ocrLines))
            bindText(stmt: stmt, index: 2, value: isoNow())
            sqlite3_bind_int64(stmt, 3, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func discardOrderSheet(id: Int64, draft: OrderSheetReviewDraft? = nil) throws {
        try open()
        let sql = """
            UPDATE order_sheets
            SET review_draft_json = COALESCE(?, review_draft_json),
                status = ?,
                updated_at = ?
            WHERE id = ?
            """
        try withStatement(sql) { stmt in
            if let draft {
                bindText(stmt: stmt, index: 1, value: encodeJSONString(draft))
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            bindText(stmt: stmt, index: 2, value: OrderSheetStatus.discarded.rawValue)
            bindText(stmt: stmt, index: 3, value: isoNow())
            sqlite3_bind_int64(stmt, 4, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func markConverted(id: Int64, linkedEstimateID: Int64, draft: OrderSheetReviewDraft) throws {
        try open()
        let sql = """
            UPDATE order_sheets
            SET review_draft_json = ?, status = ?, linked_estimate_id = ?, updated_at = ?
            WHERE id = ?
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: encodeJSONString(draft))
            bindText(stmt: stmt, index: 2, value: OrderSheetStatus.converted.rawValue)
            sqlite3_bind_int64(stmt, 3, linkedEstimateID)
            bindText(stmt: stmt, index: 4, value: isoNow())
            sqlite3_bind_int64(stmt, 5, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    private func fetchOrderSheet(sha256: String) throws -> OrderSheetRow? {
        let sql = """
            SELECT id, original_filename, stored_path, sha256, ocr_json, review_draft_json,
                   status, linked_estimate_id, created_at, updated_at
            FROM order_sheets
            WHERE sha256 = ?
            LIMIT 1
            """

        var row: OrderSheetRow?
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: sha256)
            if sqlite3_step(stmt) == SQLITE_ROW {
                row = decodeRow(from: stmt)
            }
        }
        return row
    }

    private func open() throws {
        if db != nil {
            return
        }

        let rc = sqlite3_open(databaseURL.path, &db)
        guard rc == SQLITE_OK else {
            throw DBError.openFailed(lastErrorMessage)
        }

        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    private func migrate() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS order_sheets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                original_filename TEXT NOT NULL,
                stored_path TEXT NOT NULL,
                sha256 TEXT NOT NULL UNIQUE,
                ocr_json TEXT NOT NULL DEFAULT '[]',
                review_draft_json TEXT NOT NULL DEFAULT '{}',
                status TEXT NOT NULL DEFAULT 'pending',
                linked_estimate_id INTEGER,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_order_sheets_status
            ON order_sheets(status);

            CREATE INDEX IF NOT EXISTS idx_order_sheets_linked_estimate
            ON order_sheets(linked_estimate_id);
            """
        )
    }

    private func decodeRow(from stmt: OpaquePointer?) -> OrderSheetRow {
        let ocrJSONString = columnText(stmt, 4)
        let draftJSONString = columnText(stmt, 5)
        let rawLinkedEstimateID = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7)

        return OrderSheetRow(
            id: sqlite3_column_int64(stmt, 0),
            originalFilename: columnText(stmt, 1),
            storedPath: columnText(stmt, 2),
            sha256: columnText(stmt, 3),
            ocrLines: decodeOCRLines(ocrJSONString),
            reviewDraft: decodeDraft(draftJSONString),
            status: OrderSheetStatus(rawValue: columnText(stmt, 6)) ?? .pending,
            linkedEstimateID: rawLinkedEstimateID,
            createdAt: columnText(stmt, 8),
            updatedAt: columnText(stmt, 9)
        )
    }

    private func decodeOCRLines(_ json: String) -> [OrderSheetOCRLine] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([OrderSheetOCRLine].self, from: data)) ?? []
    }

    private func decodeDraft(_ json: String) -> OrderSheetReviewDraft {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(OrderSheetReviewDraft.self, from: data)
        else {
            return .emptyDefault()
        }
        if decoded.lines.isEmpty {
            var repaired = decoded
            repaired.lines = [.blank()]
            return repaired
        }
        return decoded
    }

    private func encodeJSONString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DBError.executeFailed(lastErrorMessage)
        }
    }

    private func withStatement(_ sql: String, body: (OpaquePointer?) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    private func bindText(stmt: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(stmt, index, value, -1, ORDER_SHEET_SQLITE_TRANSIENT)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private var lastErrorMessage: String {
        guard let db, let cString = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: cString)
    }
}

func renaissanceLedgerSupportDirectory() -> URL {
    if let override = ProcessInfo.processInfo.environment["RENAISSANCE_LEDGER_SUPPORT_DIR"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        let expanded = (override as NSString).expandingTildeInPath
        let root = URL(fileURLWithPath: expanded, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    let root = support.appendingPathComponent("RenaissanceLedger", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
