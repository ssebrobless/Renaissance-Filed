import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

final class SQLiteDatabase {
    static let shared = SQLiteDatabase()

    private var db: OpaquePointer?
    private let databaseURL: URL

    private init() {
        if let override = ProcessInfo.processInfo.environment["RENAISSANCE_LEDGER_DB_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: false)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.databaseURL = url
            return
        }

        let root = renaissanceLedgerSupportDirectory()
        self.databaseURL = root.appendingPathComponent("ledger.sqlite")
    }

    /// Test-only initializer targeting an explicit on-disk database file, so unit tests
    /// can run against an isolated temporary database instead of the shared singleton.
    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func open() throws {
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
        try migrateNative()
        try migrateV2()
        try migrateV3()
        try migrateV4()
        try migrateV5()
        try migrateV6()
        try migrateV7()
        try migrateV8()
        try migrateV9()
        try migrateV10()
        try migrateV11()
        try migrateV12()
        try migrateV13()
        try migrateV14()
        try migrateV15()
        try migrateV16()
        try seedDefaultAccounts()
        try migrateV17()
        try migrateV18()
        try migrateV19()
        try migrateV20()
        try migrateV21()
        try migrateV22()
        try migrateV23()
        try migrateV24()
        try migrateV25()
        try migrateV26()
        try migrateV27()
    }

    func migrate() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS import_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                transfer_root TEXT NOT NULL,
                status TEXT NOT NULL,
                summary TEXT NOT NULL DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS documents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES import_sessions(id) ON DELETE CASCADE,
                category TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                stored_path TEXT NOT NULL,
                source_path TEXT NOT NULL,
                sha256 TEXT,
                size_bytes INTEGER NOT NULL DEFAULT 0,
                imported_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES import_sessions(id) ON DELETE CASCADE,
                source_document_id INTEGER REFERENCES documents(id) ON DELETE SET NULL,
                txn_date TEXT,
                payee TEXT,
                memo TEXT,
                account TEXT,
                amount REAL NOT NULL DEFAULT 0,
                raw_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS invoices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES import_sessions(id) ON DELETE CASCADE,
                source_document_id INTEGER REFERENCES documents(id) ON DELETE SET NULL,
                invoice_number TEXT,
                customer TEXT,
                issue_date TEXT,
                due_date TEXT,
                amount REAL NOT NULL DEFAULT 0,
                status TEXT,
                raw_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS payouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES import_sessions(id) ON DELETE CASCADE,
                source_document_id INTEGER REFERENCES documents(id) ON DELETE SET NULL,
                payee TEXT,
                payout_type TEXT,
                payout_date TEXT,
                amount REAL NOT NULL DEFAULT 0,
                memo TEXT,
                raw_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS import_issues (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES import_sessions(id) ON DELETE CASCADE,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                context TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """
        )
    }

    func beginImportSession(transferRoot: String) throws -> Int64 {
        let sql = "INSERT INTO import_sessions(started_at, transfer_root, status, summary) VALUES (?, ?, 'running', '')"
        let now = isoNow()
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: now)
            bindText(stmt: stmt, index: 2, value: transferRoot)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    func finishImportSession(sessionID: Int64, status: String, summary: String) throws {
        let sql = "UPDATE import_sessions SET ended_at=?, status=?, summary=? WHERE id=?"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: isoNow())
            bindText(stmt: stmt, index: 2, value: status)
            bindText(stmt: stmt, index: 3, value: summary)
            sqlite3_bind_int64(stmt, 4, sessionID)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func insertDocument(
        sessionID: Int64,
        category: String,
        relativePath: String,
        storedPath: String,
        sourcePath: String,
        sha256: String?,
        sizeBytes: Int64
    ) throws -> Int64 {
        let sql =
            "INSERT INTO documents(session_id, category, relative_path, stored_path, source_path, sha256, size_bytes, imported_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, sessionID)
            bindText(stmt: stmt, index: 2, value: category)
            bindText(stmt: stmt, index: 3, value: relativePath)
            bindText(stmt: stmt, index: 4, value: storedPath)
            bindText(stmt: stmt, index: 5, value: sourcePath)
            if let sha256 {
                bindText(stmt: stmt, index: 6, value: sha256)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_int64(stmt, 7, sizeBytes)
            bindText(stmt: stmt, index: 8, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    func insertTransaction(
        sessionID: Int64,
        sourceDocumentID: Int64,
        date: String?,
        payee: String,
        memo: String,
        account: String,
        amount: Double,
        rawJSON: String
    ) throws {
        let sql =
            "INSERT INTO transactions(session_id, source_document_id, txn_date, payee, memo, account, amount, raw_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, sessionID)
            sqlite3_bind_int64(stmt, 2, sourceDocumentID)
            bindOptionalText(stmt: stmt, index: 3, value: date)
            bindText(stmt: stmt, index: 4, value: payee)
            bindText(stmt: stmt, index: 5, value: memo)
            bindText(stmt: stmt, index: 6, value: account)
            sqlite3_bind_double(stmt, 7, amount)
            bindText(stmt: stmt, index: 8, value: rawJSON)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func insertInvoice(
        sessionID: Int64,
        sourceDocumentID: Int64,
        invoiceNumber: String,
        customer: String,
        issueDate: String?,
        dueDate: String?,
        amount: Double,
        status: String,
        rawJSON: String
    ) throws {
        let sql =
            "INSERT INTO invoices(session_id, source_document_id, invoice_number, customer, issue_date, due_date, amount, status, raw_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, sessionID)
            sqlite3_bind_int64(stmt, 2, sourceDocumentID)
            bindText(stmt: stmt, index: 3, value: invoiceNumber)
            bindText(stmt: stmt, index: 4, value: customer)
            bindOptionalText(stmt: stmt, index: 5, value: issueDate)
            bindOptionalText(stmt: stmt, index: 6, value: dueDate)
            sqlite3_bind_double(stmt, 7, amount)
            bindText(stmt: stmt, index: 8, value: status)
            bindText(stmt: stmt, index: 9, value: rawJSON)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func insertPayout(
        sessionID: Int64,
        sourceDocumentID: Int64,
        payee: String,
        payoutType: String,
        date: String?,
        amount: Double,
        memo: String,
        rawJSON: String
    ) throws {
        let sql =
            "INSERT INTO payouts(session_id, source_document_id, payee, payout_type, payout_date, amount, memo, raw_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, sessionID)
            sqlite3_bind_int64(stmt, 2, sourceDocumentID)
            bindText(stmt: stmt, index: 3, value: payee)
            bindText(stmt: stmt, index: 4, value: payoutType)
            bindOptionalText(stmt: stmt, index: 5, value: date)
            sqlite3_bind_double(stmt, 6, amount)
            bindText(stmt: stmt, index: 7, value: memo)
            bindText(stmt: stmt, index: 8, value: rawJSON)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func insertIssue(sessionID: Int64, level: String, message: String, context: String) throws {
        let sql = "INSERT INTO import_issues(session_id, level, message, context, created_at) VALUES (?, ?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, sessionID)
            bindText(stmt: stmt, index: 2, value: level)
            bindText(stmt: stmt, index: 3, value: message)
            bindText(stmt: stmt, index: 4, value: context)
            bindText(stmt: stmt, index: 5, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func fetchImportSessions(limit: Int = 50) throws -> [ImportSessionRow] {
        let sql =
            "SELECT id, started_at, transfer_root, status, summary FROM import_sessions ORDER BY id DESC LIMIT ?"
        var rows: [ImportSessionRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    ImportSessionRow(
                        id: sqlite3_column_int64(stmt, 0),
                        startedAt: columnText(stmt, 1),
                        transferRoot: columnText(stmt, 2),
                        status: columnText(stmt, 3),
                        summary: columnText(stmt, 4)
                    )
                )
            }
        }
        return rows
    }

    func fetchTransactions(search: String = "", limit: Int = 500) throws -> [TransactionRow] {
        let sql =
            """
            SELECT id, COALESCE(txn_date, ''), COALESCE(payee, ''), COALESCE(memo, ''),
                   COALESCE(account, ''), amount, source_document_id
            FROM transactions
            WHERE (? = '' OR lower(payee) LIKE ? OR lower(memo) LIKE ? OR lower(account) LIKE ?)
            ORDER BY COALESCE(txn_date, '') DESC, id DESC
            LIMIT ?
            """
        let like = "%\(search.lowercased())%"
        var rows: [TransactionRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            sqlite3_bind_int(stmt, 5, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let sourceDocID = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6)
                rows.append(
                    TransactionRow(
                        id: sqlite3_column_int64(stmt, 0),
                        date: columnText(stmt, 1),
                        payee: columnText(stmt, 2),
                        memo: columnText(stmt, 3),
                        account: columnText(stmt, 4),
                        amount: sqlite3_column_double(stmt, 5),
                        sourceDocumentID: sourceDocID
                    )
                )
            }
        }
        return rows
    }

    func fetchInvoices(search: String = "", limit: Int = 500) throws -> [InvoiceRow] {
        let sql =
            """
            SELECT id, COALESCE(invoice_number, ''), COALESCE(customer, ''),
                   COALESCE(issue_date, ''), COALESCE(due_date, ''), amount,
                   COALESCE(status, ''), source_document_id
            FROM invoices
            WHERE (? = '' OR lower(invoice_number) LIKE ? OR lower(customer) LIKE ?)
            ORDER BY COALESCE(issue_date, '') DESC, id DESC
            LIMIT ?
            """
        let like = "%\(search.lowercased())%"
        var rows: [InvoiceRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            sqlite3_bind_int(stmt, 4, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let sourceDocID = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7)
                rows.append(
                    InvoiceRow(
                        id: sqlite3_column_int64(stmt, 0),
                        invoiceNumber: columnText(stmt, 1),
                        customer: columnText(stmt, 2),
                        issueDate: columnText(stmt, 3),
                        dueDate: columnText(stmt, 4),
                        amount: sqlite3_column_double(stmt, 5),
                        status: columnText(stmt, 6),
                        sourceDocumentID: sourceDocID
                    )
                )
            }
        }
        return rows
    }

    func fetchPayouts(search: String = "", limit: Int = 500) throws -> [PayoutRow] {
        let sql =
            """
            SELECT id, COALESCE(payee, ''), COALESCE(payout_type, ''),
                   COALESCE(payout_date, ''), amount, COALESCE(memo, ''), source_document_id
            FROM payouts
            WHERE (? = '' OR lower(payee) LIKE ? OR lower(payout_type) LIKE ? OR lower(memo) LIKE ?)
            ORDER BY COALESCE(payout_date, '') DESC, id DESC
            LIMIT ?
            """
        let like = "%\(search.lowercased())%"
        var rows: [PayoutRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            sqlite3_bind_int(stmt, 5, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let sourceDocID = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6)
                rows.append(
                    PayoutRow(
                        id: sqlite3_column_int64(stmt, 0),
                        payee: columnText(stmt, 1),
                        payoutType: columnText(stmt, 2),
                        date: columnText(stmt, 3),
                        amount: sqlite3_column_double(stmt, 4),
                        memo: columnText(stmt, 5),
                        sourceDocumentID: sourceDocID
                    )
                )
            }
        }
        return rows
    }

    func fetchDocuments(search: String = "", limit: Int = 1000) throws -> [DocumentRow] {
        let sql =
            """
            SELECT id, category, relative_path, stored_path, source_path,
                   COALESCE(sha256, ''), size_bytes, imported_at
            FROM documents
            WHERE (? = '' OR lower(relative_path) LIKE ? OR lower(source_path) LIKE ?)
            ORDER BY id DESC
            LIMIT ?
            """
        let like = "%\(search.lowercased())%"
        var rows: [DocumentRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            sqlite3_bind_int(stmt, 4, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    DocumentRow(
                        id: sqlite3_column_int64(stmt, 0),
                        category: columnText(stmt, 1),
                        relativePath: columnText(stmt, 2),
                        storedPath: columnText(stmt, 3),
                        sourcePath: columnText(stmt, 4),
                        sha256: columnText(stmt, 5),
                        sizeBytes: sqlite3_column_int64(stmt, 6),
                        importedAt: columnText(stmt, 7)
                    )
                )
            }
        }
        return rows
    }

    func fetchIssues(limit: Int = 200) throws -> [ImportIssueRow] {
        let sql = "SELECT id, level, message, context, created_at FROM import_issues ORDER BY id DESC LIMIT ?"
        var rows: [ImportIssueRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    ImportIssueRow(
                        id: sqlite3_column_int64(stmt, 0),
                        level: columnText(stmt, 1),
                        message: columnText(stmt, 2),
                        context: columnText(stmt, 3),
                        createdAt: columnText(stmt, 4)
                    )
                )
            }
        }
        return rows
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DBError.executeFailed(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        if let cMessage = sqlite3_errmsg(db) {
            return String(cString: cMessage)
        }
        return "Unknown SQLite error"
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    private func bindOptionalText(stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value, !value.isEmpty {
            bindText(stmt: stmt, index: index, value: value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt64(stmt: OpaquePointer?, index: Int32, value: Int64?) {
        if let value, value != 0 {
            sqlite3_bind_int64(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindText(stmt: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private static func normalizeEstimateProgressText(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func bestEstimateProgressMatch<T>(
        candidates: [(offset: Int, element: T)],
        targetAmount: Double,
        remainingAmount: (T) -> Double,
        descriptionLength: (T) -> Int
    ) -> Int? {
        candidates.min { left, right in
            let leftAmountDelta = abs(remainingAmount(left.element) - targetAmount)
            let rightAmountDelta = abs(remainingAmount(right.element) - targetAmount)
            if abs(leftAmountDelta - rightAmountDelta) > 0.01 {
                return leftAmountDelta < rightAmountDelta
            }

            let leftDescriptionLength = descriptionLength(left.element)
            let rightDescriptionLength = descriptionLength(right.element)
            if leftDescriptionLength != rightDescriptionLength {
                return leftDescriptionLength > rightDescriptionLength
            }

            return left.offset < right.offset
        }?.offset
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Native Data Schema

    func migrateNative() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS gl_accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                number TEXT NOT NULL DEFAULT '',
                is_active INTEGER NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS customers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                company TEXT NOT NULL DEFAULT '',
                primary_contact TEXT NOT NULL DEFAULT '',
                email TEXT NOT NULL DEFAULT '',
                phone TEXT NOT NULL DEFAULT '',
                address TEXT NOT NULL DEFAULT '',
                city TEXT NOT NULL DEFAULT '',
                state TEXT NOT NULL DEFAULT '',
                zip TEXT NOT NULL DEFAULT '',
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS vendors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                company TEXT NOT NULL DEFAULT '',
                primary_contact TEXT NOT NULL DEFAULT '',
                phone TEXT NOT NULL DEFAULT '',
                address TEXT NOT NULL DEFAULT '',
                is_1099 INTEGER NOT NULL DEFAULT 0,
                is_internal_self INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS native_invoices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                invoice_number TEXT NOT NULL,
                customer_id INTEGER NOT NULL REFERENCES customers(id),
                issue_date TEXT NOT NULL,
                due_date TEXT NOT NULL DEFAULT '',
                memo TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'open',
                total REAL NOT NULL DEFAULT 0,
                paid REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS invoice_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                invoice_id INTEGER NOT NULL REFERENCES native_invoices(id) ON DELETE CASCADE,
                description TEXT NOT NULL DEFAULT '',
                quantity REAL NOT NULL DEFAULT 1,
                rate REAL NOT NULL DEFAULT 0,
                amount REAL NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                vendor_id INTEGER REFERENCES vendors(id),
                vendor_name_override TEXT NOT NULL DEFAULT '',
                expense_date TEXT NOT NULL,
                amount REAL NOT NULL DEFAULT 0,
                account_id INTEGER REFERENCES gl_accounts(id),
                payment_account_id INTEGER REFERENCES gl_accounts(id),
                check_number TEXT NOT NULL DEFAULT '',
                memo TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS payments_received (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                customer_id INTEGER REFERENCES customers(id),
                invoice_id INTEGER REFERENCES native_invoices(id),
                payment_date TEXT NOT NULL,
                amount REAL NOT NULL DEFAULT 0,
                method TEXT NOT NULL DEFAULT 'check',
                reference TEXT NOT NULL DEFAULT '',
                memo TEXT NOT NULL DEFAULT '',
                deposit_account_id INTEGER REFERENCES gl_accounts(id),
                created_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS service_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                description TEXT NOT NULL DEFAULT '',
                income_account_id INTEGER REFERENCES gl_accounts(id),
                unit_price REAL NOT NULL DEFAULT 0.0,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            """
        )
    }

    func migrateV2() throws {
        // Add ein column to vendors if not already present (ignore if duplicate)
        sqlite3_exec(db, "ALTER TABLE vendors ADD COLUMN ein TEXT NOT NULL DEFAULT ''", nil, nil, nil)
    }

    func seedDefaultAccounts() throws {
        var count: Int32 = 0
        try withStatement("SELECT COUNT(*) FROM gl_accounts") { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int(stmt, 0)
            }
        }
        guard count == 0 else { return }

        let accounts: [(String, String, String)] = [
            // (name, type, number)
            ("Tile Installation Services", "income", "4000"),
            ("Material Sales", "income", "4100"),
            ("Other Income", "income", "4900"),
            ("Accounts Receivable", "asset", "1200"),
            ("Undeposited Funds", "asset", "1210"),
            ("Materials & Supplies", "expense", "5000"),
            ("Subcontractor Labor", "expense", "5100"),
            ("Employee Labor", "expense", "5200"),
            ("Vehicle & Fuel", "expense", "5300"),
            ("Tools & Equipment", "expense", "5400"),
            ("Insurance", "expense", "5500"),
            ("Rent & Storage", "expense", "5600"),
            ("Office & Admin", "expense", "5700"),
            ("Utilities", "expense", "5800"),
            ("Other Expenses", "expense", "5900"),
            ("Checking Account", "asset", "1000"),
            ("Savings Account", "asset", "1100"),
            ("Accounts Payable", "liability", "2000"),
            ("Owner's Equity", "equity", "3000"),
            ("Owner's Draw", "equity", "3100"),
        ]
        for (name, type, number) in accounts {
            let sql = "INSERT INTO gl_accounts(name, type, number) VALUES (?, ?, ?)"
            try withStatement(sql) { stmt in
                bindText(stmt: stmt, index: 1, value: name)
                bindText(stmt: stmt, index: 2, value: type)
                bindText(stmt: stmt, index: 3, value: number)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
        }
    }

    // MARK: - Accounts

    func fetchAccounts(type: String? = nil) throws -> [AccountRow] {
        let sql: String
        if let type {
            sql = "SELECT id, name, type, number FROM gl_accounts WHERE type = '\(type)' AND is_active = 1 ORDER BY number"
        } else {
            sql = "SELECT id, name, type, number FROM gl_accounts WHERE is_active = 1 ORDER BY type, number"
        }
        var rows: [AccountRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(AccountRow(
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    type: columnText(stmt, 2),
                    number: columnText(stmt, 3)
                ))
            }
        }
        return rows
    }

    func fetchPaymentTerms() throws -> [PaymentTermRow] {
        let sql = """
            SELECT id, name, refnum, due_days, min_days, discount_percent, discount_days, terms_type
            FROM payment_terms
            ORDER BY name
            """
        var rows: [PaymentTermRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    PaymentTermRow(
                        id: sqlite3_column_int64(stmt, 0),
                        name: columnText(stmt, 1),
                        refnum: columnText(stmt, 2),
                        dueDays: Int(sqlite3_column_int(stmt, 3)),
                        minDays: Int(sqlite3_column_int(stmt, 4)),
                        discountPercent: sqlite3_column_double(stmt, 5),
                        discountDays: Int(sqlite3_column_int(stmt, 6)),
                        termsType: columnText(stmt, 7)
                    )
                )
            }
        }
        return rows
    }

    func fetchPaymentMethods() throws -> [PaymentMethodRow] {
        let sql = "SELECT id, name, refnum FROM payment_methods ORDER BY name"
        var rows: [PaymentMethodRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    PaymentMethodRow(
                        id: sqlite3_column_int64(stmt, 0),
                        name: columnText(stmt, 1),
                        refnum: columnText(stmt, 2)
                    )
                )
            }
        }
        return rows
    }

    // MARK: - Customers

    func fetchCustomers(search: String = "") throws -> [CustomerRow] {
        let sql = """
            SELECT id, name, company, primary_contact, email, phone, address, city, state, zip, COALESCE(created_at, '')
            FROM customers
            WHERE is_active = 1
              AND (? = '' OR lower(name) LIKE ? OR lower(company) LIKE ? OR lower(primary_contact) LIKE ? OR phone LIKE ?)
            ORDER BY name
            """
        let like = "%\(search.lowercased())%"
        var rows: [CustomerRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            bindText(stmt: stmt, index: 5, value: like)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(CustomerRow(
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    company: columnText(stmt, 2),
                    primaryContact: columnText(stmt, 3),
                    email: columnText(stmt, 4),
                    phone: columnText(stmt, 5),
                    address: columnText(stmt, 6),
                    city: columnText(stmt, 7),
                    state: columnText(stmt, 8),
                    zip: columnText(stmt, 9),
                    createdAt: columnText(stmt, 10)
                ))
            }
        }
        return rows
    }

    func fetchJobs(customerID: Int64? = nil, includeInactive: Bool = false) throws -> [JobRow] {
        let sql = """
            SELECT j.id,
                   j.customer_id,
                   COALESCE(c.name, ''),
                   j.name,
                   j.status,
                   j.site_address,
                   j.notes,
                   COALESCE(j.is_active, 1),
                   COALESCE(j.created_at, '')
            FROM jobs j
            LEFT JOIN customers c ON c.id = j.customer_id
            WHERE (? IS NULL OR j.customer_id = ?)
              AND (? = 1 OR COALESCE(j.is_active, 1) = 1)
            ORDER BY COALESCE(c.name, ''), j.name, j.id
            """
        var rows: [JobRow] = []
        try withStatement(sql) { stmt in
            if let customerID {
                sqlite3_bind_int64(stmt, 1, customerID)
                sqlite3_bind_int64(stmt, 2, customerID)
            } else {
                sqlite3_bind_null(stmt, 1)
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_int(stmt, 3, includeInactive ? 1 : 0)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(JobRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerID: sqlite3_column_int64(stmt, 1),
                    customerName: columnText(stmt, 2),
                    name: columnText(stmt, 3),
                    status: columnText(stmt, 4),
                    siteAddress: columnText(stmt, 5),
                    notes: columnText(stmt, 6),
                    isActive: sqlite3_column_int(stmt, 7) != 0,
                    createdAt: columnText(stmt, 8)
                ))
            }
        }
        return rows
    }

    @discardableResult
    func insertJob(
        customerID: Int64,
        name: String,
        status: String,
        siteAddress: String,
        notes: String,
        isActive: Bool = true
    ) throws -> Int64 {
        let sql = """
            INSERT INTO jobs(customer_id, name, status, site_address, notes, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            bindText(stmt: stmt, index: 2, value: name)
            bindText(stmt: stmt, index: 3, value: status)
            bindText(stmt: stmt, index: 4, value: siteAddress)
            bindText(stmt: stmt, index: 5, value: notes)
            sqlite3_bind_int(stmt, 6, isActive ? 1 : 0)
            bindText(stmt: stmt, index: 7, value: isoNow())
            bindText(stmt: stmt, index: 8, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    func updateJob(
        id: Int64,
        name: String,
        status: String,
        siteAddress: String,
        notes: String,
        isActive: Bool
    ) throws {
        let sql = """
            UPDATE jobs
            SET name = ?,
                status = ?,
                site_address = ?,
                notes = ?,
                is_active = ?,
                updated_at = ?
            WHERE id = ?
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: status)
            bindText(stmt: stmt, index: 3, value: siteAddress)
            bindText(stmt: stmt, index: 4, value: notes)
            sqlite3_bind_int(stmt, 5, isActive ? 1 : 0)
            bindText(stmt: stmt, index: 6, value: isoNow())
            sqlite3_bind_int64(stmt, 7, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    @discardableResult
    func insertCustomer(
        name: String, company: String, primaryContact: String, email: String, phone: String,
        address: String, city: String, state: String, zip: String
    ) throws -> Int64 {
        let sql = """
            INSERT INTO customers(name, company, primary_contact, email, phone, address, city, state, zip, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: company)
            bindText(stmt: stmt, index: 3, value: primaryContact)
            bindText(stmt: stmt, index: 4, value: email)
            bindText(stmt: stmt, index: 5, value: phone)
            bindText(stmt: stmt, index: 6, value: address)
            bindText(stmt: stmt, index: 7, value: city)
            bindText(stmt: stmt, index: 8, value: state)
            bindText(stmt: stmt, index: 9, value: zip)
            bindText(stmt: stmt, index: 10, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - Vendors

    func fetchVendors(search: String = "") throws -> [VendorRow] {
        let sql = """
            SELECT id, name, company, primary_contact, phone, is_1099, address, COALESCE(ein, ''), COALESCE(is_internal_self, 0), COALESCE(created_at, '')
            FROM vendors
            WHERE is_active = 1
              AND (? = '' OR lower(name) LIKE ? OR lower(company) LIKE ? OR lower(primary_contact) LIKE ?)
            ORDER BY name
            """
        let like = "%\(search.lowercased())%"
        var rows: [VendorRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(VendorRow(
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    company: columnText(stmt, 2),
                    primaryContact: columnText(stmt, 3),
                    phone: columnText(stmt, 4),
                    address: columnText(stmt, 6),
                    ein: columnText(stmt, 7),
                    is1099: sqlite3_column_int(stmt, 5) != 0,
                    isInternalSelf: sqlite3_column_int(stmt, 8) != 0,
                    createdAt: columnText(stmt, 9)
                ))
            }
        }
        return rows
    }

    @discardableResult
    func insertVendor(name: String, company: String, primaryContact: String, phone: String, address: String, ein: String = "", is1099: Bool, isInternalSelf: Bool) throws -> Int64 {
        let sql = "INSERT INTO vendors(name, company, primary_contact, phone, address, ein, is_1099, is_internal_self, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: company)
            bindText(stmt: stmt, index: 3, value: primaryContact)
            bindText(stmt: stmt, index: 4, value: phone)
            bindText(stmt: stmt, index: 5, value: address)
            bindText(stmt: stmt, index: 6, value: ein)
            sqlite3_bind_int(stmt, 7, is1099 ? 1 : 0)
            sqlite3_bind_int(stmt, 8, isInternalSelf ? 1 : 0)
            bindText(stmt: stmt, index: 9, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    func updateVendor(id: Int64, name: String, company: String, primaryContact: String, phone: String, address: String, ein: String, is1099: Bool, isInternalSelf: Bool) throws {
        let sql = "UPDATE vendors SET name=?, company=?, primary_contact=?, phone=?, address=?, ein=?, is_1099=?, is_internal_self=? WHERE id=?"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: company)
            bindText(stmt: stmt, index: 3, value: primaryContact)
            bindText(stmt: stmt, index: 4, value: phone)
            bindText(stmt: stmt, index: 5, value: address)
            bindText(stmt: stmt, index: 6, value: ein)
            sqlite3_bind_int(stmt, 7, is1099 ? 1 : 0)
            sqlite3_bind_int(stmt, 8, isInternalSelf ? 1 : 0)
            sqlite3_bind_int64(stmt, 9, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func deleteVendor(id: Int64) throws {
        let sql = "UPDATE vendors SET is_active=0 WHERE id=?"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    // MARK: - Service Items

    func fetchServiceItems() throws -> [ServiceItemRow] {
        let sql = "SELECT id, name, description, COALESCE(income_account_id, 0), unit_price FROM service_items WHERE is_active = 1 ORDER BY name"
        var rows: [ServiceItemRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ServiceItemRow(
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    description: columnText(stmt, 2),
                    incomeAccountID: sqlite3_column_int64(stmt, 3),
                    unitPrice: sqlite3_column_double(stmt, 4)
                ))
            }
        }
        return rows
    }

    @discardableResult
    func insertServiceItem(name: String, description: String, incomeAccountID: Int64?, unitPrice: Double) throws -> Int64 {
        let sql = "INSERT INTO service_items(name, description, income_account_id, unit_price) VALUES (?, ?, ?, ?)"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: description)
            if let aid = incomeAccountID { sqlite3_bind_int64(stmt, 3, aid) } else { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_double(stmt, 4, unitPrice)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - Estimates

    func nextEstimateNumber() throws -> String {
        let year = Calendar.current.component(.year, from: Date())
        let prefix = "EST-\(year)-"
        var count: Int32 = 0
        try withStatement("SELECT COUNT(*) FROM estimates WHERE estimate_number LIKE ?") { stmt in
            bindText(stmt: stmt, index: 1, value: "\(prefix)%")
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int(stmt, 0)
            }
        }
        return String(format: "%@%03d", prefix, count + 1)
    }

    func fetchEstimates(search: String = "") throws -> [EstimateRow] {
        let sql = """
            SELECT e.id, e.estimate_number, e.customer_id, COALESCE(c.name, ''),
                   COALESCE(e.job_id, 0), COALESCE(j.name, ''),
                   e.issue_date, e.valid_until, e.memo, e.status, e.total, COALESCE(e.linked_invoice_id, 0), COALESCE(e.customer_name_override, '')
            FROM estimates e
            LEFT JOIN customers c ON e.customer_id = c.id
            LEFT JOIN jobs j ON e.job_id = j.id
            WHERE (? = '' OR lower(e.estimate_number) LIKE ? OR lower(c.name) LIKE ? OR lower(COALESCE(j.name, '')) LIKE ?)
            ORDER BY e.issue_date DESC, e.id DESC
            LIMIT 500
            """
        let like = "%\(search.lowercased())%"
        var rows: [EstimateRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(EstimateRow(
                    id: sqlite3_column_int64(stmt, 0),
                    estimateNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    validUntil: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    linkedInvoiceID: sqlite3_column_int64(stmt, 11)
                ))
            }
        }
        return rows
    }

    func fetchEstimate(id: Int64) throws -> EstimateRow? {
        let sql = """
            SELECT e.id, e.estimate_number, e.customer_id, COALESCE(c.name, ''),
                   COALESCE(e.job_id, 0), COALESCE(j.name, ''),
                   e.issue_date, e.valid_until, e.memo, e.status, e.total, COALESCE(e.linked_invoice_id, 0), COALESCE(e.customer_name_override, '')
            FROM estimates e
            LEFT JOIN customers c ON e.customer_id = c.id
            LEFT JOIN jobs j ON e.job_id = j.id
            WHERE e.id = ?
            LIMIT 1
            """
        var row: EstimateRow?
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                row = EstimateRow(
                    id: sqlite3_column_int64(stmt, 0),
                    estimateNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    validUntil: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    linkedInvoiceID: sqlite3_column_int64(stmt, 11)
                )
            }
        }
        return row
    }

    func fetchCustomerEstimates(customerID: Int64) throws -> [EstimateRow] {
        let sql = """
            SELECT e.id, e.estimate_number, e.customer_id, COALESCE(c.name, ''),
                   COALESCE(e.job_id, 0), COALESCE(j.name, ''),
                   e.issue_date, e.valid_until, e.memo, e.status, e.total, COALESCE(e.linked_invoice_id, 0), COALESCE(e.customer_name_override, '')
            FROM estimates e
            LEFT JOIN customers c ON e.customer_id = c.id
            LEFT JOIN jobs j ON e.job_id = j.id
            WHERE e.customer_id = ?
            ORDER BY e.issue_date DESC, e.id DESC
            """
        var rows: [EstimateRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(EstimateRow(
                    id: sqlite3_column_int64(stmt, 0),
                    estimateNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    validUntil: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    linkedInvoiceID: sqlite3_column_int64(stmt, 11)
                ))
            }
        }
        return rows
    }

    func fetchEstimateProgressSnapshots(estimateIDs: [Int64]) throws -> [Int64: EstimateProgressSnapshot] {
        let uniqueIDs = Array(Set(estimateIDs)).sorted()
        guard !uniqueIDs.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: uniqueIDs.count).joined(separator: ", ")
        let sql = """
            SELECT e.id,
                   e.total,
                   COUNT(DISTINCT eil.invoice_id),
                   COALESCE(MAX(eil.invoice_id), 0),
                   COALESCE(SUM(ni.total), 0)
            FROM estimates e
            LEFT JOIN estimate_invoice_links eil ON eil.estimate_id = e.id
            LEFT JOIN native_invoices ni ON ni.id = eil.invoice_id
            WHERE e.id IN (\(placeholders))
            GROUP BY e.id, e.total
            """

        var snapshots: [Int64: EstimateProgressSnapshot] = [:]
        try withStatement(sql) { stmt in
            for (offset, estimateID) in uniqueIDs.enumerated() {
                sqlite3_bind_int64(stmt, Int32(offset + 1), estimateID)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let estimateID = sqlite3_column_int64(stmt, 0)
                snapshots[estimateID] = EstimateProgressSnapshot(
                    estimateID: estimateID,
                    estimateTotal: sqlite3_column_double(stmt, 1),
                    linkedInvoiceCount: Int(sqlite3_column_int(stmt, 2)),
                    latestInvoiceID: sqlite3_column_int64(stmt, 3),
                    invoicedTotal: sqlite3_column_double(stmt, 4)
                )
            }
        }

        for estimateID in uniqueIDs where snapshots[estimateID] == nil {
            if let estimate = try fetchEstimate(id: estimateID) {
                snapshots[estimateID] = .empty(estimateID: estimateID, estimateTotal: estimate.total)
            }
        }

        return snapshots
    }

    func fetchEstimateProgressSnapshot(estimateID: Int64) throws -> EstimateProgressSnapshot {
        if let snapshot = try fetchEstimateProgressSnapshots(estimateIDs: [estimateID])[estimateID] {
            return snapshot
        }
        if let estimate = try fetchEstimate(id: estimateID) {
            return .empty(estimateID: estimateID, estimateTotal: estimate.total)
        }
        return .empty(estimateID: estimateID, estimateTotal: 0)
    }

    func fetchEstimateLines(estimateID: Int64) throws -> [EstimateLineRow] {
        let sql = """
            SELECT id, description, quantity, rate, amount
            FROM estimate_lines
            WHERE estimate_id = ?
            ORDER BY id
            """
        var rows: [EstimateLineRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, estimateID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(EstimateLineRow(
                    id: sqlite3_column_int64(stmt, 0),
                    description: columnText(stmt, 1),
                    quantity: sqlite3_column_double(stmt, 2),
                    rate: sqlite3_column_double(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4)
                ))
            }
        }
        return rows
    }

    func fetchEstimateRemainingInvoiceDraft(
        estimateID: Int64,
        estimateNumber: String,
        existingEstimateLines: [EstimateLineRow]? = nil
    ) throws -> [EstimateRemainingLineDraft] {
        let snapshot = try fetchEstimateProgressSnapshot(estimateID: estimateID)
        let remainingTotal = snapshot.remainingTotal
        guard remainingTotal > 0.01 else { return [] }

        let estimateLines: [EstimateLineRow]
        if let existingEstimateLines {
            estimateLines = existingEstimateLines
        } else {
            estimateLines = try fetchEstimateLines(estimateID: estimateID)
        }
        guard !estimateLines.isEmpty else {
            return [
                EstimateRemainingLineDraft(
                    id: "remaining-balance",
                    description: "Remaining balance for Estimate \(estimateNumber)",
                    quantity: 1,
                    rate: remainingTotal,
                    amount: remainingTotal
                )
            ]
        }

        let linkedInvoiceIDs = try fetchEstimateLinkedInvoiceIDs(estimateID: estimateID)
        guard !linkedInvoiceIDs.isEmpty else {
            return estimateLines.map { line in
                EstimateRemainingLineDraft(
                    id: "estimate-line-\(line.id)",
                    description: line.description,
                    quantity: line.quantity,
                    rate: line.rate,
                    amount: line.amount
                )
            }
        }

        struct WorkingLine {
            let id: Int64
            let description: String
            let normalizedDescription: String
            let quantity: Double
            let originalRate: Double
            var remainingAmount: Double
        }

        var workingLines = estimateLines.map { line in
            WorkingLine(
                id: line.id,
                description: line.description,
                normalizedDescription: SQLiteDatabase.normalizeEstimateProgressText(line.description),
                quantity: line.quantity,
                originalRate: line.rate,
                remainingAmount: line.amount
            )
        }
        var unmatchedPriorInvoiceAmount = 0.0

        for invoiceID in linkedInvoiceIDs {
            let invoiceLines = try fetchInvoiceLines(invoiceID: invoiceID)
            for invoiceLine in invoiceLines where invoiceLine.amount > 0.01 {
                let normalizedInvoiceDescription = SQLiteDatabase.normalizeEstimateProgressText(invoiceLine.description)
                let candidates = workingLines.enumerated().filter { _, line in
                    line.remainingAmount > 0.01 && (
                        line.normalizedDescription == normalizedInvoiceDescription
                        || (!normalizedInvoiceDescription.isEmpty && line.normalizedDescription.contains(normalizedInvoiceDescription))
                        || (!line.normalizedDescription.isEmpty && normalizedInvoiceDescription.contains(line.normalizedDescription))
                    )
                }

                guard let targetIndex = SQLiteDatabase.bestEstimateProgressMatch(
                    candidates: candidates,
                    targetAmount: invoiceLine.amount,
                    remainingAmount: { $0.remainingAmount },
                    descriptionLength: { $0.normalizedDescription.count }
                ) else {
                    unmatchedPriorInvoiceAmount += invoiceLine.amount
                    continue
                }

                let deduction = min(workingLines[targetIndex].remainingAmount, invoiceLine.amount)
                workingLines[targetIndex].remainingAmount -= deduction
                let leftover = invoiceLine.amount - deduction
                if leftover > 0.01 {
                    unmatchedPriorInvoiceAmount += leftover
                }
            }
        }

        var drafts = workingLines.compactMap { line -> EstimateRemainingLineDraft? in
            guard line.remainingAmount > 0.01 else { return nil }
            let quantity = line.quantity > 0.0001 ? line.quantity : 1
            return EstimateRemainingLineDraft(
                id: "estimate-line-\(line.id)",
                description: line.description,
                quantity: quantity,
                rate: line.remainingAmount / quantity,
                amount: line.remainingAmount
            )
        }

        let inferredTotal = drafts.reduce(0) { $0 + $1.amount }
        if unmatchedPriorInvoiceAmount > 0.01 || inferredTotal <= 0.01 {
            return [
                EstimateRemainingLineDraft(
                    id: "remaining-balance",
                    description: "Remaining balance for Estimate \(estimateNumber)",
                    quantity: 1,
                    rate: remainingTotal,
                    amount: remainingTotal
                )
            ]
        }

        let drift = inferredTotal - remainingTotal
        if abs(drift) > 0.01 {
            let scale = remainingTotal / inferredTotal
            drafts = drafts.map { draft in
                let adjustedAmount = draft.amount * scale
                let quantity = draft.quantity > 0.0001 ? draft.quantity : 1
                return EstimateRemainingLineDraft(
                    id: draft.id,
                    description: draft.description,
                    quantity: quantity,
                    rate: adjustedAmount / quantity,
                    amount: adjustedAmount
                )
            }
        }

        return drafts
    }

    func saveEstimateWithLines(
        number: String, customerID: Int64, issueDate: String, validUntil: String,
        memo: String, total: Double, status: String = "draft",
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)],
        jobID: Int64? = nil,
        customerNameOverride: String = "",
        sourceEstimateID: Int64? = nil,
        sourceRelationship: String = "change_order",
        sourceNote: String = ""
    ) throws -> Int64 {
        try exec("BEGIN;")
        do {
            let estimateSQL = """
                INSERT INTO estimates(estimate_number, customer_id, job_id, issue_date, valid_until, memo, status, total, customer_name_override, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            try withStatement(estimateSQL) { stmt in
                bindText(stmt: stmt, index: 1, value: number)
                sqlite3_bind_int64(stmt, 2, customerID)
                if let jobID {
                    sqlite3_bind_int64(stmt, 3, jobID)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                bindText(stmt: stmt, index: 4, value: issueDate)
                bindText(stmt: stmt, index: 5, value: validUntil)
                bindText(stmt: stmt, index: 6, value: memo)
                bindText(stmt: stmt, index: 7, value: status)
                sqlite3_bind_double(stmt, 8, total)
                bindText(stmt: stmt, index: 9, value: customerNameOverride)
                bindText(stmt: stmt, index: 10, value: isoNow())
                bindText(stmt: stmt, index: 11, value: isoNow())
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
            let estimateID = sqlite3_last_insert_rowid(db)

            let lineSQL = "INSERT INTO estimate_lines(estimate_id, description, quantity, rate, amount) VALUES (?, ?, ?, ?, ?)"
            for line in lines {
                try withStatement(lineSQL) { stmt in
                    sqlite3_bind_int64(stmt, 1, estimateID)
                    bindText(stmt: stmt, index: 2, value: line.description)
                    sqlite3_bind_double(stmt, 3, line.quantity)
                    sqlite3_bind_double(stmt, 4, line.rate)
                    sqlite3_bind_double(stmt, 5, line.amount)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            if let sourceEstimateID {
                try insertEstimateRevisionLink(
                    sourceEstimateID: sourceEstimateID,
                    childEstimateID: estimateID,
                    relationship: sourceRelationship,
                    sourceNote: sourceNote
                )
            }

            try exec("COMMIT;")
            return estimateID
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func insertEstimateRevisionLink(
        sourceEstimateID: Int64,
        childEstimateID: Int64,
        relationship: String = "change_order",
        sourceNote: String = ""
    ) throws {
        let sql = """
            INSERT OR REPLACE INTO estimate_revision_links(
                source_estimate_id, child_estimate_id, created_at, relationship, source_note
            )
            VALUES (?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, sourceEstimateID)
            sqlite3_bind_int64(stmt, 2, childEstimateID)
            bindText(stmt: stmt, index: 3, value: isoNow())
            bindText(stmt: stmt, index: 4, value: relationship)
            bindText(stmt: stmt, index: 5, value: sourceNote)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func fetchEstimateRevisionChildren(estimateID: Int64) throws -> [EstimateRevisionLinkRow] {
        let sql = """
            SELECT erl.id, erl.source_estimate_id, erl.child_estimate_id, erl.created_at,
                   erl.relationship, erl.source_note,
                   e.id, e.estimate_number, e.customer_id, COALESCE(c.name, ''),
                   COALESCE(e.job_id, 0), COALESCE(j.name, ''),
                   e.issue_date, e.valid_until, e.memo, e.status, e.total,
                   COALESCE(e.linked_invoice_id, 0), COALESCE(e.customer_name_override, '')
            FROM estimate_revision_links erl
            JOIN estimates e ON e.id = erl.child_estimate_id
            LEFT JOIN customers c ON e.customer_id = c.id
            LEFT JOIN jobs j ON e.job_id = j.id
            WHERE erl.source_estimate_id = ?
            ORDER BY erl.created_at DESC, erl.id DESC
            """
        return try fetchEstimateRevisionLinks(sql: sql, estimateID: estimateID)
    }

    func fetchEstimateRevisionSource(estimateID: Int64) throws -> EstimateRevisionLinkRow? {
        let sql = """
            SELECT erl.id, erl.source_estimate_id, erl.child_estimate_id, erl.created_at,
                   erl.relationship, erl.source_note,
                   e.id, e.estimate_number, e.customer_id, COALESCE(c.name, ''),
                   COALESCE(e.job_id, 0), COALESCE(j.name, ''),
                   e.issue_date, e.valid_until, e.memo, e.status, e.total,
                   COALESCE(e.linked_invoice_id, 0), COALESCE(e.customer_name_override, '')
            FROM estimate_revision_links erl
            JOIN estimates e ON e.id = erl.source_estimate_id
            LEFT JOIN customers c ON e.customer_id = c.id
            LEFT JOIN jobs j ON e.job_id = j.id
            WHERE erl.child_estimate_id = ?
            ORDER BY erl.created_at DESC, erl.id DESC
            LIMIT 1
            """
        return try fetchEstimateRevisionLinks(sql: sql, estimateID: estimateID).first
    }

    private func fetchEstimateRevisionLinks(sql: String, estimateID: Int64) throws -> [EstimateRevisionLinkRow] {
        var rows: [EstimateRevisionLinkRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, estimateID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let estimate = EstimateRow(
                    id: sqlite3_column_int64(stmt, 6),
                    estimateNumber: columnText(stmt, 7),
                    customerID: sqlite3_column_int64(stmt, 8),
                    customerName: columnText(stmt, 9),
                    customerNameOverride: columnText(stmt, 18),
                    jobID: sqlite3_column_int64(stmt, 10),
                    jobName: columnText(stmt, 11),
                    issueDate: columnText(stmt, 12),
                    validUntil: columnText(stmt, 13),
                    memo: columnText(stmt, 14),
                    status: columnText(stmt, 15),
                    total: sqlite3_column_double(stmt, 16),
                    linkedInvoiceID: sqlite3_column_int64(stmt, 17)
                )
                rows.append(EstimateRevisionLinkRow(
                    id: sqlite3_column_int64(stmt, 0),
                    sourceEstimateID: sqlite3_column_int64(stmt, 1),
                    childEstimateID: sqlite3_column_int64(stmt, 2),
                    createdAt: columnText(stmt, 3),
                    relationship: columnText(stmt, 4),
                    sourceNote: columnText(stmt, 5),
                    estimate: estimate
                ))
            }
        }
        return rows
    }

    func updateEstimateWithLines(
        id: Int64,
        number: String,
        customerID: Int64,
        jobID: Int64? = nil,
        issueDate: String,
        validUntil: String,
        memo: String,
        total: Double,
        status: String,
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)],
        customerNameOverride: String = ""
    ) throws {
        try exec("BEGIN;")
        do {
            let estimateSQL = """
                UPDATE estimates
                SET estimate_number = ?,
                    customer_id = ?,
                    job_id = ?,
                    issue_date = ?,
                    valid_until = ?,
                    memo = ?,
                    status = ?,
                    total = ?,
                    customer_name_override = ?,
                    updated_at = ?
                WHERE id = ?
                """
            try withStatement(estimateSQL) { stmt in
                bindText(stmt: stmt, index: 1, value: number)
                sqlite3_bind_int64(stmt, 2, customerID)
                if let jobID {
                    sqlite3_bind_int64(stmt, 3, jobID)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                bindText(stmt: stmt, index: 4, value: issueDate)
                bindText(stmt: stmt, index: 5, value: validUntil)
                bindText(stmt: stmt, index: 6, value: memo)
                bindText(stmt: stmt, index: 7, value: status)
                sqlite3_bind_double(stmt, 8, total)
                bindText(stmt: stmt, index: 9, value: customerNameOverride)
                bindText(stmt: stmt, index: 10, value: isoNow())
                sqlite3_bind_int64(stmt, 11, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }

            try withStatement("DELETE FROM estimate_lines WHERE estimate_id = ?") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }

            let lineSQL = "INSERT INTO estimate_lines(estimate_id, description, quantity, rate, amount) VALUES (?, ?, ?, ?, ?)"
            for line in lines {
                try withStatement(lineSQL) { stmt in
                    sqlite3_bind_int64(stmt, 1, id)
                    bindText(stmt: stmt, index: 2, value: line.description)
                    sqlite3_bind_double(stmt, 3, line.quantity)
                    sqlite3_bind_double(stmt, 4, line.rate)
                    sqlite3_bind_double(stmt, 5, line.amount)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func linkEstimateToInvoice(
        estimateID: Int64,
        invoiceID: Int64,
        mode: EstimateInvoiceProgressMode = .fullRemaining,
        percentValue: Double = 100,
        shouldMarkEstimateConverted: Bool = true,
        sourceNote: String = ""
    ) throws {
        let linkSQL = """
            INSERT OR REPLACE INTO estimate_invoice_links(estimate_id, invoice_id, created_at, mode, percent_value, source_note)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        try withStatement(linkSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, estimateID)
            sqlite3_bind_int64(stmt, 2, invoiceID)
            bindText(stmt: stmt, index: 3, value: isoNow())
            bindText(stmt: stmt, index: 4, value: mode.rawValue)
            sqlite3_bind_double(stmt, 5, percentValue)
            bindText(stmt: stmt, index: 6, value: sourceNote)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }

        let sql: String
        if shouldMarkEstimateConverted {
            sql = """
                UPDATE estimates
                SET linked_invoice_id = ?,
                    status = 'converted',
                    updated_at = ?
                WHERE id = ?
                """
        } else {
            sql = """
                UPDATE estimates
                SET linked_invoice_id = ?,
                    updated_at = ?
                WHERE id = ?
                """
        }
        try withStatement(sql) { stmt in
            if shouldMarkEstimateConverted {
                sqlite3_bind_int64(stmt, 1, invoiceID)
                bindText(stmt: stmt, index: 2, value: isoNow())
                sqlite3_bind_int64(stmt, 3, estimateID)
            } else {
                sqlite3_bind_int64(stmt, 1, invoiceID)
                bindText(stmt: stmt, index: 2, value: isoNow())
                sqlite3_bind_int64(stmt, 3, estimateID)
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func fetchLatestLinkedInvoiceID(estimateID: Int64) throws -> Int64 {
        let sql = """
            SELECT COALESCE(MAX(invoice_id), 0)
            FROM estimate_invoice_links
            WHERE estimate_id = ?
            """
        var invoiceID: Int64 = 0
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, estimateID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                invoiceID = sqlite3_column_int64(stmt, 0)
            }
        }
        return invoiceID
    }

    func fetchEstimateLinkedInvoiceIDs(estimateID: Int64) throws -> [Int64] {
        let sql = """
            SELECT invoice_id
            FROM estimate_invoice_links
            WHERE estimate_id = ?
            ORDER BY id
            """
        var ids: [Int64] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, estimateID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(sqlite3_column_int64(stmt, 0))
            }
        }
        return ids
    }

    func fetchEstimateLinkedInvoices(estimateID: Int64) throws -> [NativeInvoiceRow] {
        let sql = """
            SELECT ni.id, ni.invoice_number, ni.customer_id, COALESCE(c.name, ''),
                   COALESCE(ni.job_id, 0), COALESCE(j.name, ''), ni.issue_date,
                   ni.due_date, ni.memo, ni.status, ni.total, ni.paid, COALESCE(ni.customer_name_override, '')
            FROM estimate_invoice_links eil
            JOIN native_invoices ni ON ni.id = eil.invoice_id
            LEFT JOIN customers c ON ni.customer_id = c.id
            LEFT JOIN jobs j ON ni.job_id = j.id
            WHERE eil.estimate_id = ?
            ORDER BY ni.issue_date DESC, ni.id DESC
            """
        var rows: [NativeInvoiceRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, estimateID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(NativeInvoiceRow(
                    id: sqlite3_column_int64(stmt, 0),
                    invoiceNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    dueDate: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    paid: sqlite3_column_double(stmt, 11)
                ))
            }
        }
        return rows
    }

    func estimateNumberExists(_ number: String, excludingID: Int64? = nil) throws -> Bool {
        let sql: String
        if excludingID == nil {
            sql = "SELECT 1 FROM estimates WHERE estimate_number = ? LIMIT 1"
        } else {
            sql = "SELECT 1 FROM estimates WHERE estimate_number = ? AND id != ? LIMIT 1"
        }
        var exists = false
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: number)
            if let excludingID {
                sqlite3_bind_int64(stmt, 2, excludingID)
            }
            exists = sqlite3_step(stmt) == SQLITE_ROW
        }
        return exists
    }

    func invoiceNumberExists(_ number: String, excludingID: Int64? = nil) throws -> Bool {
        let sql: String
        if excludingID == nil {
            sql = "SELECT 1 FROM native_invoices WHERE invoice_number = ? LIMIT 1"
        } else {
            sql = "SELECT 1 FROM native_invoices WHERE invoice_number = ? AND id != ? LIMIT 1"
        }
        var exists = false
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: number)
            if let excludingID {
                sqlite3_bind_int64(stmt, 2, excludingID)
            }
            exists = sqlite3_step(stmt) == SQLITE_ROW
        }
        return exists
    }

    func updateEstimateStatus(id: Int64, status: String) throws {
        let sql = """
            UPDATE estimates
            SET status = ?, updated_at = ?
            WHERE id = ?
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: status)
            bindText(stmt: stmt, index: 2, value: isoNow())
            sqlite3_bind_int64(stmt, 3, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    // MARK: - Native Invoices

    func nextInvoiceNumber() throws -> String {
        let year = Calendar.current.component(.year, from: Date())
        let prefix = "INV-\(year)-"
        var count: Int32 = 0
        try withStatement("SELECT COUNT(*) FROM native_invoices WHERE invoice_number LIKE ?") { stmt in
            bindText(stmt: stmt, index: 1, value: "\(prefix)%")
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int(stmt, 0)
            }
        }
        return String(format: "%@%03d", prefix, count + 1)
    }

    func nextSalesReceiptNumber() throws -> String {
        let year = Calendar.current.component(.year, from: Date())
        let prefix = "SR-\(year)-"
        var count: Int32 = 0
        try withStatement("SELECT COUNT(*) FROM sales_receipts WHERE receipt_number LIKE ?") { stmt in
            bindText(stmt: stmt, index: 1, value: "\(prefix)%")
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int(stmt, 0)
            }
        }
        return String(format: "%@%03d", prefix, count + 1)
    }

    func nextCheckNumber(paymentAccountID: Int64? = nil) throws -> String {
        let sql: String
        if paymentAccountID == nil {
            sql = """
                SELECT check_number
                FROM expenses
                WHERE TRIM(COALESCE(check_number, '')) != ''
                """
        } else {
            sql = """
                SELECT check_number
                FROM expenses
                WHERE payment_account_id = ?
                  AND TRIM(COALESCE(check_number, '')) != ''
                """
        }

        var maxNumeric = 1000
        var width = 4

        try withStatement(sql) { stmt in
            if let paymentAccountID {
                sqlite3_bind_int64(stmt, 1, paymentAccountID)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let value = columnText(stmt, 0).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.allSatisfy(\.isNumber), let numeric = Int(value) else { continue }
                maxNumeric = max(maxNumeric, numeric)
                width = max(width, value.count)
            }
        }

        return String(format: "%0*d", width, maxNumeric + 1)
    }

    func fetchNativeInvoices(search: String = "") throws -> [NativeInvoiceRow] {
        let sql = """
            SELECT ni.id, ni.invoice_number, ni.customer_id, COALESCE(c.name, ''),
                   COALESCE(ni.job_id, 0), COALESCE(j.name, ''),
                   ni.issue_date, ni.due_date, ni.memo, ni.status, ni.total, ni.paid, COALESCE(ni.customer_name_override, '')
            FROM native_invoices ni
            LEFT JOIN customers c ON ni.customer_id = c.id
            LEFT JOIN jobs j ON ni.job_id = j.id
            WHERE (? = '' OR lower(ni.invoice_number) LIKE ? OR lower(c.name) LIKE ? OR lower(COALESCE(j.name, '')) LIKE ?)
            ORDER BY ni.issue_date DESC, ni.id DESC
            LIMIT 500
            """
        let like = "%\(search.lowercased())%"
        var rows: [NativeInvoiceRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(NativeInvoiceRow(
                    id: sqlite3_column_int64(stmt, 0),
                    invoiceNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    dueDate: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    paid: sqlite3_column_double(stmt, 11)
                ))
            }
        }
        return rows
    }

    func fetchSalesReceipts(search: String = "") throws -> [SalesReceiptRow] {
        let sql = """
            SELECT sr.id, sr.receipt_number, COALESCE(sr.customer_id, 0), COALESCE(c.name, ''),
                   COALESCE(sr.job_id, 0), COALESCE(j.name, ''),
                   sr.receipt_date, sr.memo, sr.total,
                   COALESCE(sr.payment_method_id, 0), COALESCE(pm.name, ''),
                   COALESCE(pr.deposit_account_id, 0), COALESCE(a.name, ''),
                   COALESCE(sr.payment_id, 0)
            FROM sales_receipts sr
            LEFT JOIN customers c ON sr.customer_id = c.id
            LEFT JOIN jobs j ON sr.job_id = j.id
            LEFT JOIN payment_methods pm ON sr.payment_method_id = pm.id
            LEFT JOIN payments_received pr ON sr.payment_id = pr.id
            LEFT JOIN gl_accounts a ON pr.deposit_account_id = a.id
            WHERE (? = '' OR lower(sr.receipt_number) LIKE ? OR lower(COALESCE(c.name, '')) LIKE ? OR lower(COALESCE(j.name, '')) LIKE ?)
            ORDER BY sr.receipt_date DESC, sr.id DESC
            LIMIT 500
            """
        let like = "%\(search.lowercased())%"
        var rows: [SalesReceiptRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SalesReceiptRow(
                    id: sqlite3_column_int64(stmt, 0),
                    receiptNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    receiptDate: columnText(stmt, 6),
                    memo: columnText(stmt, 7),
                    total: sqlite3_column_double(stmt, 8),
                    paymentMethodID: sqlite3_column_int64(stmt, 9),
                    paymentMethodName: columnText(stmt, 10),
                    depositAccountID: sqlite3_column_int64(stmt, 11),
                    depositAccountName: columnText(stmt, 12),
                    paymentID: sqlite3_column_int64(stmt, 13)
                ))
            }
        }
        return rows
    }

    func fetchCustomerInvoices(customerID: Int64) throws -> [NativeInvoiceRow] {
        let sql = """
            SELECT ni.id, ni.invoice_number, ni.customer_id, COALESCE(c.name, ''),
                   COALESCE(ni.job_id, 0), COALESCE(j.name, ''),
                   ni.issue_date, ni.due_date, ni.memo, ni.status, ni.total, ni.paid, COALESCE(ni.customer_name_override, '')
            FROM native_invoices ni
            LEFT JOIN customers c ON ni.customer_id = c.id
            LEFT JOIN jobs j ON ni.job_id = j.id
            WHERE ni.customer_id = ?
            ORDER BY ni.issue_date DESC, ni.id DESC
            """
        var rows: [NativeInvoiceRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(NativeInvoiceRow(
                    id: sqlite3_column_int64(stmt, 0),
                    invoiceNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    dueDate: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    paid: sqlite3_column_double(stmt, 11)
                ))
            }
        }
        return rows
    }

    func fetchCustomerSalesReceipts(customerID: Int64) throws -> [SalesReceiptRow] {
        let sql = """
            SELECT sr.id, sr.receipt_number, COALESCE(sr.customer_id, 0), COALESCE(c.name, ''),
                   COALESCE(sr.job_id, 0), COALESCE(j.name, ''),
                   sr.receipt_date, sr.memo, sr.total,
                   COALESCE(sr.payment_method_id, 0), COALESCE(pm.name, ''),
                   COALESCE(pr.deposit_account_id, 0), COALESCE(a.name, ''),
                   COALESCE(sr.payment_id, 0)
            FROM sales_receipts sr
            LEFT JOIN customers c ON sr.customer_id = c.id
            LEFT JOIN jobs j ON sr.job_id = j.id
            LEFT JOIN payment_methods pm ON sr.payment_method_id = pm.id
            LEFT JOIN payments_received pr ON sr.payment_id = pr.id
            LEFT JOIN gl_accounts a ON pr.deposit_account_id = a.id
            WHERE sr.customer_id = ?
            ORDER BY sr.receipt_date DESC, sr.id DESC
            """
        var rows: [SalesReceiptRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SalesReceiptRow(
                    id: sqlite3_column_int64(stmt, 0),
                    receiptNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    receiptDate: columnText(stmt, 6),
                    memo: columnText(stmt, 7),
                    total: sqlite3_column_double(stmt, 8),
                    paymentMethodID: sqlite3_column_int64(stmt, 9),
                    paymentMethodName: columnText(stmt, 10),
                    depositAccountID: sqlite3_column_int64(stmt, 11),
                    depositAccountName: columnText(stmt, 12),
                    paymentID: sqlite3_column_int64(stmt, 13)
                ))
            }
        }
        return rows
    }

    func saveInvoiceWithLines(
        number: String, customerID: Int64, issueDate: String, dueDate: String,
        memo: String, total: Double,
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)],
        jobID: Int64? = nil,
        customerNameOverride: String = ""
    ) throws -> Int64 {
        try exec("BEGIN;")
        do {
            let invSQL = """
                INSERT INTO native_invoices(invoice_number, customer_id, job_id, issue_date, due_date, memo, total, customer_name_override, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            try withStatement(invSQL) { stmt in
                bindText(stmt: stmt, index: 1, value: number)
                sqlite3_bind_int64(stmt, 2, customerID)
                if let jobID {
                    sqlite3_bind_int64(stmt, 3, jobID)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                bindText(stmt: stmt, index: 4, value: issueDate)
                bindText(stmt: stmt, index: 5, value: dueDate)
                bindText(stmt: stmt, index: 6, value: memo)
                sqlite3_bind_double(stmt, 7, total)
                bindText(stmt: stmt, index: 8, value: customerNameOverride)
                bindText(stmt: stmt, index: 9, value: isoNow())
                bindText(stmt: stmt, index: 10, value: isoNow())
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
            let invoiceID = sqlite3_last_insert_rowid(db)

            let lineSQL = "INSERT INTO invoice_lines(invoice_id, description, quantity, rate, amount) VALUES (?, ?, ?, ?, ?)"
            for line in lines {
                try withStatement(lineSQL) { stmt in
                    sqlite3_bind_int64(stmt, 1, invoiceID)
                    bindText(stmt: stmt, index: 2, value: line.description)
                    sqlite3_bind_double(stmt, 3, line.quantity)
                    sqlite3_bind_double(stmt, 4, line.rate)
                    sqlite3_bind_double(stmt, 5, line.amount)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            try exec("COMMIT;")
            try? repostInvoice(invoiceID)   // keep the ledger current; rebuild is the backstop
            return invoiceID
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func updateInvoiceWithLines(
        id: Int64,
        number: String,
        customerID: Int64,
        jobID: Int64? = nil,
        issueDate: String,
        dueDate: String,
        memo: String,
        total: Double,
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)],
        customerNameOverride: String = ""
    ) throws {
        try exec("BEGIN;")
        do {
            var currentPaid = 0.0
            var currentStatus = ""
            try withStatement("SELECT paid, status FROM native_invoices WHERE id = ?") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    currentPaid = sqlite3_column_double(stmt, 0)
                    currentStatus = columnText(stmt, 1)
                }
            }

            let invoiceSQL = """
                UPDATE native_invoices
                SET invoice_number = ?,
                    customer_id = ?,
                    job_id = ?,
                    issue_date = ?,
                    due_date = ?,
                    memo = ?,
                    total = ?,
                    customer_name_override = ?,
                    updated_at = ?
                WHERE id = ?
                """
            try withStatement(invoiceSQL) { stmt in
                bindText(stmt: stmt, index: 1, value: number)
                sqlite3_bind_int64(stmt, 2, customerID)
                if let jobID {
                    sqlite3_bind_int64(stmt, 3, jobID)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                bindText(stmt: stmt, index: 4, value: issueDate)
                bindText(stmt: stmt, index: 5, value: dueDate)
                bindText(stmt: stmt, index: 6, value: memo)
                sqlite3_bind_double(stmt, 7, total)
                bindText(stmt: stmt, index: 8, value: customerNameOverride)
                bindText(stmt: stmt, index: 9, value: isoNow())
                sqlite3_bind_int64(stmt, 10, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }

            try withStatement("DELETE FROM invoice_lines WHERE invoice_id = ?") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }

            let lineSQL = "INSERT INTO invoice_lines(invoice_id, description, quantity, rate, amount) VALUES (?, ?, ?, ?, ?)"
            for line in lines {
                try withStatement(lineSQL) { stmt in
                    sqlite3_bind_int64(stmt, 1, id)
                    bindText(stmt: stmt, index: 2, value: line.description)
                    sqlite3_bind_double(stmt, 3, line.quantity)
                    sqlite3_bind_double(stmt, 4, line.rate)
                    sqlite3_bind_double(stmt, 5, line.amount)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            if currentStatus != "void" {
                try updateInvoicePaidStatus(id: id, paid: currentPaid)
            }

            try exec("COMMIT;")
            try? repostInvoice(id)   // reflect the edited totals in the ledger
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func salesReceiptNumberExists(_ number: String, excludingID: Int64? = nil) throws -> Bool {
        let sql: String
        if excludingID == nil {
            sql = "SELECT 1 FROM sales_receipts WHERE receipt_number = ? LIMIT 1"
        } else {
            sql = "SELECT 1 FROM sales_receipts WHERE receipt_number = ? AND id != ? LIMIT 1"
        }
        var exists = false
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: number)
            if let excludingID {
                sqlite3_bind_int64(stmt, 2, excludingID)
            }
            exists = sqlite3_step(stmt) == SQLITE_ROW
        }
        return exists
    }

    func saveSalesReceiptWithLines(
        number: String,
        customerID: Int64?,
        jobID: Int64?,
        receiptDate: String,
        paymentMethodID: Int64?,
        depositAccountID: Int64?,
        memo: String,
        total: Double,
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)]
    ) throws -> Int64 {
        try exec("BEGIN;")
        do {
            let paymentMethodName = try paymentMethodNameForSalesReceipt(paymentMethodID)
            let paymentID = try insertStandaloneCustomerPayment(
                customerID: customerID,
                paymentDate: receiptDate,
                amount: total,
                method: paymentMethodName,
                reference: number,
                memo: memo,
                depositAccountID: depositAccountID
            )

            let receiptSQL = """
                INSERT INTO sales_receipts(receipt_number, customer_id, job_id, receipt_date, payment_method_id, payment_id, memo, total, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            try withStatement(receiptSQL) { stmt in
                bindText(stmt: stmt, index: 1, value: number)
                bindOptionalInt64(stmt: stmt, index: 2, value: customerID)
                bindOptionalInt64(stmt: stmt, index: 3, value: jobID)
                bindText(stmt: stmt, index: 4, value: receiptDate)
                bindOptionalInt64(stmt: stmt, index: 5, value: paymentMethodID)
                sqlite3_bind_int64(stmt, 6, paymentID)
                bindText(stmt: stmt, index: 7, value: memo)
                sqlite3_bind_double(stmt, 8, total)
                bindText(stmt: stmt, index: 9, value: isoNow())
                bindText(stmt: stmt, index: 10, value: isoNow())
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
            let receiptID = sqlite3_last_insert_rowid(db)
            try insertSalesReceiptLines(receiptID: receiptID, lines: lines)
            try exec("COMMIT;")
            return receiptID
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func updateSalesReceiptWithLines(
        id: Int64,
        number: String,
        customerID: Int64?,
        jobID: Int64?,
        receiptDate: String,
        paymentMethodID: Int64?,
        depositAccountID: Int64?,
        memo: String,
        total: Double,
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)]
    ) throws {
        try exec("BEGIN;")
        do {
            var paymentID: Int64 = 0
            try withStatement("SELECT COALESCE(payment_id, 0) FROM sales_receipts WHERE id = ? LIMIT 1") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    paymentID = sqlite3_column_int64(stmt, 0)
                }
            }

            let paymentMethodName = try paymentMethodNameForSalesReceipt(paymentMethodID)
            if paymentID == 0 {
                paymentID = try insertStandaloneCustomerPayment(
                    customerID: customerID,
                    paymentDate: receiptDate,
                    amount: total,
                    method: paymentMethodName,
                    reference: number,
                    memo: memo,
                    depositAccountID: depositAccountID
                )
            } else {
                try withStatement(
                    """
                    UPDATE payments_received
                    SET customer_id = ?,
                        payment_date = ?,
                        amount = ?,
                        method = ?,
                        reference = ?,
                        memo = ?,
                        deposit_account_id = ?
                    WHERE id = ?
                    """
                ) { stmt in
                    bindOptionalInt64(stmt: stmt, index: 1, value: customerID)
                    bindText(stmt: stmt, index: 2, value: receiptDate)
                    sqlite3_bind_double(stmt, 3, total)
                    bindText(stmt: stmt, index: 4, value: paymentMethodName)
                    bindText(stmt: stmt, index: 5, value: number)
                    bindText(stmt: stmt, index: 6, value: memo)
                    bindOptionalInt64(stmt: stmt, index: 7, value: depositAccountID)
                    sqlite3_bind_int64(stmt, 8, paymentID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            try withStatement(
                """
                UPDATE sales_receipts
                SET receipt_number = ?,
                    customer_id = ?,
                    job_id = ?,
                    receipt_date = ?,
                    payment_method_id = ?,
                    payment_id = ?,
                    memo = ?,
                    total = ?,
                    updated_at = ?
                WHERE id = ?
                """
            ) { stmt in
                bindText(stmt: stmt, index: 1, value: number)
                bindOptionalInt64(stmt: stmt, index: 2, value: customerID)
                bindOptionalInt64(stmt: stmt, index: 3, value: jobID)
                bindText(stmt: stmt, index: 4, value: receiptDate)
                bindOptionalInt64(stmt: stmt, index: 5, value: paymentMethodID)
                sqlite3_bind_int64(stmt, 6, paymentID)
                bindText(stmt: stmt, index: 7, value: memo)
                sqlite3_bind_double(stmt, 8, total)
                bindText(stmt: stmt, index: 9, value: isoNow())
                sqlite3_bind_int64(stmt, 10, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }

            try withStatement("DELETE FROM sales_receipt_lines WHERE receipt_id = ?") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
            try insertSalesReceiptLines(receiptID: id, lines: lines)

            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func updateInvoicePaidStatus(id: Int64, paid: Double) throws {
        let status: String
        if paid <= 0 { status = "open" }
        else {
            var total = 0.0
            try withStatement("SELECT total FROM native_invoices WHERE id = ?") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) == SQLITE_ROW { total = sqlite3_column_double(stmt, 0) }
            }
            status = paid >= total ? "paid" : "partial"
        }
        let sql = "UPDATE native_invoices SET paid = ?, status = ?, updated_at = ? WHERE id = ?"
        try withStatement(sql) { stmt in
            sqlite3_bind_double(stmt, 1, paid)
            bindText(stmt: stmt, index: 2, value: status)
            bindText(stmt: stmt, index: 3, value: isoNow())
            sqlite3_bind_int64(stmt, 4, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    private func paymentMethodNameForSalesReceipt(_ paymentMethodID: Int64?) throws -> String {
        guard let paymentMethodID, paymentMethodID != 0 else { return "cash" }
        var name = ""
        try withStatement("SELECT name FROM payment_methods WHERE id = ? LIMIT 1") { stmt in
            sqlite3_bind_int64(stmt, 1, paymentMethodID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                name = columnText(stmt, 0)
            }
        }
        return name.isEmpty ? "cash" : name
    }

    private func insertStandaloneCustomerPayment(
        customerID: Int64?,
        paymentDate: String,
        amount: Double,
        method: String,
        reference: String,
        memo: String,
        depositAccountID: Int64?
    ) throws -> Int64 {
        let sql = """
            INSERT INTO payments_received(customer_id, invoice_id, payment_date, amount, method, reference, memo, deposit_account_id, created_at)
            VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            bindOptionalInt64(stmt: stmt, index: 1, value: customerID)
            bindText(stmt: stmt, index: 2, value: paymentDate)
            sqlite3_bind_double(stmt, 3, amount)
            bindText(stmt: stmt, index: 4, value: method)
            bindText(stmt: stmt, index: 5, value: reference)
            bindText(stmt: stmt, index: 6, value: memo)
            bindOptionalInt64(stmt: stmt, index: 7, value: depositAccountID)
            bindText(stmt: stmt, index: 8, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func insertSalesReceiptLines(
        receiptID: Int64,
        lines: [(description: String, quantity: Double, rate: Double, amount: Double)]
    ) throws {
        let lineSQL = "INSERT INTO sales_receipt_lines(receipt_id, description, quantity, rate, amount) VALUES (?, ?, ?, ?, ?)"
        for line in lines {
            try withStatement(lineSQL) { stmt in
                sqlite3_bind_int64(stmt, 1, receiptID)
                bindText(stmt: stmt, index: 2, value: line.description)
                sqlite3_bind_double(stmt, 3, line.quantity)
                sqlite3_bind_double(stmt, 4, line.rate)
                sqlite3_bind_double(stmt, 5, line.amount)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
        }
    }

    private func calculatedAppliedAmountForInvoice(invoiceID: Int64) throws -> Double {
        var totalApplied = 0.0

        try withStatement(
            """
            SELECT COALESCE(SUM(applied_amount), 0)
            FROM payment_applications
            WHERE invoice_id = ?
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, invoiceID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalApplied += sqlite3_column_double(stmt, 0)
            }
        }

        try withStatement(
            """
            SELECT COALESCE(SUM(pr.amount), 0)
            FROM payments_received pr
            WHERE pr.invoice_id = ?
              AND NOT EXISTS (
                  SELECT 1
                  FROM payment_applications pa
                  WHERE pa.payment_id = pr.id
              )
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, invoiceID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalApplied += sqlite3_column_double(stmt, 0)
            }
        }

        try withStatement(
            """
            SELECT COALESCE(SUM(amount), 0)
            FROM credit_applications
            WHERE invoice_id = ?
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, invoiceID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalApplied += sqlite3_column_double(stmt, 0)
            }
        }

        return totalApplied
    }

    func recalculateInvoicePaidStatus(id: Int64) throws {
        try updateInvoicePaidStatus(id: id, paid: try calculatedAppliedAmountForInvoice(invoiceID: id))
    }

    // MARK: - Payments Received

    @discardableResult
    func insertPaymentReceived(
        customerID: Int64, invoiceID: Int64,
        paymentDate: String, amount: Double,
        method: String, reference: String, memo: String
    ) throws -> Int64 {
        let paymentID = try recordCustomerPayment(
            customerID: customerID,
            paymentDate: paymentDate,
            paymentAmount: amount,
            method: method,
            reference: reference,
            memo: memo,
            cashAllocations: [(invoiceID: invoiceID, amount: amount)],
            creditApplications: []
        )
        return paymentID ?? 0
    }

    @discardableResult
    func insertCustomerCredit(
        customerID: Int64,
        creditDate: String,
        amount: Double,
        reference: String,
        creditType: String,
        memo: String
    ) throws -> Int64 {
        let sql = """
            INSERT INTO customer_credits(customer_id, credit_date, reference, credit_type, amount, remaining_amount, memo, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            bindText(stmt: stmt, index: 2, value: creditDate)
            bindText(stmt: stmt, index: 3, value: reference)
            bindText(stmt: stmt, index: 4, value: creditType)
            sqlite3_bind_double(stmt, 5, amount)
            sqlite3_bind_double(stmt, 6, amount)
            bindText(stmt: stmt, index: 7, value: memo)
            bindText(stmt: stmt, index: 8, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        return sqlite3_last_insert_rowid(db)
    }

    @discardableResult
    func recordCustomerPayment(
        customerID: Int64,
        paymentDate: String,
        paymentAmount: Double,
        method: String,
        reference: String,
        memo: String,
        depositAccountID: Int64? = nil,
        cashAllocations: [(invoiceID: Int64, amount: Double)],
        creditApplications: [(creditID: Int64, invoiceID: Int64, amount: Double)]
    ) throws -> Int64? {
        let normalizedCashAllocations = cashAllocations.filter { $0.amount > 0.01 }
        let normalizedCreditApplications = creditApplications.filter { $0.amount > 0.01 }
        let totalCashApplied = normalizedCashAllocations.reduce(0.0) { $0 + $1.amount }
        let totalCreditApplied = normalizedCreditApplications.reduce(0.0) { $0 + $1.amount }

        guard paymentAmount > 0.01 || totalCreditApplied > 0.01 else {
            throw DBError.stepFailed("Record a payment amount or apply at least one credit.")
        }

        if paymentAmount > 0.01, abs(totalCashApplied - paymentAmount) > 0.01 {
            throw DBError.stepFailed("Cash payment allocations must match the payment amount.")
        }

        var availableCreditByID: [Int64: Double] = [:]
        for application in normalizedCreditApplications {
            if availableCreditByID[application.creditID] == nil {
                try withStatement(
                    "SELECT remaining_amount FROM customer_credits WHERE id = ? AND customer_id = ? LIMIT 1"
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, application.creditID)
                    sqlite3_bind_int64(stmt, 2, customerID)
                    guard sqlite3_step(stmt) == SQLITE_ROW else {
                        throw DBError.stepFailed("Customer credit \(application.creditID) was not found.")
                    }
                    availableCreditByID[application.creditID] = sqlite3_column_double(stmt, 0)
                }
            }
            let available = availableCreditByID[application.creditID] ?? 0
            guard application.amount <= available + 0.01 else {
                throw DBError.stepFailed("Tried to apply more credit than is available.")
            }
            availableCreditByID[application.creditID] = max(0, available - application.amount)
        }

        let invoiceIDs = Set(normalizedCashAllocations.map(\.invoiceID) + normalizedCreditApplications.map(\.invoiceID))
        try exec("BEGIN;")
        do {
            var paymentID: Int64?
            if paymentAmount > 0.01 {
                let sql = """
                    INSERT INTO payments_received(customer_id, invoice_id, payment_date, amount, method, reference, memo, deposit_account_id, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                try withStatement(sql) { stmt in
                    sqlite3_bind_int64(stmt, 1, customerID)
                    if normalizedCashAllocations.count == 1, let first = normalizedCashAllocations.first {
                        sqlite3_bind_int64(stmt, 2, first.invoiceID)
                    } else {
                        sqlite3_bind_null(stmt, 2)
                    }
                    bindText(stmt: stmt, index: 3, value: paymentDate)
                    sqlite3_bind_double(stmt, 4, paymentAmount)
                    bindText(stmt: stmt, index: 5, value: method)
                    bindText(stmt: stmt, index: 6, value: reference)
                    bindText(stmt: stmt, index: 7, value: memo)
                    if let depositAccountID {
                        sqlite3_bind_int64(stmt, 8, depositAccountID)
                    } else {
                        sqlite3_bind_null(stmt, 8)
                    }
                    bindText(stmt: stmt, index: 9, value: isoNow())
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
                paymentID = sqlite3_last_insert_rowid(db)
            }

            if let paymentID {
                let allocationSQL = """
                    INSERT INTO payment_applications(payment_id, invoice_id, applied_amount, created_at)
                    VALUES (?, ?, ?, ?)
                    """
                for allocation in normalizedCashAllocations {
                    try withStatement(allocationSQL) { stmt in
                        sqlite3_bind_int64(stmt, 1, paymentID)
                        sqlite3_bind_int64(stmt, 2, allocation.invoiceID)
                        sqlite3_bind_double(stmt, 3, allocation.amount)
                        bindText(stmt: stmt, index: 4, value: isoNow())
                        if sqlite3_step(stmt) != SQLITE_DONE {
                            throw DBError.stepFailed(lastErrorMessage)
                        }
                    }
                }
            }

            let creditSQL = """
                INSERT INTO credit_applications(customer_credit_id, invoice_id, payment_id, applied_date, amount, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """
            for application in normalizedCreditApplications {
                try withStatement(
                    "UPDATE customer_credits SET remaining_amount = remaining_amount - ? WHERE id = ?"
                ) { stmt in
                    sqlite3_bind_double(stmt, 1, application.amount)
                    sqlite3_bind_int64(stmt, 2, application.creditID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }

                try withStatement(creditSQL) { stmt in
                    sqlite3_bind_int64(stmt, 1, application.creditID)
                    sqlite3_bind_int64(stmt, 2, application.invoiceID)
                    if let paymentID {
                        sqlite3_bind_int64(stmt, 3, paymentID)
                    } else {
                        sqlite3_bind_null(stmt, 3)
                    }
                    bindText(stmt: stmt, index: 4, value: paymentDate)
                    sqlite3_bind_double(stmt, 5, application.amount)
                    bindText(stmt: stmt, index: 6, value: isoNow())
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            for invoiceID in invoiceIDs {
                try recalculateInvoicePaidStatus(id: invoiceID)
            }

            try exec("COMMIT;")
            if let paymentID { try? repostPayment(paymentID) }   // book the cash receipt live
            return paymentID
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func fetchOpenInvoicesForCustomer(customerID: Int64) throws -> [NativeInvoiceRow] {
        let sql = """
            SELECT ni.id, ni.invoice_number, ni.customer_id, COALESCE(c.name, ''),
                   COALESCE(ni.job_id, 0), COALESCE(j.name, ''), ni.issue_date,
                   ni.due_date, ni.memo, ni.status, ni.total, ni.paid, COALESCE(ni.customer_name_override, '')
            FROM native_invoices ni
            LEFT JOIN customers c ON ni.customer_id = c.id
            LEFT JOIN jobs j ON ni.job_id = j.id
            WHERE ni.customer_id = ?
              AND ni.status != 'void'
              AND (ni.total - ni.paid) > 0.01
            ORDER BY ni.issue_date, ni.id
            """
        var rows: [NativeInvoiceRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(NativeInvoiceRow(
                    id: sqlite3_column_int64(stmt, 0),
                    invoiceNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    dueDate: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    paid: sqlite3_column_double(stmt, 11)
                ))
            }
        }
        return rows
    }

    func fetchCustomerCredits(customerID: Int64) throws -> [CustomerCreditRow] {
        let sql = """
            SELECT id, customer_id, credit_date, reference, credit_type, amount, remaining_amount, memo
            FROM customer_credits
            WHERE customer_id = ? AND remaining_amount > 0.01
            ORDER BY credit_date, id
            """
        var rows: [CustomerCreditRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(CustomerCreditRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerID: sqlite3_column_int64(stmt, 1),
                    creditDate: columnText(stmt, 2),
                    reference: columnText(stmt, 3),
                    creditType: columnText(stmt, 4),
                    amount: sqlite3_column_double(stmt, 5),
                    remainingAmount: sqlite3_column_double(stmt, 6),
                    memo: columnText(stmt, 7)
                ))
            }
        }
        return rows
    }

    func fetchPaymentsForCustomer(customerID: Int64) throws -> [PaymentReceivedRow] {
        let sql = """
            SELECT p.id,
                   COALESCE(c.name, ''),
                   COALESCE(
                       NULLIF((
                           SELECT group_concat(ni2.invoice_number, ', ')
                           FROM payment_applications pa
                           JOIN native_invoices ni2 ON ni2.id = pa.invoice_id
                           WHERE pa.payment_id = p.id
                       ), ''),
                       COALESCE(ni.invoice_number, ''),
                       COALESCE(sr.receipt_number, '')
                   ),
                   p.payment_date,
                   p.amount,
                   p.method,
                   COALESCE(p.reference, '')
            FROM payments_received p
            LEFT JOIN customers c ON p.customer_id = c.id
            LEFT JOIN native_invoices ni ON p.invoice_id = ni.id
            LEFT JOIN sales_receipts sr ON sr.payment_id = p.id
            WHERE p.customer_id = ?
            ORDER BY p.payment_date DESC, p.id DESC
            """
        var rows: [PaymentReceivedRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(PaymentReceivedRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerName: columnText(stmt, 1),
                    invoiceNumber: columnText(stmt, 2),
                    paymentDate: columnText(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4),
                    method: columnText(stmt, 5),
                    reference: columnText(stmt, 6)
                ))
            }
        }
        return rows
    }

    func fetchRecentPayments(limit: Int = 8) throws -> [PaymentReceivedRow] {
        let sql = """
            SELECT p.id,
                   COALESCE(c.name, ''),
                   COALESCE(
                       NULLIF((
                           SELECT group_concat(ni2.invoice_number, ', ')
                           FROM payment_applications pa
                           JOIN native_invoices ni2 ON ni2.id = pa.invoice_id
                           WHERE pa.payment_id = p.id
                       ), ''),
                       COALESCE(ni.invoice_number, ''),
                       COALESCE(sr.receipt_number, '')
                   ),
                   p.payment_date,
                   p.amount,
                   p.method,
                   COALESCE(p.reference, '')
            FROM payments_received p
            LEFT JOIN customers c ON p.customer_id = c.id
            LEFT JOIN native_invoices ni ON p.invoice_id = ni.id
            LEFT JOIN sales_receipts sr ON sr.payment_id = p.id
            ORDER BY p.payment_date DESC, p.id DESC
            LIMIT ?
            """
        var rows: [PaymentReceivedRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(PaymentReceivedRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerName: columnText(stmt, 1),
                    invoiceNumber: columnText(stmt, 2),
                    paymentDate: columnText(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4),
                    method: columnText(stmt, 5),
                    reference: columnText(stmt, 6)
                ))
            }
        }
        return rows
    }

    func fetchUndepositedPayments() throws -> [PaymentReceivedRow] {
        let sql = """
            SELECT p.id,
                   COALESCE(c.name, ''),
                   COALESCE(
                       (
                           SELECT group_concat(inv.invoice_number, ', ')
                           FROM payment_applications pa
                           JOIN native_invoices inv ON inv.id = pa.invoice_id
                           WHERE pa.payment_id = p.id
                       ),
                       CASE WHEN p.invoice_id IS NOT NULL AND p.invoice_id != 0 THEN inv.invoice_number ELSE '' END,
                       COALESCE(sr.receipt_number, ''),
                       ''
                   ),
                   p.payment_date,
                   p.amount,
                   p.method,
                   p.reference
            FROM payments_received p
            LEFT JOIN customers c ON p.customer_id = c.id
            LEFT JOIN native_invoices inv ON p.invoice_id = inv.id
            LEFT JOIN sales_receipts sr ON sr.payment_id = p.id
            LEFT JOIN deposit_record_lines drl ON drl.payment_id = p.id
            WHERE p.amount > 0.01
              AND COALESCE(p.deposit_account_id, 0) = 0
              AND drl.id IS NULL
              -- Credit memos are non-cash (applied to invoices, never hit the bank),
              -- so they must not appear as undeposited cash awaiting a bank deposit.
              AND LOWER(COALESCE(p.method, '')) != 'credit_memo'
            ORDER BY p.payment_date, p.id
            """
        var rows: [PaymentReceivedRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(PaymentReceivedRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerName: columnText(stmt, 1),
                    invoiceNumber: columnText(stmt, 2),
                    paymentDate: columnText(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4),
                    method: columnText(stmt, 5),
                    reference: columnText(stmt, 6)
                ))
            }
        }
        return rows
    }

    @discardableResult
    func recordDeposit(
        paymentIDs: [Int64],
        depositDate: String,
        destinationAccountID: Int64,
        reference: String,
        memo: String
    ) throws -> Int64 {
        let uniquePaymentIDs = Array(Set(paymentIDs)).sorted()
        guard !uniquePaymentIDs.isEmpty else {
            throw DBError.stepFailed("Choose at least one undeposited payment.")
        }

        var total = 0.0
        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for paymentID in uniquePaymentIDs {
                try withStatement(
                    """
                    SELECT amount
                    FROM payments_received
                    WHERE id = ?
                      AND amount > 0.01
                      AND COALESCE(deposit_account_id, 0) = 0
                      AND NOT EXISTS (
                          SELECT 1 FROM deposit_record_lines drl WHERE drl.payment_id = payments_received.id
                      )
                    LIMIT 1
                    """
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, paymentID)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        total += sqlite3_column_double(stmt, 0)
                    } else {
                        throw DBError.stepFailed("One or more selected payments are no longer available for deposit.")
                    }
                }
            }

            let insertDepositSQL = """
                INSERT INTO deposit_records(deposit_date, account_id, reference, memo, total_amount, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """
            try withStatement(insertDepositSQL) { stmt in
                bindText(stmt: stmt, index: 1, value: depositDate)
                sqlite3_bind_int64(stmt, 2, destinationAccountID)
                bindText(stmt: stmt, index: 3, value: reference)
                bindText(stmt: stmt, index: 4, value: memo)
                sqlite3_bind_double(stmt, 5, total)
                bindText(stmt: stmt, index: 6, value: isoNow())
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
            let depositID = sqlite3_last_insert_rowid(db)

            for paymentID in uniquePaymentIDs {
                var amount = 0.0
                try withStatement("SELECT amount FROM payments_received WHERE id = ? LIMIT 1") { stmt in
                    sqlite3_bind_int64(stmt, 1, paymentID)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        amount = sqlite3_column_double(stmt, 0)
                    } else {
                        throw DBError.stepFailed("Missing payment while recording deposit.")
                    }
                }

                try withStatement(
                    """
                    INSERT INTO deposit_record_lines(deposit_id, payment_id, amount, created_at)
                    VALUES (?, ?, ?, ?)
                    """
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, depositID)
                    sqlite3_bind_int64(stmt, 2, paymentID)
                    sqlite3_bind_double(stmt, 3, amount)
                    bindText(stmt: stmt, index: 4, value: isoNow())
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }

                try withStatement("UPDATE payments_received SET deposit_account_id = ? WHERE id = ?") { stmt in
                    sqlite3_bind_int64(stmt, 1, destinationAccountID)
                    sqlite3_bind_int64(stmt, 2, paymentID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            try exec("COMMIT;")
            // Book the deposit (Undeposited → bank) and re-book each payment, whose cash
            // side now belongs in Undeposited Funds.
            try? repostDeposit(depositID)
            for paymentID in uniquePaymentIDs { try? repostPayment(paymentID) }
            return depositID
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func fetchRecentDeposits(limit: Int = 12) throws -> [DepositRecordRow] {
        let sql = """
            SELECT d.id, d.deposit_date, COALESCE(a.name, ''), d.reference, d.memo, d.total_amount
            FROM deposit_records d
            LEFT JOIN gl_accounts a ON d.account_id = a.id
            ORDER BY d.deposit_date DESC, d.id DESC
            LIMIT ?
            """
        var rows: [DepositRecordRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(DepositRecordRow(
                    id: sqlite3_column_int64(stmt, 0),
                    depositDate: columnText(stmt, 1),
                    accountName: columnText(stmt, 2),
                    reference: columnText(stmt, 3),
                    memo: columnText(stmt, 4),
                    totalAmount: sqlite3_column_double(stmt, 5)
                ))
            }
        }
        return rows
    }

    func fetchPaymentsForDeposit(depositID: Int64) throws -> [PaymentReceivedRow] {
        let sql = """
            SELECT p.id,
                   COALESCE(c.name, ''),
                   COALESCE(
                       (
                           SELECT group_concat(inv.invoice_number, ', ')
                           FROM payment_applications pa
                           JOIN native_invoices inv ON inv.id = pa.invoice_id
                           WHERE pa.payment_id = p.id
                       ),
                       CASE WHEN p.invoice_id IS NOT NULL AND p.invoice_id != 0 THEN ni.invoice_number ELSE '' END,
                       COALESCE(sr.receipt_number, ''),
                       ''
                   ),
                   p.payment_date,
                   drl.amount,
                   p.method,
                   COALESCE(p.reference, '')
            FROM deposit_record_lines drl
            JOIN payments_received p ON p.id = drl.payment_id
            LEFT JOIN customers c ON p.customer_id = c.id
            LEFT JOIN native_invoices ni ON p.invoice_id = ni.id
            LEFT JOIN sales_receipts sr ON sr.payment_id = p.id
            WHERE drl.deposit_id = ?
            ORDER BY p.payment_date, p.id
            """
        var rows: [PaymentReceivedRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, depositID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(PaymentReceivedRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerName: columnText(stmt, 1),
                    invoiceNumber: columnText(stmt, 2),
                    paymentDate: columnText(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4),
                    method: columnText(stmt, 5),
                    reference: columnText(stmt, 6)
                ))
            }
        }
        return rows
    }

    // MARK: - Expenses

    func fetchExpenses(search: String = "") throws -> [ExpenseRow] {
        let sql = """
            SELECT e.id,
                   COALESCE(e.vendor_id, 0),
                   CASE WHEN e.vendor_id IS NOT NULL THEN COALESCE(v.name, e.vendor_name_override)
                        ELSE e.vendor_name_override END,
                   COALESCE(e.job_id, 0),
                   COALESCE(j.name, ''),
                   e.expense_date, e.amount,
                   COALESCE(a.name, ''),
                   COALESCE(e.account_id, 0),
                   COALESCE(e.payment_account_id, 0),
                   COALESCE(pa.name, ''),
                   e.check_number, e.memo,
                   COALESCE(e.cleared, 0)
            FROM expenses e
            LEFT JOIN vendors v ON e.vendor_id = v.id
            LEFT JOIN jobs j ON e.job_id = j.id
            LEFT JOIN gl_accounts a ON e.account_id = a.id
            LEFT JOIN gl_accounts pa ON e.payment_account_id = pa.id
            WHERE (? = '' OR lower(e.vendor_name_override) LIKE ? OR lower(v.name) LIKE ?
                   OR lower(a.name) LIKE ? OR e.check_number LIKE ? OR lower(e.memo) LIKE ?
                   OR lower(COALESCE(j.name, '')) LIKE ?)
            ORDER BY e.expense_date DESC, e.id DESC
            LIMIT 500
            """
        let like = "%\(search.lowercased())%"
        var rows: [ExpenseRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: search)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: like)
            bindText(stmt: stmt, index: 5, value: like)
            bindText(stmt: stmt, index: 6, value: like)
            bindText(stmt: stmt, index: 7, value: like)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ExpenseRow(
                    id: sqlite3_column_int64(stmt, 0),
                    vendorID: sqlite3_column_int64(stmt, 1),
                    vendorName: columnText(stmt, 2),
                    jobID: sqlite3_column_int64(stmt, 3),
                    jobName: columnText(stmt, 4),
                    expenseDate: columnText(stmt, 5),
                    amount: sqlite3_column_double(stmt, 6),
                    accountName: columnText(stmt, 7),
                    accountID: sqlite3_column_int64(stmt, 8),
                    paymentAccountID: sqlite3_column_int64(stmt, 9),
                    paymentAccountName: columnText(stmt, 10),
                    checkNumber: columnText(stmt, 11),
                    memo: columnText(stmt, 12),
                    cleared: sqlite3_column_int64(stmt, 13) != 0
                ))
            }
        }
        return rows
    }

    func fetchExpense(id: Int64) throws -> ExpenseRow? {
        let sql = """
            SELECT e.id,
                   COALESCE(e.vendor_id, 0),
                   CASE WHEN e.vendor_id IS NOT NULL THEN COALESCE(v.name, e.vendor_name_override)
                        ELSE e.vendor_name_override END,
                   COALESCE(e.job_id, 0),
                   COALESCE(j.name, ''),
                   e.expense_date, e.amount,
                   COALESCE(a.name, ''),
                   COALESCE(e.account_id, 0),
                   COALESCE(e.payment_account_id, 0),
                   COALESCE(pa.name, ''),
                   e.check_number, e.memo
            FROM expenses e
            LEFT JOIN vendors v ON e.vendor_id = v.id
            LEFT JOIN jobs j ON e.job_id = j.id
            LEFT JOIN gl_accounts a ON e.account_id = a.id
            LEFT JOIN gl_accounts pa ON e.payment_account_id = pa.id
            WHERE e.id = ?
            LIMIT 1
            """
        var row: ExpenseRow?
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                row = ExpenseRow(
                    id: sqlite3_column_int64(stmt, 0),
                    vendorID: sqlite3_column_int64(stmt, 1),
                    vendorName: columnText(stmt, 2),
                    jobID: sqlite3_column_int64(stmt, 3),
                    jobName: columnText(stmt, 4),
                    expenseDate: columnText(stmt, 5),
                    amount: sqlite3_column_double(stmt, 6),
                    accountName: columnText(stmt, 7),
                    accountID: sqlite3_column_int64(stmt, 8),
                    paymentAccountID: sqlite3_column_int64(stmt, 9),
                    paymentAccountName: columnText(stmt, 10),
                    checkNumber: columnText(stmt, 11),
                    memo: columnText(stmt, 12)
                )
            }
        }
        return row
    }

    func fetchVendorExpenseHistory(search: String, year: Int?) throws -> [ExpenseRow] {
        let searchValue = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !searchValue.isEmpty else { return [] }

        let yearText = year.map(String.init) ?? ""
        let like = "%\(searchValue)%"
        let sql = """
            SELECT e.id,
                   COALESCE(e.vendor_id, 0),
                   CASE WHEN e.vendor_id IS NOT NULL THEN COALESCE(v.name, e.vendor_name_override)
                        ELSE e.vendor_name_override END,
                   COALESCE(e.job_id, 0),
                   COALESCE(j.name, ''),
                   e.expense_date, e.amount,
                   COALESCE(a.name, ''),
                   COALESCE(e.account_id, 0),
                   COALESCE(e.payment_account_id, 0),
                   COALESCE(pa.name, ''),
                   e.check_number, e.memo
            FROM expenses e
            LEFT JOIN vendors v ON e.vendor_id = v.id
            LEFT JOIN jobs j ON e.job_id = j.id
            LEFT JOIN gl_accounts a ON e.account_id = a.id
            LEFT JOIN gl_accounts pa ON e.payment_account_id = pa.id
            WHERE (lower(COALESCE(v.name, '')) LIKE ?
                   OR lower(COALESCE(e.vendor_name_override, '')) LIKE ?
                   OR lower(COALESCE(v.company, '')) LIKE ?)
              AND (? = '' OR substr(e.expense_date, 1, 4) = ?)
            ORDER BY e.expense_date DESC, e.id DESC
            """

        var rows: [ExpenseRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: like)
            bindText(stmt: stmt, index: 2, value: like)
            bindText(stmt: stmt, index: 3, value: like)
            bindText(stmt: stmt, index: 4, value: yearText)
            bindText(stmt: stmt, index: 5, value: yearText)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ExpenseRow(
                    id: sqlite3_column_int64(stmt, 0),
                    vendorID: sqlite3_column_int64(stmt, 1),
                    vendorName: columnText(stmt, 2),
                    jobID: sqlite3_column_int64(stmt, 3),
                    jobName: columnText(stmt, 4),
                    expenseDate: columnText(stmt, 5),
                    amount: sqlite3_column_double(stmt, 6),
                    accountName: columnText(stmt, 7),
                    accountID: sqlite3_column_int64(stmt, 8),
                    paymentAccountID: sqlite3_column_int64(stmt, 9),
                    paymentAccountName: columnText(stmt, 10),
                    checkNumber: columnText(stmt, 11),
                    memo: columnText(stmt, 12)
                ))
            }
        }
        return rows
    }

    func fetchVendorExpenseHistorySummary(search: String, year: Int?) throws -> VendorExpenseHistorySummary {
        let searchValue = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSearch = "%\(searchValue)%"
        let yearText = year.map(String.init) ?? ""

        if searchValue.isEmpty {
            return VendorExpenseHistorySummary(
                searchText: "",
                year: year,
                totalPaid: 0,
                transactionCount: 0,
                matchedVendorCount: 0,
                historical1099Total: nil
            )
        }

        let expenseSQL = """
            SELECT COALESCE(SUM(e.amount), 0), COUNT(*)
            FROM expenses e
            LEFT JOIN vendors v ON e.vendor_id = v.id
            WHERE (lower(COALESCE(v.name, '')) LIKE ?
                   OR lower(COALESCE(e.vendor_name_override, '')) LIKE ?
                   OR lower(COALESCE(v.company, '')) LIKE ?)
              AND (? = '' OR substr(e.expense_date, 1, 4) = ?)
            """

        var totalPaid = 0.0
        var transactionCount = 0
        try withStatement(expenseSQL) { stmt in
            bindText(stmt: stmt, index: 1, value: normalizedSearch)
            bindText(stmt: stmt, index: 2, value: normalizedSearch)
            bindText(stmt: stmt, index: 3, value: normalizedSearch)
            bindText(stmt: stmt, index: 4, value: yearText)
            bindText(stmt: stmt, index: 5, value: yearText)
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalPaid = sqlite3_column_double(stmt, 0)
                transactionCount = Int(sqlite3_column_int(stmt, 1))
            }
        }

        let vendorCountSQL = """
            SELECT COUNT(*)
            FROM vendors
            WHERE lower(name) LIKE ? OR lower(company) LIKE ?
            """
        var matchedVendorCount = 0
        try withStatement(vendorCountSQL) { stmt in
            bindText(stmt: stmt, index: 1, value: normalizedSearch)
            bindText(stmt: stmt, index: 2, value: normalizedSearch)
            if sqlite3_step(stmt) == SQLITE_ROW {
                matchedVendorCount = Int(sqlite3_column_int(stmt, 0))
            }
        }

        var historical1099Total: Double?
        if let year {
            let historySQL = """
                SELECT SUM(total_paid)
                FROM historical_1099_totals
                WHERE tax_year = ?
                  AND lower(vendor_name) LIKE ?
                """
            try withStatement(historySQL) { stmt in
                sqlite3_bind_int(stmt, 1, Int32(year))
                bindText(stmt: stmt, index: 2, value: normalizedSearch)
                if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                    historical1099Total = sqlite3_column_double(stmt, 0)
                }
            }
        }

        return VendorExpenseHistorySummary(
            searchText: search,
            year: year,
            totalPaid: totalPaid,
            transactionCount: transactionCount,
            matchedVendorCount: matchedVendorCount,
            historical1099Total: historical1099Total
        )
    }

    @discardableResult
    func insertExpense(
        vendorNameOverride: String, vendorID: Int64?,
        expenseDate: String, amount: Double,
        accountID: Int64?, paymentAccountID: Int64?,
        checkNumber: String, memo: String,
        jobID: Int64? = nil
    ) throws -> Int64 {
        let sql = """
            INSERT INTO expenses(vendor_id, vendor_name_override, expense_date, amount,
                                 account_id, payment_account_id, check_number, memo, job_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            if let vid = vendorID { sqlite3_bind_int64(stmt, 1, vid) } else { sqlite3_bind_null(stmt, 1) }
            bindText(stmt: stmt, index: 2, value: vendorNameOverride)
            bindText(stmt: stmt, index: 3, value: expenseDate)
            sqlite3_bind_double(stmt, 4, amount)
            if let aid = accountID { sqlite3_bind_int64(stmt, 5, aid) } else { sqlite3_bind_null(stmt, 5) }
            if let paid = paymentAccountID { sqlite3_bind_int64(stmt, 6, paid) } else { sqlite3_bind_null(stmt, 6) }
            bindText(stmt: stmt, index: 7, value: checkNumber)
            bindText(stmt: stmt, index: 8, value: memo)
            if let jobID {
                sqlite3_bind_int64(stmt, 9, jobID)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            bindText(stmt: stmt, index: 10, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        let expenseID = sqlite3_last_insert_rowid(db)
        try? repostExpense(expenseID)
        return expenseID
    }

    /// Insert a GL account and return its id. Used by reconcile harness seeding
    /// (and any future account-creation flow).
    func insertGLAccount(name: String, type: String, number: String) throws -> Int64 {
        try withStatement("INSERT INTO gl_accounts(name, type, number) VALUES (?, ?, ?)") { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: type)
            bindText(stmt: stmt, index: 3, value: number)
            if sqlite3_step(stmt) != SQLITE_DONE { throw DBError.stepFailed(lastErrorMessage) }
        }
        return sqlite3_last_insert_rowid(db)
    }

    /// Insert a standalone deposit record (not grouped from undeposited payments)
    /// and return its id. Used by reconcile harness seeding.
    func insertDepositRecord(depositDate: String, accountID: Int64, reference: String, memo: String, totalAmount: Double) throws -> Int64 {
        let sql = """
            INSERT INTO deposit_records(deposit_date, account_id, reference, memo, total_amount, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: depositDate)
            sqlite3_bind_int64(stmt, 2, accountID)
            bindText(stmt: stmt, index: 3, value: reference)
            bindText(stmt: stmt, index: 4, value: memo)
            sqlite3_bind_double(stmt, 5, totalAmount)
            bindText(stmt: stmt, index: 6, value: isoNow())
            if sqlite3_step(stmt) != SQLITE_DONE { throw DBError.stepFailed(lastErrorMessage) }
        }
        return sqlite3_last_insert_rowid(db)
    }

    func fetchExpenseCheckItemLines(expenseID: Int64) throws -> [ExpenseCheckItemLineRow] {
        let sql = """
            SELECT id,
                   COALESCE(service_item_id, 0),
                   item_name,
                   description,
                   quantity,
                   rate,
                   amount
            FROM expense_check_item_lines
            WHERE expense_id = ?
            ORDER BY sort_order, id
            """
        var rows: [ExpenseCheckItemLineRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, expenseID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ExpenseCheckItemLineRow(
                    id: sqlite3_column_int64(stmt, 0),
                    serviceItemID: sqlite3_column_int64(stmt, 1),
                    itemName: columnText(stmt, 2),
                    description: columnText(stmt, 3),
                    quantity: sqlite3_column_double(stmt, 4),
                    rate: sqlite3_column_double(stmt, 5),
                    amount: sqlite3_column_double(stmt, 6)
                ))
            }
        }
        return rows
    }

    func replaceExpenseCheckItemLines(expenseID: Int64, lines: [CheckItemDraft]) throws {
        try withStatement("DELETE FROM expense_check_item_lines WHERE expense_id = ?") { stmt in
            sqlite3_bind_int64(stmt, 1, expenseID)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }

        guard !lines.isEmpty else { return }

        let sql = """
            INSERT INTO expense_check_item_lines(
                expense_id,
                sort_order,
                service_item_id,
                item_name,
                description,
                quantity,
                rate,
                amount,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        for (index, line) in lines.enumerated() {
            try withStatement(sql) { stmt in
                sqlite3_bind_int64(stmt, 1, expenseID)
                sqlite3_bind_int(stmt, 2, Int32(index))
                if line.serviceItemID != 0 {
                    sqlite3_bind_int64(stmt, 3, line.serviceItemID)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                bindText(stmt: stmt, index: 4, value: line.itemName)
                bindText(stmt: stmt, index: 5, value: line.description)
                sqlite3_bind_double(stmt, 6, line.quantity)
                sqlite3_bind_double(stmt, 7, line.rate)
                sqlite3_bind_double(stmt, 8, line.amount)
                bindText(stmt: stmt, index: 9, value: isoNow())
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
        }
    }

    // MARK: - P&L Report

    func fetchPLReport(from: String, to: String) throws -> PLReport {
        // Income: payments received by customer, including linked sales receipts
        let incomeSQL = """
            SELECT COALESCE(c.name, 'Unknown Customer'), SUM(p.amount)
            FROM payments_received p
            LEFT JOIN customers c ON p.customer_id = c.id
            WHERE p.payment_date >= ? AND p.payment_date <= ?
            GROUP BY p.customer_id
            ORDER BY SUM(p.amount) DESC
            """
        var incomeLines: [PLReportLine] = []
        try withStatement(incomeSQL) { stmt in
            bindText(stmt: stmt, index: 1, value: from)
            bindText(stmt: stmt, index: 2, value: to)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let label = columnText(stmt, 0)
                let total = sqlite3_column_double(stmt, 1)
                if total > 0 { incomeLines.append(PLReportLine(label: label, total: total)) }
            }
        }

        // Expenses: by expense account
        let expenseSQL = """
            SELECT COALESCE(a.name, 'Uncategorized'), SUM(e.amount)
            FROM expenses e
            LEFT JOIN gl_accounts a ON e.account_id = a.id
            WHERE e.expense_date >= ? AND e.expense_date <= ?
            GROUP BY e.account_id
            ORDER BY SUM(e.amount) DESC
            """
        var expenseLines: [PLReportLine] = []
        try withStatement(expenseSQL) { stmt in
            bindText(stmt: stmt, index: 1, value: from)
            bindText(stmt: stmt, index: 2, value: to)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let label = columnText(stmt, 0)
                let total = sqlite3_column_double(stmt, 1)
                if total > 0 { expenseLines.append(PLReportLine(label: label, total: total)) }
            }
        }

        return PLReport(fromDate: from, toDate: to, incomeLines: incomeLines, expenseLines: expenseLines)
    }

    func fetchHistoricalPLYears() throws -> [Int] {
        let sql = """
            SELECT DISTINCT report_year
            FROM historical_pl_lines
            ORDER BY report_year DESC
            """
        var years: [Int] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                years.append(Int(sqlite3_column_int(stmt, 0)))
            }
        }
        return years
    }

    func fetchHistoricalPLReport(year: Int) throws -> HistoricalPLReport? {
        func lines(for section: String) throws -> [PLReportLine] {
            let sql = """
                SELECT account_name, SUM(total)
                FROM historical_pl_lines
                WHERE report_year = ? AND section = ?
                GROUP BY account_name
                HAVING ABS(SUM(total)) >= 0.005
                ORDER BY SUM(total) DESC, account_name
                """
            var rows: [PLReportLine] = []
            try withStatement(sql) { stmt in
                sqlite3_bind_int(stmt, 1, Int32(year))
                bindText(stmt: stmt, index: 2, value: section)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append(
                        PLReportLine(
                            label: columnText(stmt, 0),
                            total: sqlite3_column_double(stmt, 1)
                        )
                    )
                }
            }
            return rows
        }

        let incomeLines = try lines(for: "income")
        let cogsLines = try lines(for: "cogs")
        let expenseLines = try lines(for: "expense")
        if incomeLines.isEmpty && cogsLines.isEmpty && expenseLines.isEmpty {
            return nil
        }
        return HistoricalPLReport(
            year: year,
            incomeLines: incomeLines,
            cogsLines: cogsLines,
            expenseLines: expenseLines
        )
    }

    func fetchHistoricalTrialBalanceReport() throws -> HistoricalTrialBalanceReport? {
        let headerSQL = """
            SELECT as_of_label, source_name
            FROM historical_trial_balance_lines
            ORDER BY id
            LIMIT 1
            """
        var asOfLabel = ""
        var sourceName = ""
        try withStatement(headerSQL) { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                asOfLabel = columnText(stmt, 0)
                sourceName = columnText(stmt, 1)
            }
        }
        guard !asOfLabel.isEmpty || !sourceName.isEmpty else {
            return nil
        }

        let lineSQL = """
            SELECT account_name, debit, credit
            FROM historical_trial_balance_lines
            ORDER BY account_name
            """
        var lines: [TrialBalanceLine] = []
        try withStatement(lineSQL) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                lines.append(
                    TrialBalanceLine(
                        accountName: columnText(stmt, 0),
                        debit: sqlite3_column_double(stmt, 1),
                        credit: sqlite3_column_double(stmt, 2)
                    )
                )
            }
        }
        guard !lines.isEmpty else { return nil }
        return HistoricalTrialBalanceReport(asOfLabel: asOfLabel, sourceName: sourceName, lines: lines)
    }

    func fetchHistoricalCashFlowReport() throws -> HistoricalCashFlowReport? {
        let headerSQL = """
            SELECT as_of_label, source_name
            FROM historical_cash_flow_lines
            ORDER BY id
            LIMIT 1
            """
        var asOfLabel = ""
        var sourceName = ""
        try withStatement(headerSQL) { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                asOfLabel = columnText(stmt, 0)
                sourceName = columnText(stmt, 1)
            }
        }
        guard !asOfLabel.isEmpty || !sourceName.isEmpty else {
            return nil
        }

        let sectionSQL = """
            SELECT section_name, line_label, total
            FROM historical_cash_flow_lines
            ORDER BY section_sort, line_sort, id
            """
        var bucket: [String: [HistoricalCashFlowLine]] = [:]
        var orderedSections: [String] = []
        try withStatement(sectionSQL) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let sectionName = columnText(stmt, 0)
                let line = HistoricalCashFlowLine(
                    label: columnText(stmt, 1),
                    total: sqlite3_column_double(stmt, 2)
                )
                if bucket[sectionName] == nil {
                    orderedSections.append(sectionName)
                }
                bucket[sectionName, default: []].append(line)
            }
        }

        let sections = orderedSections.compactMap { title -> HistoricalCashFlowSection? in
            guard let lines = bucket[title], !lines.isEmpty else { return nil }
            return HistoricalCashFlowSection(title: title, lines: lines)
        }
        guard !sections.isEmpty else { return nil }
        return HistoricalCashFlowReport(asOfLabel: asOfLabel, sourceName: sourceName, sections: sections)
    }

    func fetchHistoricalSalesByItemReport() throws -> HistoricalSalesByItemReport? {
        let headerSQL = """
            SELECT period_label, source_name
            FROM historical_sales_by_item_lines
            ORDER BY id
            LIMIT 1
            """
        var periodLabel = ""
        var sourceName = ""
        try withStatement(headerSQL) { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                periodLabel = columnText(stmt, 0)
                sourceName = columnText(stmt, 1)
            }
        }
        guard !periodLabel.isEmpty || !sourceName.isEmpty else {
            return nil
        }

        let sql = """
            SELECT section_name, item_name, quantity, amount, percent_of_sales, average_price, is_subtotal
            FROM historical_sales_by_item_lines
            ORDER BY section_sort, line_sort, id
            """
        var bucket: [String: [HistoricalSalesByItemLine]] = [:]
        var orderedSections: [String] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let sectionName = columnText(stmt, 0)
                let line = HistoricalSalesByItemLine(
                    itemName: columnText(stmt, 1),
                    quantity: sqlite3_column_double(stmt, 2),
                    amount: sqlite3_column_double(stmt, 3),
                    percentOfSales: sqlite3_column_double(stmt, 4),
                    averagePrice: sqlite3_column_double(stmt, 5),
                    isSubtotal: sqlite3_column_int(stmt, 6) != 0
                )
                if bucket[sectionName] == nil {
                    orderedSections.append(sectionName)
                }
                bucket[sectionName, default: []].append(line)
            }
        }

        let sections = orderedSections.compactMap { title -> HistoricalSalesByItemSection? in
            guard let lines = bucket[title], !lines.isEmpty else { return nil }
            return HistoricalSalesByItemSection(title: title, lines: lines)
        }
        guard !sections.isEmpty else { return nil }
        return HistoricalSalesByItemReport(periodLabel: periodLabel, sourceName: sourceName, sections: sections)
    }

    // MARK: - V3 Migration (Bills)

    func migrateV3() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS bills (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                vendor_id INTEGER REFERENCES vendors(id),
                vendor_name_override TEXT NOT NULL DEFAULT '',
                bill_date TEXT NOT NULL,
                due_date TEXT NOT NULL DEFAULT '',
                amount REAL NOT NULL,
                account_id INTEGER REFERENCES gl_accounts(id),
                memo TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'unpaid',
                paid_date TEXT,
                check_number TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            """)
    }

    // MARK: - Invoice Detail

    func fetchInvoice(id: Int64) throws -> NativeInvoiceRow? {
        let sql = """
            SELECT ni.id, ni.invoice_number, ni.customer_id, COALESCE(c.name, ''),
                   COALESCE(ni.job_id, 0), COALESCE(j.name, ''),
                   ni.issue_date, ni.due_date, ni.memo, ni.status, ni.total, ni.paid, COALESCE(ni.customer_name_override, '')
            FROM native_invoices ni
            LEFT JOIN customers c ON ni.customer_id = c.id
            LEFT JOIN jobs j ON ni.job_id = j.id
            WHERE ni.id = ?
            """
        var row: NativeInvoiceRow?
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                row = NativeInvoiceRow(
                    id: sqlite3_column_int64(stmt, 0),
                    invoiceNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    customerNameOverride: columnText(stmt, 12),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    issueDate: columnText(stmt, 6),
                    dueDate: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    total: sqlite3_column_double(stmt, 10),
                    paid: sqlite3_column_double(stmt, 11)
                )
            }
        }
        return row
    }

    func fetchSalesReceipt(id: Int64) throws -> SalesReceiptRow? {
        let sql = """
            SELECT sr.id, sr.receipt_number, COALESCE(sr.customer_id, 0), COALESCE(c.name, ''),
                   COALESCE(sr.job_id, 0), COALESCE(j.name, ''),
                   sr.receipt_date, sr.memo, sr.total,
                   COALESCE(sr.payment_method_id, 0), COALESCE(pm.name, ''),
                   COALESCE(pr.deposit_account_id, 0), COALESCE(a.name, ''),
                   COALESCE(sr.payment_id, 0)
            FROM sales_receipts sr
            LEFT JOIN customers c ON sr.customer_id = c.id
            LEFT JOIN jobs j ON sr.job_id = j.id
            LEFT JOIN payment_methods pm ON sr.payment_method_id = pm.id
            LEFT JOIN payments_received pr ON sr.payment_id = pr.id
            LEFT JOIN gl_accounts a ON pr.deposit_account_id = a.id
            WHERE sr.id = ?
            """
        var row: SalesReceiptRow?
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                row = SalesReceiptRow(
                    id: sqlite3_column_int64(stmt, 0),
                    receiptNumber: columnText(stmt, 1),
                    customerID: sqlite3_column_int64(stmt, 2),
                    customerName: columnText(stmt, 3),
                    jobID: sqlite3_column_int64(stmt, 4),
                    jobName: columnText(stmt, 5),
                    receiptDate: columnText(stmt, 6),
                    memo: columnText(stmt, 7),
                    total: sqlite3_column_double(stmt, 8),
                    paymentMethodID: sqlite3_column_int64(stmt, 9),
                    paymentMethodName: columnText(stmt, 10),
                    depositAccountID: sqlite3_column_int64(stmt, 11),
                    depositAccountName: columnText(stmt, 12),
                    paymentID: sqlite3_column_int64(stmt, 13)
                )
            }
        }
        return row
    }

    func fetchInvoiceLines(invoiceID: Int64) throws -> [InvoiceLineRow] {
        let sql = "SELECT id, description, quantity, rate, amount FROM invoice_lines WHERE invoice_id = ? ORDER BY id"
        var rows: [InvoiceLineRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, invoiceID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(InvoiceLineRow(
                    id: sqlite3_column_int64(stmt, 0),
                    description: columnText(stmt, 1),
                    quantity: sqlite3_column_double(stmt, 2),
                    rate: sqlite3_column_double(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4)
                ))
            }
        }
        return rows
    }

    func fetchSalesReceiptLines(receiptID: Int64) throws -> [SalesReceiptLineRow] {
        let sql = "SELECT id, description, quantity, rate, amount FROM sales_receipt_lines WHERE receipt_id = ? ORDER BY id"
        var rows: [SalesReceiptLineRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, receiptID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SalesReceiptLineRow(
                    id: sqlite3_column_int64(stmt, 0),
                    description: columnText(stmt, 1),
                    quantity: sqlite3_column_double(stmt, 2),
                    rate: sqlite3_column_double(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4)
                ))
            }
        }
        return rows
    }

    func fetchPaymentsForInvoice(invoiceID: Int64) throws -> [PaymentDetailRow] {
        let sql = """
            SELECT pr.id, pr.payment_date, pa.applied_amount, pr.method, pr.reference, pr.memo
            FROM payment_applications pa
            JOIN payments_received pr ON pr.id = pa.payment_id
            WHERE pa.invoice_id = ?
            UNION ALL
            SELECT pr.id, pr.payment_date, pr.amount, pr.method, pr.reference, pr.memo
            FROM payments_received pr
            WHERE pr.invoice_id = ?
              AND NOT EXISTS (
                  SELECT 1
                  FROM payment_applications pa
                  WHERE pa.payment_id = pr.id
              )
            ORDER BY payment_date, id
            """
        var rows: [PaymentDetailRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, invoiceID)
            sqlite3_bind_int64(stmt, 2, invoiceID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(PaymentDetailRow(
                    id: sqlite3_column_int64(stmt, 0),
                    paymentDate: columnText(stmt, 1),
                    amount: sqlite3_column_double(stmt, 2),
                    method: columnText(stmt, 3),
                    reference: columnText(stmt, 4),
                    memo: columnText(stmt, 5)
                ))
            }
        }
        return rows
    }

    func fetchCreditApplicationsForInvoice(invoiceID: Int64) throws -> [CreditApplicationDetailRow] {
        let sql = """
            SELECT ca.id, ca.applied_date, ca.amount, COALESCE(cc.reference, ''), COALESCE(cc.memo, ''), COALESCE(cc.credit_type, 'credit')
            FROM credit_applications ca
            JOIN customer_credits cc ON cc.id = ca.customer_credit_id
            WHERE ca.invoice_id = ?
            ORDER BY ca.applied_date, ca.id
            """
        var rows: [CreditApplicationDetailRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, invoiceID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(CreditApplicationDetailRow(
                    id: sqlite3_column_int64(stmt, 0),
                    appliedDate: columnText(stmt, 1),
                    amount: sqlite3_column_double(stmt, 2),
                    reference: columnText(stmt, 3),
                    memo: columnText(stmt, 4),
                    creditType: columnText(stmt, 5)
                ))
            }
        }
        return rows
    }

    func voidInvoice(id: Int64) throws {
        let sql = "UPDATE native_invoices SET status='void', updated_at=? WHERE id=?"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: isoNow())
            sqlite3_bind_int64(stmt, 2, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        try? repostInvoice(id)   // parity with rebuildJournal, which posts regardless of status
    }

    // MARK: - Customer Update

    func updateCustomer(id: Int64, name: String, company: String, primaryContact: String, email: String, phone: String,
                        address: String, city: String, state: String, zip: String) throws {
        let sql = "UPDATE customers SET name=?, company=?, primary_contact=?, email=?, phone=?, address=?, city=?, state=?, zip=? WHERE id=?"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: company)
            bindText(stmt: stmt, index: 3, value: primaryContact)
            bindText(stmt: stmt, index: 4, value: email)
            bindText(stmt: stmt, index: 5, value: phone)
            bindText(stmt: stmt, index: 6, value: address)
            bindText(stmt: stmt, index: 7, value: city)
            bindText(stmt: stmt, index: 8, value: state)
            bindText(stmt: stmt, index: 9, value: zip)
            sqlite3_bind_int64(stmt, 10, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func updateDocumentStoredPath(id: Int64, storedPath: String) throws {
        let sql = "UPDATE documents SET stored_path=? WHERE id=?"
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: storedPath)
            sqlite3_bind_int64(stmt, 2, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    // MARK: - Expense Update / Delete

    func updateExpense(id: Int64, vendorNameOverride: String, vendorID: Int64?,
                       expenseDate: String, amount: Double,
                       accountID: Int64?, paymentAccountID: Int64?,
                       checkNumber: String, memo: String, jobID: Int64? = nil) throws {
        let sql = """
            UPDATE expenses SET vendor_id=?, vendor_name_override=?, expense_date=?, amount=?,
                   account_id=?, payment_account_id=?, check_number=?, memo=?, job_id=?
            WHERE id=?
            """
        try withStatement(sql) { stmt in
            if let vid = vendorID { sqlite3_bind_int64(stmt, 1, vid) } else { sqlite3_bind_null(stmt, 1) }
            bindText(stmt: stmt, index: 2, value: vendorNameOverride)
            bindText(stmt: stmt, index: 3, value: expenseDate)
            sqlite3_bind_double(stmt, 4, amount)
            if let aid = accountID { sqlite3_bind_int64(stmt, 5, aid) } else { sqlite3_bind_null(stmt, 5) }
            if let paid = paymentAccountID { sqlite3_bind_int64(stmt, 6, paid) } else { sqlite3_bind_null(stmt, 6) }
            bindText(stmt: stmt, index: 7, value: checkNumber)
            bindText(stmt: stmt, index: 8, value: memo)
            if let jobID {
                sqlite3_bind_int64(stmt, 9, jobID)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            sqlite3_bind_int64(stmt, 10, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        try? repostExpense(id)   // reflect edited amount/account in the ledger
    }

    func deleteExpense(id: Int64) throws {
        try withStatement("DELETE FROM expense_check_item_lines WHERE expense_id=?") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        let sql = "DELETE FROM expenses WHERE id=?"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        try? repostExpense(id)   // row is gone → clears its ledger lines
    }

    // MARK: - AR Aging Report

    func fetchARAgingReport(asOf: String) throws -> [ARAgingRow] {
        let sql = """
            WITH invoice_buckets AS (
                SELECT ni.customer_id AS customer_id,
                       COALESCE(SUM(CASE WHEN julianday(?) - julianday(ni.due_date) <= 0
                                         THEN ni.total - ni.paid ELSE 0 END), 0) AS current_amount,
                       COALESCE(SUM(CASE WHEN julianday(?) - julianday(ni.due_date) BETWEEN 1 AND 30
                                         THEN ni.total - ni.paid ELSE 0 END), 0) AS days_1_30,
                       COALESCE(SUM(CASE WHEN julianday(?) - julianday(ni.due_date) BETWEEN 31 AND 60
                                         THEN ni.total - ni.paid ELSE 0 END), 0) AS days_31_60,
                       COALESCE(SUM(CASE WHEN julianday(?) - julianday(ni.due_date) BETWEEN 61 AND 90
                                         THEN ni.total - ni.paid ELSE 0 END), 0) AS days_61_90,
                       COALESCE(SUM(CASE WHEN julianday(?) - julianday(ni.due_date) > 90
                                         THEN ni.total - ni.paid ELSE 0 END), 0) AS over_90
                FROM native_invoices ni
                WHERE ni.status NOT IN ('paid', 'void')
                  AND (ni.total - ni.paid) > 0.01
                GROUP BY ni.customer_id
            ),
            credit_totals AS (
                SELECT cc.customer_id AS customer_id,
                       COALESCE(SUM(cc.remaining_amount), 0) AS credit_total
                FROM customer_credits cc
                WHERE cc.remaining_amount > 0.01
                GROUP BY cc.customer_id
            ),
            customer_scope AS (
                SELECT customer_id FROM invoice_buckets
                UNION
                SELECT customer_id FROM credit_totals
            )
            SELECT cs.customer_id,
                   COALESCE(c.name, 'Unknown'),
                   COALESCE(ib.current_amount, 0) - COALESCE(ct.credit_total, 0),
                   COALESCE(ib.days_1_30, 0),
                   COALESCE(ib.days_31_60, 0),
                   COALESCE(ib.days_61_90, 0),
                   COALESCE(ib.over_90, 0)
            FROM customer_scope cs
            LEFT JOIN customers c ON cs.customer_id = c.id
            LEFT JOIN invoice_buckets ib ON ib.customer_id = cs.customer_id
            LEFT JOIN credit_totals ct ON ct.customer_id = cs.customer_id
            WHERE ABS(
                (COALESCE(ib.current_amount, 0) - COALESCE(ct.credit_total, 0))
                + COALESCE(ib.days_1_30, 0)
                + COALESCE(ib.days_31_60, 0)
                + COALESCE(ib.days_61_90, 0)
                + COALESCE(ib.over_90, 0)
            ) > 0.01
            ORDER BY COALESCE(c.name, 'Unknown')
            """
        var rows: [ARAgingRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: asOf)
            bindText(stmt: stmt, index: 2, value: asOf)
            bindText(stmt: stmt, index: 3, value: asOf)
            bindText(stmt: stmt, index: 4, value: asOf)
            bindText(stmt: stmt, index: 5, value: asOf)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ARAgingRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerName: columnText(stmt, 1),
                    current: sqlite3_column_double(stmt, 2),
                    days1_30: sqlite3_column_double(stmt, 3),
                    days31_60: sqlite3_column_double(stmt, 4),
                    days61_90: sqlite3_column_double(stmt, 5),
                    over90: sqlite3_column_double(stmt, 6)
                ))
            }
        }
        return rows
    }

    /// A/P aging: outstanding (unpaid) bills grouped by vendor and bucketed by
    /// how far past `asOf` their due date is. Bills with no due date count as
    /// current. Payments fully clear a bill (status flips to 'paid'), so an
    /// unpaid bill's outstanding amount is simply its `amount`.
    func fetchAPAgingReport(asOf: String) throws -> [APAgingRow] {
        let sql = """
            SELECT COALESCE(b.vendor_id, 0) AS vendor_id,
                   CASE WHEN b.vendor_id IS NOT NULL THEN COALESCE(v.name, b.vendor_name_override)
                        ELSE b.vendor_name_override END AS vendor_name,
                   COALESCE(SUM(CASE WHEN b.due_date = '' OR julianday(?) - julianday(b.due_date) <= 0
                                     THEN b.amount ELSE 0 END), 0) AS current_amount,
                   COALESCE(SUM(CASE WHEN julianday(?) - julianday(b.due_date) BETWEEN 1 AND 30
                                     THEN b.amount ELSE 0 END), 0) AS days_1_30,
                   COALESCE(SUM(CASE WHEN julianday(?) - julianday(b.due_date) BETWEEN 31 AND 60
                                     THEN b.amount ELSE 0 END), 0) AS days_31_60,
                   COALESCE(SUM(CASE WHEN julianday(?) - julianday(b.due_date) BETWEEN 61 AND 90
                                     THEN b.amount ELSE 0 END), 0) AS days_61_90,
                   COALESCE(SUM(CASE WHEN julianday(?) - julianday(b.due_date) > 90
                                     THEN b.amount ELSE 0 END), 0) AS over_90
            FROM bills b
            LEFT JOIN vendors v ON b.vendor_id = v.id
            WHERE b.status = 'unpaid' AND b.amount > 0.01
            GROUP BY vendor_id, vendor_name
            HAVING SUM(b.amount) > 0.01
            ORDER BY vendor_name
            """
        var rows: [APAgingRow] = []
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: asOf)
            bindText(stmt: stmt, index: 2, value: asOf)
            bindText(stmt: stmt, index: 3, value: asOf)
            bindText(stmt: stmt, index: 4, value: asOf)
            bindText(stmt: stmt, index: 5, value: asOf)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(APAgingRow(
                    id: sqlite3_column_int64(stmt, 0),
                    vendorName: columnText(stmt, 1),
                    current: sqlite3_column_double(stmt, 2),
                    days1_30: sqlite3_column_double(stmt, 3),
                    days31_60: sqlite3_column_double(stmt, 4),
                    days61_90: sqlite3_column_double(stmt, 5),
                    over90: sqlite3_column_double(stmt, 6)
                ))
            }
        }
        return rows
    }

    // MARK: - 1099 Report

    func fetch1099Report(year: Int, includeLiveExpenseReview: Bool = false) throws -> [Report1099Row] {
        let historicalSQL = """
            SELECT COALESCE(v.id, -h.id),
                   h.vendor_name,
                   CASE WHEN COALESCE(h.ein, '') != '' THEN h.ein ELSE COALESCE(v.ein, '') END,
                   h.total_paid
            FROM historical_1099_totals h
            LEFT JOIN vendors v ON h.vendor_id = v.id
            WHERE h.tax_year = ?
            ORDER BY h.total_paid DESC, h.vendor_name
            """
        var historicalRows: [Report1099Row] = []
        try withStatement(historicalSQL) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(year))
            while sqlite3_step(stmt) == SQLITE_ROW {
                historicalRows.append(Report1099Row(
                    id: sqlite3_column_int64(stmt, 0),
                    vendorName: columnText(stmt, 1),
                    ein: columnText(stmt, 2),
                    totalPaid: sqlite3_column_double(stmt, 3),
                    source: .historicalSnapshot
                ))
            }
        }
        if !historicalRows.isEmpty {
            return historicalRows
        }

        guard includeLiveExpenseReview else {
            return []
        }

        let from = "\(year)-01-01"
        let to = "\(year)-12-31"
        struct LiveVendorExpense {
            let vendorID: Int64
            let vendorName: String
            let ein: String
            let amount: Double
        }

        let vendorSQL = """
            SELECT id, name, COALESCE(ein, '')
            FROM vendors
            WHERE is_1099 = 1 OR is_internal_self = 1
            ORDER BY name
            """
        var canonicalVendors: [(id: Int64, name: String, ein: String)] = []
        try withStatement(vendorSQL) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                canonicalVendors.append((
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    ein: columnText(stmt, 2)
                ))
            }
        }

        let liveSQL = """
            SELECT e.vendor_id,
                   COALESCE(v.name, e.vendor_name_override),
                   COALESCE(v.ein, ''),
                   COALESCE(v.is_1099, 0),
                   COALESCE(v.is_internal_self, 0),
                   e.amount
            FROM expenses e
            LEFT JOIN vendors v ON e.vendor_id = v.id
            WHERE e.expense_date >= ? AND e.expense_date <= ?
            ORDER BY e.expense_date, e.id
            """

        func normalizedKey(_ value: String) -> String {
            value
                .lowercased()
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }

        func resolveCanonicalVendor(rawName: String, vendorID: Int64) -> (id: Int64, name: String, ein: String)? {
            if let exact = canonicalVendors.first(where: { $0.id == vendorID }) {
                return exact
            }

            let rawKey = normalizedKey(rawName)
            guard !rawKey.isEmpty else { return nil }

            if let exact = canonicalVendors.first(where: { normalizedKey($0.name) == rawKey }) {
                return exact
            }

            if let prefix = canonicalVendors.first(where: {
                let canonicalKey = normalizedKey($0.name)
                return rawKey.hasPrefix(canonicalKey + " ")
            }) {
                return prefix
            }

            return nil
        }

        var grouped: [Int64: Report1099Row] = [:]
        try withStatement(liveSQL) { stmt in
            bindText(stmt: stmt, index: 1, value: from)
            bindText(stmt: stmt, index: 2, value: to)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let vendorID = sqlite3_column_int64(stmt, 0)
                let rawName = columnText(stmt, 1)
                let rawEin = columnText(stmt, 2)
                let is1099 = sqlite3_column_int(stmt, 3) != 0
                let isInternalSelf = sqlite3_column_int(stmt, 4) != 0
                let amount = sqlite3_column_double(stmt, 5)

                guard is1099 || isInternalSelf || !rawName.isEmpty else {
                    continue
                }

                guard let canonical = resolveCanonicalVendor(rawName: rawName, vendorID: vendorID) else {
                    continue
                }

                let existing = grouped[canonical.id]
                grouped[canonical.id] = Report1099Row(
                    id: canonical.id,
                    vendorName: canonical.name,
                    ein: canonical.ein.isEmpty ? rawEin : canonical.ein,
                    totalPaid: (existing?.totalPaid ?? 0) + amount,
                    source: .liveExpenseReview
                )
            }
        }
        return grouped.values.sorted {
            if $0.totalPaid != $1.totalPaid { return $0.totalPaid > $1.totalPaid }
            return $0.vendorName.localizedCaseInsensitiveCompare($1.vendorName) == .orderedAscending
        }
    }

    // MARK: - Customer Statement

    func fetchCustomerStatement(customerID: Int64) throws -> [CustomerStatementLine] {
        var rawLines: [(date: String, type: String, reference: String, amount: Double)] = []

        let estimateSQL = """
            SELECT estimate_number, issue_date
            FROM estimates
            WHERE customer_id = ?
            ORDER BY issue_date, id
            """
        try withStatement(estimateSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rawLines.append((
                    date: columnText(stmt, 1),
                    type: "Estimate",
                    reference: columnText(stmt, 0),
                    amount: 0
                ))
            }
        }

        let receiptSQL = """
            SELECT receipt_number, receipt_date, total
            FROM sales_receipts
            WHERE customer_id = ?
            ORDER BY receipt_date, id
            """
        try withStatement(receiptSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rawLines.append((
                    date: columnText(stmt, 1),
                    type: "Sales Receipt",
                    reference: columnText(stmt, 0),
                    amount: sqlite3_column_double(stmt, 2)
                ))
            }
        }

        let invSQL = """
            SELECT invoice_number, issue_date, total
            FROM native_invoices
            WHERE customer_id = ? AND status != 'void'
            ORDER BY issue_date, id
            """
        try withStatement(invSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rawLines.append((
                    date: columnText(stmt, 1),
                    type: "Invoice",
                    reference: columnText(stmt, 0),
                    amount: sqlite3_column_double(stmt, 2)
                ))
            }
        }

        let paySQL = """
            SELECT payment_date, amount, COALESCE(reference, '')
            FROM payments_received
            WHERE customer_id = ?
            ORDER BY payment_date, id
            """
        try withStatement(paySQL) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rawLines.append((
                    date: columnText(stmt, 0),
                    type: "Payment",
                    reference: columnText(stmt, 2),
                    amount: -sqlite3_column_double(stmt, 1)
                ))
            }
        }

        let creditSQL = """
            SELECT credit_date, remaining_amount, COALESCE(reference, '')
            FROM customer_credits
            WHERE customer_id = ? AND remaining_amount > 0.01
            ORDER BY credit_date, id
            """
        try withStatement(creditSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rawLines.append((
                    date: columnText(stmt, 0),
                    type: "Customer Credit",
                    reference: columnText(stmt, 2),
                    amount: -sqlite3_column_double(stmt, 1)
                ))
            }
        }

        let sortOrder: [String: Int] = ["Estimate": 0, "Invoice": 1, "Sales Receipt": 2, "Payment": 3, "Customer Credit": 4]
        rawLines.sort {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            let lhs = sortOrder[$0.type] ?? 99
            let rhs = sortOrder[$1.type] ?? 99
            if lhs != rhs {
                return lhs < rhs
            }
            return $0.reference < $1.reference
        }

        var runningBalance = 0.0
        return rawLines.map { line in
            runningBalance += line.amount
            return CustomerStatementLine(
                date: line.date,
                type: line.type,
                reference: line.reference,
                amount: line.amount,
                balance: runningBalance
            )
        }
    }

    func fetchCustomerActivitySnapshot(customerID: Int64) throws -> CustomerActivitySnapshot {
        var openBalance = 0.0
        var availableCreditTotal = 0.0
        var availableCreditCount = 0
        try withStatement(
            """
            SELECT COALESCE(SUM(total - paid), 0)
            FROM native_invoices
            WHERE customer_id = ? AND status NOT IN ('paid', 'void')
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                openBalance = sqlite3_column_double(stmt, 0)
            }
        }

        try withStatement(
            """
            SELECT COALESCE(SUM(remaining_amount), 0)
            FROM customer_credits
            WHERE customer_id = ? AND remaining_amount > 0.01
        """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                availableCreditTotal = sqlite3_column_double(stmt, 0)
                openBalance -= availableCreditTotal
            }
        }

        try withStatement(
            """
            SELECT COUNT(*)
            FROM customer_credits
            WHERE customer_id = ? AND remaining_amount > 0.01
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                availableCreditCount = Int(sqlite3_column_int(stmt, 0))
            }
        }

        var estimateCount = 0
        var estimateTotal = 0.0
        try withStatement(
            """
            SELECT COUNT(*), COALESCE(SUM(total), 0)
            FROM estimates
            WHERE customer_id = ?
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                estimateCount = Int(sqlite3_column_int(stmt, 0))
                estimateTotal = sqlite3_column_double(stmt, 1)
            }
        }

        var invoiceCount = 0
        var invoiceTotal = 0.0
        try withStatement(
            """
            SELECT COUNT(*), COALESCE(SUM(total), 0)
            FROM native_invoices
            WHERE customer_id = ? AND status != 'void'
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                invoiceCount = Int(sqlite3_column_int(stmt, 0))
                invoiceTotal = sqlite3_column_double(stmt, 1)
            }
        }

        var paymentCount = 0
        var paymentTotal = 0.0
        try withStatement(
            """
            SELECT COUNT(*), COALESCE(SUM(amount), 0)
            FROM payments_received
            WHERE customer_id = ?
            """
        ) { stmt in
            sqlite3_bind_int64(stmt, 1, customerID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                paymentCount = Int(sqlite3_column_int(stmt, 0))
                paymentTotal = sqlite3_column_double(stmt, 1)
            }
        }

        return CustomerActivitySnapshot(
            openBalance: openBalance,
            estimateCount: estimateCount,
            estimateTotal: estimateTotal,
            invoiceCount: invoiceCount,
            invoiceTotal: invoiceTotal,
            paymentCount: paymentCount,
            paymentTotal: paymentTotal,
            availableCreditCount: availableCreditCount,
            availableCreditTotal: availableCreditTotal
        )
    }

    func fetchJobProfitability(customerID: Int64? = nil, includeInactive: Bool = false) throws -> [JobProfitabilityRow] {
        let sql = """
            WITH estimate_totals AS (
                SELECT job_id,
                       COUNT(*) AS estimate_count,
                       COALESCE(SUM(total), 0) AS estimate_total
                FROM estimates
                WHERE COALESCE(job_id, 0) != 0
                GROUP BY job_id
            ),
            invoice_totals AS (
                SELECT job_id,
                       COUNT(*) AS invoice_count,
                       COALESCE(SUM(invoice_total), 0) AS invoice_total,
                       COALESCE(SUM(open_balance), 0) AS open_balance
                FROM (
                    SELECT job_id,
                           total AS invoice_total,
                           CASE WHEN status != 'void' THEN MAX(total - paid, 0) ELSE 0 END AS open_balance
                    FROM native_invoices
                    WHERE COALESCE(job_id, 0) != 0
                    UNION ALL
                    SELECT job_id,
                           total AS invoice_total,
                           0 AS open_balance
                    FROM sales_receipts
                    WHERE COALESCE(job_id, 0) != 0
                ) receipt_and_invoice_revenue
                GROUP BY job_id
            ),
            expense_totals AS (
                SELECT job_id,
                       COUNT(*) AS expense_count,
                       COALESCE(SUM(amount), 0) AS expense_total
                FROM (
                    SELECT job_id, amount
                    FROM expenses
                    WHERE COALESCE(job_id, 0) != 0
                    UNION ALL
                    SELECT job_id, amount
                    FROM bills
                    WHERE COALESCE(job_id, 0) != 0 AND status = 'unpaid'
                ) job_costs
                GROUP BY job_id
            )
            SELECT j.id,
                   j.customer_id,
                   COALESCE(c.name, ''),
                   j.name,
                   j.status,
                   COALESCE(j.is_active, 1),
                   COALESCE(et.estimate_count, 0),
                   COALESCE(et.estimate_total, 0),
                   COALESCE(it.invoice_count, 0),
                   COALESCE(it.invoice_total, 0),
                   COALESCE(it.open_balance, 0),
                   COALESCE(ext.expense_count, 0),
                   COALESCE(ext.expense_total, 0)
            FROM jobs j
            LEFT JOIN customers c ON c.id = j.customer_id
            LEFT JOIN estimate_totals et ON et.job_id = j.id
            LEFT JOIN invoice_totals it ON it.job_id = j.id
            LEFT JOIN expense_totals ext ON ext.job_id = j.id
            WHERE (? IS NULL OR j.customer_id = ?)
              AND (? = 1 OR COALESCE(j.is_active, 1) = 1)
            ORDER BY COALESCE(c.name, ''), j.name, j.id
            """
        var rows: [JobProfitabilityRow] = []
        try withStatement(sql) { stmt in
            if let customerID {
                sqlite3_bind_int64(stmt, 1, customerID)
                sqlite3_bind_int64(stmt, 2, customerID)
            } else {
                sqlite3_bind_null(stmt, 1)
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_int(stmt, 3, includeInactive ? 1 : 0)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(JobProfitabilityRow(
                    id: sqlite3_column_int64(stmt, 0),
                    customerID: sqlite3_column_int64(stmt, 1),
                    customerName: columnText(stmt, 2),
                    jobName: columnText(stmt, 3),
                    status: columnText(stmt, 4),
                    isActive: sqlite3_column_int(stmt, 5) != 0,
                    estimateCount: Int(sqlite3_column_int(stmt, 6)),
                    estimateTotal: sqlite3_column_double(stmt, 7),
                    invoiceCount: Int(sqlite3_column_int(stmt, 8)),
                    invoicedTotal: sqlite3_column_double(stmt, 9),
                    openInvoiceBalance: sqlite3_column_double(stmt, 10),
                    expenseCount: Int(sqlite3_column_int(stmt, 11)),
                    expenseTotal: sqlite3_column_double(stmt, 12)
                ))
            }
        }
        return rows
    }

    // MARK: - Memorized Transactions

    func fetchMemorizedTransactions(
        type: MemorizedTransactionType? = nil,
        includeInactive: Bool = false
    ) throws -> [MemorizedTransactionRow] {
        let sql: String
        if type == nil {
            sql = """
                SELECT id, name, type, payload_json, is_active, updated_at,
                       reminder_frequency, next_due_date, last_used_at, notes
                FROM memorized_transactions
                WHERE (? = 1 OR is_active = 1)
                ORDER BY
                    CASE WHEN next_due_date = '' THEN 1 ELSE 0 END,
                    next_due_date,
                    lower(name),
                    id
                """
        } else {
            sql = """
                SELECT id, name, type, payload_json, is_active, updated_at,
                       reminder_frequency, next_due_date, last_used_at, notes
                FROM memorized_transactions
                WHERE type = ?
                  AND (? = 1 OR is_active = 1)
                ORDER BY
                    CASE WHEN next_due_date = '' THEN 1 ELSE 0 END,
                    next_due_date,
                    lower(name),
                    id
                """
        }

        var rows: [MemorizedTransactionRow] = []
        try withStatement(sql) { stmt in
            if let type {
                bindText(stmt: stmt, index: 1, value: type.rawValue)
                sqlite3_bind_int(stmt, 2, includeInactive ? 1 : 0)
            } else {
                sqlite3_bind_int(stmt, 1, includeInactive ? 1 : 0)
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let typeValue = MemorizedTransactionType(rawValue: columnText(stmt, 2)) ?? .estimate
                let reminderValue = MemorizedReminderFrequency(rawValue: columnText(stmt, 6)) ?? .none
                rows.append(MemorizedTransactionRow(
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    type: typeValue,
                    payloadJSON: columnText(stmt, 3),
                    isActive: sqlite3_column_int(stmt, 4) != 0,
                    updatedAt: columnText(stmt, 5),
                    reminderFrequency: reminderValue,
                    nextDueDate: columnText(stmt, 7),
                    lastUsedAt: columnText(stmt, 8),
                    notes: columnText(stmt, 9)
                ))
            }
        }
        return rows
    }

    @discardableResult
    func saveMemorizedTransaction(
        name: String,
        type: MemorizedTransactionType,
        payloadJSON: String,
        isActive: Bool = true,
        reminderFrequency: MemorizedReminderFrequency = .none,
        nextDueDate: String = "",
        notes: String = ""
    ) throws -> Int64 {
        let sql = """
            INSERT INTO memorized_transactions(
                name, type, payload_json, is_active, created_at, updated_at,
                reminder_frequency, next_due_date, notes
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(type, name) DO UPDATE SET
                payload_json = excluded.payload_json,
                is_active = excluded.is_active,
                updated_at = excluded.updated_at,
                reminder_frequency = excluded.reminder_frequency,
                next_due_date = excluded.next_due_date,
                notes = excluded.notes
            """

        try withStatement(sql) { stmt in
            let now = isoNow()
            bindText(stmt: stmt, index: 1, value: name)
            bindText(stmt: stmt, index: 2, value: type.rawValue)
            bindText(stmt: stmt, index: 3, value: payloadJSON)
            sqlite3_bind_int(stmt, 4, isActive ? 1 : 0)
            bindText(stmt: stmt, index: 5, value: now)
            bindText(stmt: stmt, index: 6, value: now)
            bindText(stmt: stmt, index: 7, value: reminderFrequency.rawValue)
            bindText(stmt: stmt, index: 8, value: reminderFrequency == .none ? "" : nextDueDate)
            bindText(stmt: stmt, index: 9, value: notes)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }

        var memorizedID: Int64 = 0
        try withStatement(
            "SELECT id FROM memorized_transactions WHERE type = ? AND name = ? LIMIT 1"
        ) { stmt in
            bindText(stmt: stmt, index: 1, value: type.rawValue)
            bindText(stmt: stmt, index: 2, value: name)
            if sqlite3_step(stmt) == SQLITE_ROW {
                memorizedID = sqlite3_column_int64(stmt, 0)
            }
        }
        return memorizedID
    }

    func recordMemorizedTransactionUse(id: Int64, nextDueDate: String) throws {
        try withStatement(
            """
            UPDATE memorized_transactions
            SET last_used_at = ?,
                next_due_date = ?,
                updated_at = ?
            WHERE id = ?
            """
        ) { stmt in
            let now = isoNow()
            bindText(stmt: stmt, index: 1, value: now)
            bindText(stmt: stmt, index: 2, value: nextDueDate)
            bindText(stmt: stmt, index: 3, value: now)
            sqlite3_bind_int64(stmt, 4, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func deleteMemorizedTransaction(id: Int64) throws {
        try withStatement("DELETE FROM memorized_transactions WHERE id = ?") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    // MARK: - Bills

    func fetchBills(unpaidOnly: Bool = false) throws -> [BillRow] {
        let filter = unpaidOnly ? "WHERE b.status = 'unpaid'" : ""
        let sql = """
            SELECT b.id,
                   CASE WHEN b.vendor_id IS NOT NULL THEN COALESCE(v.name, b.vendor_name_override)
                        ELSE b.vendor_name_override END,
                   b.bill_date, b.due_date, b.amount,
                   COALESCE(a.name, ''), COALESCE(b.job_id, 0), COALESCE(j.name, ''),
                   b.memo, b.status, b.check_number
            FROM bills b
            LEFT JOIN vendors v ON b.vendor_id = v.id
            LEFT JOIN gl_accounts a ON b.account_id = a.id
            LEFT JOIN jobs j ON b.job_id = j.id
            \(filter)
            ORDER BY b.due_date, b.id
            """
        var rows: [BillRow] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(BillRow(
                    id: sqlite3_column_int64(stmt, 0),
                    vendorName: columnText(stmt, 1),
                    billDate: columnText(stmt, 2),
                    dueDate: columnText(stmt, 3),
                    amount: sqlite3_column_double(stmt, 4),
                    accountName: columnText(stmt, 5),
                    jobID: sqlite3_column_int64(stmt, 6),
                    jobName: columnText(stmt, 7),
                    memo: columnText(stmt, 8),
                    status: columnText(stmt, 9),
                    checkNumber: columnText(stmt, 10)
                ))
            }
        }
        return rows
    }

    @discardableResult
    func insertBill(vendorNameOverride: String, vendorID: Int64?, billDate: String,
                    dueDate: String, amount: Double, accountID: Int64?, jobID: Int64? = nil, memo: String) throws -> Int64 {
        let sql = """
            INSERT INTO bills(vendor_id, vendor_name_override, bill_date, due_date, amount, account_id, job_id, memo)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { stmt in
            if let vid = vendorID { sqlite3_bind_int64(stmt, 1, vid) } else { sqlite3_bind_null(stmt, 1) }
            bindText(stmt: stmt, index: 2, value: vendorNameOverride)
            bindText(stmt: stmt, index: 3, value: billDate)
            bindText(stmt: stmt, index: 4, value: dueDate)
            sqlite3_bind_double(stmt, 5, amount)
            if let aid = accountID { sqlite3_bind_int64(stmt, 6, aid) } else { sqlite3_bind_null(stmt, 6) }
            if let jid = jobID { sqlite3_bind_int64(stmt, 7, jid) } else { sqlite3_bind_null(stmt, 7) }
            bindText(stmt: stmt, index: 8, value: memo)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        let billID = sqlite3_last_insert_rowid(db)
        try? repostBill(billID)
        return billID
    }

    func fetchBillPayments(billID: Int64) throws -> [BillPaymentRow] {
        let sql = """
            SELECT bp.id, bp.bill_id, bp.payment_date, bp.amount, bp.payment_method,
                   COALESCE(a.name, ''), bp.check_number, bp.memo
            FROM bill_payments bp
            LEFT JOIN gl_accounts a ON bp.payment_account_id = a.id
            WHERE bp.bill_id = ?
            ORDER BY bp.payment_date DESC, bp.id DESC
            """
        var rows: [BillPaymentRow] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, billID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(BillPaymentRow(
                    id: sqlite3_column_int64(stmt, 0),
                    billID: sqlite3_column_int64(stmt, 1),
                    paymentDate: columnText(stmt, 2),
                    amount: sqlite3_column_double(stmt, 3),
                    paymentMethod: columnText(stmt, 4),
                    paymentAccountName: columnText(stmt, 5),
                    checkNumber: columnText(stmt, 6),
                    memo: columnText(stmt, 7)
                ))
            }
        }
        return rows
    }

    func recordBillPayments(
        billIDs: [Int64],
        paymentDate: String,
        paymentAccountID: Int64?,
        paymentMethod: String,
        startingCheckNumber: String,
        memo: String
    ) throws {
        let uniqueBillIDs = Array(Set(billIDs)).sorted()
        guard !uniqueBillIDs.isEmpty else {
            throw DBError.stepFailed("Choose at least one bill to pay.")
        }

        let normalizedMethod = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Check" : paymentMethod
        let baseCheckNumber = startingCheckNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        var nextCheck = Int(baseCheckNumber)
        var createdExpenseIDs: [Int64] = []   // the bookkeeping "Bill payment" rows to post live

        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for billID in uniqueBillIDs {
                var amount = 0.0
                var vendorID: Int64?
                var vendorNameOverride = ""
                var accountID: Int64?
                var jobID: Int64?
                var billMemo = ""
                try withStatement(
                    """
                    SELECT amount,
                           vendor_id,
                           vendor_name_override,
                           account_id,
                           job_id,
                           memo
                    FROM bills
                    WHERE id = ? AND status = 'unpaid'
                    LIMIT 1
                    """
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, billID)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        amount = sqlite3_column_double(stmt, 0)
                        if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                            vendorID = sqlite3_column_int64(stmt, 1)
                        }
                        vendorNameOverride = columnText(stmt, 2)
                        if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                            accountID = sqlite3_column_int64(stmt, 3)
                        }
                        if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                            jobID = sqlite3_column_int64(stmt, 4)
                        }
                        billMemo = columnText(stmt, 5)
                    } else {
                        throw DBError.stepFailed("One or more selected bills are no longer unpaid.")
                    }
                }

                let assignedCheckNumber: String
                if normalizedMethod.caseInsensitiveCompare("Check") == .orderedSame {
                    if let currentCheck = nextCheck {
                        assignedCheckNumber = String(currentCheck)
                        nextCheck = currentCheck + 1
                    } else {
                        assignedCheckNumber = baseCheckNumber
                    }
                } else {
                    assignedCheckNumber = ""
                }

                try withStatement(
                    """
                    INSERT INTO bill_payments(bill_id, payment_date, amount, payment_account_id, payment_method, check_number, memo, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, billID)
                    bindText(stmt: stmt, index: 2, value: paymentDate)
                    sqlite3_bind_double(stmt, 3, amount)
                    if let paymentAccountID {
                        sqlite3_bind_int64(stmt, 4, paymentAccountID)
                    } else {
                        sqlite3_bind_null(stmt, 4)
                    }
                    bindText(stmt: stmt, index: 5, value: normalizedMethod)
                    bindText(stmt: stmt, index: 6, value: assignedCheckNumber)
                    bindText(stmt: stmt, index: 7, value: memo)
                    bindText(stmt: stmt, index: 8, value: isoNow())
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }

                try withStatement(
                    "UPDATE bills SET status='paid', paid_date=?, check_number=? WHERE id=?"
                ) { stmt in
                    bindText(stmt: stmt, index: 1, value: paymentDate)
                    bindText(stmt: stmt, index: 2, value: assignedCheckNumber)
                    sqlite3_bind_int64(stmt, 3, billID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }

                let registerMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Bill payment\(billMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ": \(billMemo)")"
                    : memo
                try withStatement(
                    """
                    INSERT INTO expenses(
                        vendor_id,
                        vendor_name_override,
                        expense_date,
                        amount,
                        account_id,
                        payment_account_id,
                        check_number,
                        memo,
                        job_id,
                        created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                ) { stmt in
                    if let vendorID {
                        sqlite3_bind_int64(stmt, 1, vendorID)
                    } else {
                        sqlite3_bind_null(stmt, 1)
                    }
                    bindText(stmt: stmt, index: 2, value: vendorNameOverride)
                    bindText(stmt: stmt, index: 3, value: paymentDate)
                    sqlite3_bind_double(stmt, 4, amount)
                    if let accountID {
                        sqlite3_bind_int64(stmt, 5, accountID)
                    } else {
                        sqlite3_bind_null(stmt, 5)
                    }
                    if let paymentAccountID {
                        sqlite3_bind_int64(stmt, 6, paymentAccountID)
                    } else {
                        sqlite3_bind_null(stmt, 6)
                    }
                    bindText(stmt: stmt, index: 7, value: assignedCheckNumber)
                    bindText(stmt: stmt, index: 8, value: registerMemo)
                    if let jobID {
                        sqlite3_bind_int64(stmt, 9, jobID)
                    } else {
                        sqlite3_bind_null(stmt, 9)
                    }
                    bindText(stmt: stmt, index: 10, value: isoNow())
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
                createdExpenseIDs.append(sqlite3_last_insert_rowid(db))
            }

            try exec("COMMIT;")
            // Post each bill-payment expense (it settles Accounts Payable). The bills' own
            // entries are unchanged, so they don't need reposting.
            for expenseID in createdExpenseIDs { try? repostExpense(expenseID) }
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func markBillPaid(id: Int64, paidDate: String, checkNumber: String) throws {
        try recordBillPayments(
            billIDs: [id],
            paymentDate: paidDate,
            paymentAccountID: nil,
            paymentMethod: checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : "Check",
            startingCheckNumber: checkNumber,
            memo: ""
        )
    }

    func deleteBill(id: Int64) throws {
        let sql = "DELETE FROM bills WHERE id=?"
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
        try? repostBill(id)   // row is gone → clears its ledger lines
    }

    // MARK: - Backup

    func exportBackup(to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: databaseURL, to: destinationURL)
    }

    // MARK: - V4 Migration (Company Info)

    func migrateV4() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS company_info (
                id INTEGER PRIMARY KEY DEFAULT 1,
                name TEXT NOT NULL DEFAULT 'Your Company Name',
                phone TEXT NOT NULL DEFAULT '',
                address1 TEXT NOT NULL DEFAULT '',
                city_state_zip TEXT NOT NULL DEFAULT '',
                email TEXT NOT NULL DEFAULT '',
                license_number TEXT NOT NULL DEFAULT '',
                payment_terms TEXT NOT NULL DEFAULT 'Net 30',
                invoice_footer TEXT NOT NULL DEFAULT 'Thank you for your business.'
            );
            """)
        // Seed a default row if none exists
        try exec("""
            INSERT OR IGNORE INTO company_info (id) VALUES (1);
            """)
    }

    func migrateV5() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS customer_credits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                customer_id INTEGER NOT NULL REFERENCES customers(id),
                credit_date TEXT NOT NULL,
                reference TEXT NOT NULL DEFAULT '',
                credit_type TEXT NOT NULL DEFAULT 'credit',
                amount REAL NOT NULL DEFAULT 0,
                remaining_amount REAL NOT NULL DEFAULT 0,
                memo TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_customer_credits_customer_date
                ON customer_credits(customer_id, credit_date, id);
            """)
    }

    func migrateV6() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS estimates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                estimate_number TEXT NOT NULL UNIQUE,
                customer_id INTEGER NOT NULL REFERENCES customers(id),
                issue_date TEXT NOT NULL,
                valid_until TEXT NOT NULL DEFAULT '',
                memo TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'draft',
                total REAL NOT NULL DEFAULT 0,
                linked_invoice_id INTEGER REFERENCES native_invoices(id),
                created_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS estimate_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                estimate_id INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
                description TEXT NOT NULL DEFAULT '',
                quantity REAL NOT NULL DEFAULT 1,
                rate REAL NOT NULL DEFAULT 0,
                amount REAL NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_estimates_customer_date
                ON estimates(customer_id, issue_date, id);
            """)
    }

    func migrateV7() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS historical_1099_totals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tax_year INTEGER NOT NULL,
                vendor_id INTEGER REFERENCES vendors(id) ON DELETE SET NULL,
                vendor_name TEXT NOT NULL DEFAULT '',
                ein TEXT NOT NULL DEFAULT '',
                total_paid REAL NOT NULL DEFAULT 0,
                source_name TEXT NOT NULL DEFAULT '',
                source_path TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT '',
                UNIQUE(tax_year, vendor_name)
            );

            CREATE INDEX IF NOT EXISTS idx_historical_1099_year_vendor
                ON historical_1099_totals(tax_year, vendor_name);
            """)
    }

    func migrateV8() throws {
        sqlite3_exec(db, "ALTER TABLE customers ADD COLUMN primary_contact TEXT NOT NULL DEFAULT ''", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE vendors ADD COLUMN primary_contact TEXT NOT NULL DEFAULT ''", nil, nil, nil)
    }

    func migrateV9() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS historical_pl_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                report_year INTEGER NOT NULL,
                section TEXT NOT NULL,
                account_name TEXT NOT NULL,
                total REAL NOT NULL DEFAULT 0,
                source_name TEXT NOT NULL DEFAULT '',
                source_path TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT '',
                UNIQUE(report_year, section, account_name)
            );

            CREATE INDEX IF NOT EXISTS idx_historical_pl_year_section
                ON historical_pl_lines(report_year, section, account_name);
            """)
    }

    func migrateV10() throws {
        sqlite3_exec(db, "ALTER TABLE vendors ADD COLUMN is_internal_self INTEGER NOT NULL DEFAULT 0", nil, nil, nil)

        let companyPhone = (try? fetchCompanyInfo().phone.filter(\.isNumber)) ?? ""
        guard !companyPhone.isEmpty else { return }

        let sql = """
            UPDATE vendors
            SET is_internal_self = 1
            WHERE is_internal_self = 0
              AND replace(replace(replace(replace(replace(phone, '-', ''), '(', ''), ')', ''), ' ', ''), '+', '') = ?
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: companyPhone)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    func migrateV11() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS payment_terms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                refnum TEXT NOT NULL DEFAULT '',
                due_days INTEGER NOT NULL DEFAULT 0,
                min_days INTEGER NOT NULL DEFAULT 0,
                discount_percent REAL NOT NULL DEFAULT 0,
                discount_days INTEGER NOT NULL DEFAULT 0,
                terms_type TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS payment_methods (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                refnum TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT ''
            );
            """)
    }

    func migrateV12() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS historical_trial_balance_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                as_of_label TEXT NOT NULL DEFAULT '',
                account_name TEXT NOT NULL,
                debit REAL NOT NULL DEFAULT 0,
                credit REAL NOT NULL DEFAULT 0,
                source_name TEXT NOT NULL DEFAULT '',
                source_path TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT '',
                UNIQUE(as_of_label, account_name)
            );

            CREATE INDEX IF NOT EXISTS idx_historical_trial_balance_label
                ON historical_trial_balance_lines(as_of_label, account_name);
            """)
    }

    func migrateV13() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS historical_cash_flow_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                as_of_label TEXT NOT NULL DEFAULT '',
                section_name TEXT NOT NULL,
                section_sort INTEGER NOT NULL DEFAULT 0,
                line_label TEXT NOT NULL,
                line_sort INTEGER NOT NULL DEFAULT 0,
                total REAL NOT NULL DEFAULT 0,
                source_name TEXT NOT NULL DEFAULT '',
                source_path TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT '',
                UNIQUE(as_of_label, section_name, line_label)
            );

            CREATE INDEX IF NOT EXISTS idx_historical_cash_flow_label
                ON historical_cash_flow_lines(as_of_label, section_sort, line_sort);
            """)
    }

    func migrateV14() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS historical_sales_by_item_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                period_label TEXT NOT NULL DEFAULT '',
                section_name TEXT NOT NULL,
                section_sort INTEGER NOT NULL DEFAULT 0,
                item_name TEXT NOT NULL,
                line_sort INTEGER NOT NULL DEFAULT 0,
                quantity REAL NOT NULL DEFAULT 0,
                amount REAL NOT NULL DEFAULT 0,
                percent_of_sales REAL NOT NULL DEFAULT 0,
                average_price REAL NOT NULL DEFAULT 0,
                is_subtotal INTEGER NOT NULL DEFAULT 0,
                source_name TEXT NOT NULL DEFAULT '',
                source_path TEXT NOT NULL DEFAULT '',
                imported_at TEXT NOT NULL DEFAULT '',
                UNIQUE(period_label, section_name, item_name, is_subtotal)
            );

            CREATE INDEX IF NOT EXISTS idx_historical_sales_by_item_period
                ON historical_sales_by_item_lines(period_label, section_sort, line_sort);
            """)
    }

    func migrateV15() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS estimate_invoice_links (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                estimate_id INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
                invoice_id INTEGER NOT NULL REFERENCES native_invoices(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL DEFAULT '',
                mode TEXT NOT NULL DEFAULT 'full',
                percent_value REAL NOT NULL DEFAULT 100,
                source_note TEXT NOT NULL DEFAULT '',
                UNIQUE(estimate_id, invoice_id)
            );

            INSERT OR IGNORE INTO estimate_invoice_links(estimate_id, invoice_id, created_at, mode, percent_value)
            SELECT id, linked_invoice_id, COALESCE(updated_at, created_at, ''), 'full', 100
            FROM estimates
            WHERE COALESCE(linked_invoice_id, 0) != 0;
            """)
    }

    func migrateV16() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS payment_applications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                payment_id INTEGER NOT NULL REFERENCES payments_received(id) ON DELETE CASCADE,
                invoice_id INTEGER NOT NULL REFERENCES native_invoices(id) ON DELETE CASCADE,
                applied_amount REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT '',
                UNIQUE(payment_id, invoice_id)
            );

            CREATE INDEX IF NOT EXISTS idx_payment_applications_invoice
                ON payment_applications(invoice_id, payment_id);

            INSERT OR IGNORE INTO payment_applications(payment_id, invoice_id, applied_amount, created_at)
            SELECT pr.id, pr.invoice_id, pr.amount, COALESCE(pr.created_at, '')
            FROM payments_received pr
            WHERE COALESCE(pr.invoice_id, 0) != 0;

            CREATE TABLE IF NOT EXISTS credit_applications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                customer_credit_id INTEGER NOT NULL REFERENCES customer_credits(id) ON DELETE CASCADE,
                invoice_id INTEGER NOT NULL REFERENCES native_invoices(id) ON DELETE CASCADE,
                payment_id INTEGER REFERENCES payments_received(id) ON DELETE SET NULL,
                applied_date TEXT NOT NULL DEFAULT '',
                amount REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_credit_applications_invoice
                ON credit_applications(invoice_id, applied_date, id);
            """)
    }

    func migrateV17() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS deposit_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                deposit_date TEXT NOT NULL,
                account_id INTEGER NOT NULL REFERENCES gl_accounts(id),
                reference TEXT NOT NULL DEFAULT '',
                memo TEXT NOT NULL DEFAULT '',
                total_amount REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS deposit_record_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                deposit_id INTEGER NOT NULL REFERENCES deposit_records(id) ON DELETE CASCADE,
                payment_id INTEGER NOT NULL REFERENCES payments_received(id) ON DELETE CASCADE,
                amount REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT '',
                UNIQUE(payment_id)
            );

            CREATE INDEX IF NOT EXISTS idx_deposit_record_lines_deposit
                ON deposit_record_lines(deposit_id, payment_id);

            CREATE TABLE IF NOT EXISTS bill_payments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
                payment_date TEXT NOT NULL,
                amount REAL NOT NULL DEFAULT 0,
                payment_account_id INTEGER REFERENCES gl_accounts(id),
                payment_method TEXT NOT NULL DEFAULT 'Check',
                check_number TEXT NOT NULL DEFAULT '',
                memo TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_bill_payments_bill
                ON bill_payments(bill_id, payment_date, id);

            """)
    }

    func migrateV18() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                site_address TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_jobs_customer
                ON jobs(customer_id, is_active, name);
            """)

        sqlite3_exec(db, "ALTER TABLE estimates ADD COLUMN job_id INTEGER REFERENCES jobs(id)", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE native_invoices ADD COLUMN job_id INTEGER REFERENCES jobs(id)", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE expenses ADD COLUMN job_id INTEGER REFERENCES jobs(id)", nil, nil, nil)

        try exec("""
            CREATE INDEX IF NOT EXISTS idx_estimates_job
                ON estimates(job_id, issue_date, id);
            CREATE INDEX IF NOT EXISTS idx_native_invoices_job
                ON native_invoices(job_id, issue_date, id);
            CREATE INDEX IF NOT EXISTS idx_expenses_job
                ON expenses(job_id, expense_date, id);
            """)
    }

    func migrateV19() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS memorized_transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                payload_json TEXT NOT NULL DEFAULT '',
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT '',
                UNIQUE(type, name)
            );

            CREATE INDEX IF NOT EXISTS idx_memorized_transactions_type
                ON memorized_transactions(type, is_active, name);
            """)
    }

    func migrateV20() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS expense_check_item_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
                sort_order INTEGER NOT NULL DEFAULT 0,
                service_item_id INTEGER REFERENCES service_items(id) ON DELETE SET NULL,
                item_name TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                quantity REAL NOT NULL DEFAULT 0,
                rate REAL NOT NULL DEFAULT 0,
                amount REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_expense_check_item_lines_expense
                ON expense_check_item_lines(expense_id, sort_order, id);
            """)
    }

    func migrateV21() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS sales_receipts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                receipt_number TEXT NOT NULL,
                customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
                job_id INTEGER REFERENCES jobs(id) ON DELETE SET NULL,
                receipt_date TEXT NOT NULL,
                payment_method_id INTEGER REFERENCES payment_methods(id) ON DELETE SET NULL,
                payment_id INTEGER REFERENCES payments_received(id) ON DELETE SET NULL,
                memo TEXT NOT NULL DEFAULT '',
                total REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT ''
            );

            CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_receipts_number
                ON sales_receipts(receipt_number);

            CREATE INDEX IF NOT EXISTS idx_sales_receipts_customer_date
                ON sales_receipts(customer_id, receipt_date, id);

            CREATE INDEX IF NOT EXISTS idx_sales_receipts_job_date
                ON sales_receipts(job_id, receipt_date, id);

            CREATE TABLE IF NOT EXISTS sales_receipt_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                receipt_id INTEGER NOT NULL REFERENCES sales_receipts(id) ON DELETE CASCADE,
                description TEXT NOT NULL DEFAULT '',
                quantity REAL NOT NULL DEFAULT 1,
                rate REAL NOT NULL DEFAULT 0,
                amount REAL NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_sales_receipt_lines_receipt
                ON sales_receipt_lines(receipt_id, id);
            """)
    }

    func migrateV22() throws {
        // Per-document customer-name override so user can pick a customer
        // and edit the name that prints, or save a doc with a typed-but-not-yet-created
        // customer name. Mirrors expenses.vendor_name_override.
        sqlite3_exec(db, "ALTER TABLE estimates ADD COLUMN customer_name_override TEXT NOT NULL DEFAULT ''", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE native_invoices ADD COLUMN customer_name_override TEXT NOT NULL DEFAULT ''", nil, nil, nil)
    }

    func migrateV23() throws {
        // Vendor bills can belong to a customer job, then Pay Bills carries
        // that job into the check/register expense for profitability reports.
        sqlite3_exec(db, "ALTER TABLE bills ADD COLUMN job_id INTEGER REFERENCES jobs(id)", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_bills_job ON bills(job_id, bill_date, id)", nil, nil, nil)
    }

    func migrateV24() throws {
        sqlite3_exec(db, "ALTER TABLE memorized_transactions ADD COLUMN reminder_frequency TEXT NOT NULL DEFAULT 'none'", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE memorized_transactions ADD COLUMN next_due_date TEXT NOT NULL DEFAULT ''", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE memorized_transactions ADD COLUMN last_used_at TEXT NOT NULL DEFAULT ''", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE memorized_transactions ADD COLUMN notes TEXT NOT NULL DEFAULT ''", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_memorized_transactions_due ON memorized_transactions(is_active, next_due_date, type)", nil, nil, nil)
    }

    func migrateV25() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS estimate_revision_links (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_estimate_id INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
                child_estimate_id INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL DEFAULT '',
                relationship TEXT NOT NULL DEFAULT 'change_order',
                source_note TEXT NOT NULL DEFAULT '',
                UNIQUE(source_estimate_id, child_estimate_id)
            );

            CREATE INDEX IF NOT EXISTS idx_estimate_revision_source
            ON estimate_revision_links(source_estimate_id, child_estimate_id);

            CREATE INDEX IF NOT EXISTS idx_estimate_revision_child
            ON estimate_revision_links(child_estimate_id, source_estimate_id);
            """)
    }

    // Bank reconciliation (BNK-004): reconciliation headers + cleared/reconciled flags
    // on every bank-affecting table. Additive + idempotent.
    func migrateV26() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS reconciliations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES gl_accounts(id),
                statement_date TEXT NOT NULL,
                beginning_balance REAL NOT NULL DEFAULT 0,
                ending_balance REAL NOT NULL DEFAULT 0,
                cleared_total REAL NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'in_progress',
                created_at TEXT NOT NULL DEFAULT '',
                reconciled_at TEXT NOT NULL DEFAULT ''
            );

            CREATE INDEX IF NOT EXISTS idx_reconciliations_account
            ON reconciliations(account_id, statement_date);
            """)
        // Additive cleared/reconciled flags. ALTER fails harmlessly if the column already exists.
        sqlite3_exec(db, "ALTER TABLE expenses ADD COLUMN cleared INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE expenses ADD COLUMN reconciliation_id INTEGER", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE bill_payments ADD COLUMN cleared INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE bill_payments ADD COLUMN reconciliation_id INTEGER", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE deposit_records ADD COLUMN cleared INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE deposit_records ADD COLUMN reconciliation_id INTEGER", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE transactions ADD COLUMN cleared INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE transactions ADD COLUMN reconciliation_id INTEGER", nil, nil, nil)
    }

    // MARK: - Bank Reconciliation (BNK-004)

    /// Bank accounts that actually carry register activity — i.e. accounts used
    /// as a payment account on an expense, a deposit account, or named on an
    /// imported transaction. These are the accounts worth offering to reconcile.
    func fetchReconcilableAccounts() throws -> [ReconcileAccount] {
        let sql = """
            SELECT a.id, a.name, a.number
            FROM gl_accounts a
            WHERE a.id IN (SELECT DISTINCT payment_account_id FROM expenses WHERE payment_account_id IS NOT NULL)
               OR a.id IN (SELECT DISTINCT account_id FROM deposit_records WHERE account_id IS NOT NULL)
               OR a.name IN (SELECT DISTINCT account FROM transactions WHERE account IS NOT NULL AND account <> '')
            ORDER BY a.name
            """
        var rows: [ReconcileAccount] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ReconcileAccount(
                    id: sqlite3_column_int64(stmt, 0),
                    name: columnText(stmt, 1),
                    number: columnText(stmt, 2)
                ))
            }
        }
        return rows
    }

    /// Beginning balance for a new reconciliation of `accountID` = the most
    /// recently *reconciled* statement's ending balance, or 0 if none exists.
    func reconciliationBeginningBalance(accountID: Int64) throws -> Double {
        let sql = """
            SELECT ending_balance
            FROM reconciliations
            WHERE account_id = ? AND status = 'reconciled'
            ORDER BY statement_date DESC, id DESC
            LIMIT 1
            """
        var balance = 0.0
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, accountID)
            if sqlite3_step(stmt) == SQLITE_ROW {
                balance = sqlite3_column_double(stmt, 0)
            }
        }
        return balance
    }

    /// All register lines for `accountID` dated on/through `throughDate` that are
    /// not yet tied to a committed reconciliation. Money out (expenses) comes
    /// back negative, deposits positive; legacy `transactions.amount` is taken
    /// as already bank-signed.
    ///
    /// `bill_payments` is intentionally excluded: `recordBillPayments` mirrors
    /// every bill payment into `expenses`, so `expenses` is the authoritative
    /// money-out register and counting both would double-count.
    /// Working set for the reconcile sheet: every register line for `accountID`
    /// dated on/through `throughDate` that is either not yet reconciled, or
    /// already tied to `includeReconciliationID` (a resumed in-progress
    /// reconciliation — those rows come back pre-cleared so the sheet can
    /// re-check them). Passing nil for `includeReconciliationID` yields only the
    /// unreconciled lines. `reconciliation_id` is never 0 (AUTOINCREMENT starts
    /// at 1), so binding 0 for the nil case matches the `IS NULL` rows only.
    func fetchReconcileItems(
        accountID: Int64,
        accountName: String,
        throughDate: String,
        includeReconciliationID: Int64? = nil
    ) throws -> [ReconcileItem] {
        let includeID = includeReconciliationID ?? 0
        let sql = """
            SELECT kind, sid, dt, payee, ref, memo, signed_amount, cleared, recon_id FROM (
                SELECT 'expense' AS kind, e.id AS sid, e.expense_date AS dt,
                       CASE WHEN e.vendor_id IS NOT NULL THEN COALESCE(v.name, e.vendor_name_override)
                            ELSE e.vendor_name_override END AS payee,
                       e.check_number AS ref, e.memo AS memo,
                       -e.amount AS signed_amount, COALESCE(e.cleared, 0) AS cleared,
                       e.reconciliation_id AS recon_id
                FROM expenses e
                LEFT JOIN vendors v ON e.vendor_id = v.id
                WHERE e.payment_account_id = ? AND e.expense_date <= ?
                  AND (e.reconciliation_id IS NULL OR e.reconciliation_id = ?)
                UNION ALL
                SELECT 'deposit', d.id, d.deposit_date, '', d.reference, d.memo,
                       d.total_amount, COALESCE(d.cleared, 0), d.reconciliation_id
                FROM deposit_records d
                WHERE d.account_id = ? AND d.deposit_date <= ?
                  AND (d.reconciliation_id IS NULL OR d.reconciliation_id = ?)
                UNION ALL
                SELECT 'transaction', t.id, COALESCE(t.txn_date, ''), COALESCE(t.payee, ''), '', COALESCE(t.memo, ''),
                       t.amount, COALESCE(t.cleared, 0), t.reconciliation_id
                FROM transactions t
                WHERE t.account = ? AND COALESCE(t.txn_date, '') <= ?
                  AND (t.reconciliation_id IS NULL OR t.reconciliation_id = ?)
            )
            ORDER BY dt, kind, sid
            """
        var items: [ReconcileItem] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, accountID)
            bindText(stmt: stmt, index: 2, value: throughDate)
            sqlite3_bind_int64(stmt, 3, includeID)
            sqlite3_bind_int64(stmt, 4, accountID)
            bindText(stmt: stmt, index: 5, value: throughDate)
            sqlite3_bind_int64(stmt, 6, includeID)
            bindText(stmt: stmt, index: 7, value: accountName)
            bindText(stmt: stmt, index: 8, value: throughDate)
            sqlite3_bind_int64(stmt, 9, includeID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let kind = ReconcileSourceKind(rawValue: columnText(stmt, 0)) else { continue }
                let reconID: Int64? = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 8)
                items.append(ReconcileItem(
                    sourceKind: kind,
                    sourceID: sqlite3_column_int64(stmt, 1),
                    date: columnText(stmt, 2),
                    payee: columnText(stmt, 3),
                    reference: columnText(stmt, 4),
                    memo: columnText(stmt, 5),
                    signedAmount: sqlite3_column_double(stmt, 6),
                    cleared: sqlite3_column_int64(stmt, 7) != 0,
                    reconciliationID: reconID
                ))
            }
        }
        return items
    }

    /// The single open (in-progress) reconciliation for an account, if one was
    /// left unfinished. Used to resume rather than start over.
    func fetchInProgressReconciliation(accountID: Int64) throws -> Reconciliation? {
        let all = try fetchReconciliations(accountID: accountID)
        return all.first { $0.status == "in_progress" }
    }

    /// Save a reconciliation without finishing it (status `in_progress`) so Dad
    /// can step away and resume. Returns the header (with its id) so the sheet
    /// can keep editing the same row.
    @discardableResult
    func saveReconciliationProgress(
        existingID: Int64?,
        accountID: Int64,
        statementDate: String,
        beginningBalance: Double,
        endingBalance: Double,
        clearedItems: [ReconcileItem]
    ) throws -> Reconciliation {
        try upsertReconciliation(
            existingID: existingID,
            accountID: accountID,
            statementDate: statementDate,
            beginningBalance: beginningBalance,
            endingBalance: endingBalance,
            clearedItems: clearedItems,
            status: "in_progress"
        )
    }

    /// Commit a reconciliation (status `reconciled`). `existingID` promotes a
    /// resumed in-progress row; nil starts a fresh one. `clearedTotal` stores
    /// the net change the cleared items apply to the bank balance.
    @discardableResult
    func commitReconciliation(
        existingID: Int64? = nil,
        accountID: Int64,
        statementDate: String,
        beginningBalance: Double,
        endingBalance: Double,
        clearedItems: [ReconcileItem]
    ) throws -> Reconciliation {
        try upsertReconciliation(
            existingID: existingID,
            accountID: accountID,
            statementDate: statementDate,
            beginningBalance: beginningBalance,
            endingBalance: endingBalance,
            clearedItems: clearedItems,
            status: "reconciled"
        )
    }

    /// Shared write path for save-in-progress and commit. Atomic: upsert the
    /// header, release every item currently tied to it, then re-tie exactly the
    /// chosen cleared items. Release-then-tie makes repeated saves idempotent
    /// and correctly drops items the user un-checked.
    private func upsertReconciliation(
        existingID: Int64?,
        accountID: Int64,
        statementDate: String,
        beginningBalance: Double,
        endingBalance: Double,
        clearedItems: [ReconcileItem],
        status: String
    ) throws -> Reconciliation {
        let clearedTotal = clearedItems.reduce(0) { $0 + $1.signedAmount }
        let timestamp = isoNow()
        let reconciledAt = status == "reconciled" ? timestamp : ""

        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            var reconciliationID: Int64
            var createdAt = timestamp
            if let existingID {
                try withStatement(
                    """
                    UPDATE reconciliations
                    SET statement_date = ?, beginning_balance = ?, ending_balance = ?,
                        cleared_total = ?, status = ?, reconciled_at = ?
                    WHERE id = ?
                    """
                ) { stmt in
                    bindText(stmt: stmt, index: 1, value: statementDate)
                    sqlite3_bind_double(stmt, 2, beginningBalance)
                    sqlite3_bind_double(stmt, 3, endingBalance)
                    sqlite3_bind_double(stmt, 4, clearedTotal)
                    bindText(stmt: stmt, index: 5, value: status)
                    bindText(stmt: stmt, index: 6, value: reconciledAt)
                    sqlite3_bind_int64(stmt, 7, existingID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
                reconciliationID = existingID
                // Preserve the original created_at for the returned model.
                try withStatement("SELECT created_at FROM reconciliations WHERE id = ?") { stmt in
                    sqlite3_bind_int64(stmt, 1, existingID)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        createdAt = columnText(stmt, 0)
                    }
                }
            } else {
                try withStatement(
                    """
                    INSERT INTO reconciliations(
                        account_id, statement_date, beginning_balance, ending_balance,
                        cleared_total, status, created_at, reconciled_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, accountID)
                    bindText(stmt: stmt, index: 2, value: statementDate)
                    sqlite3_bind_double(stmt, 3, beginningBalance)
                    sqlite3_bind_double(stmt, 4, endingBalance)
                    sqlite3_bind_double(stmt, 5, clearedTotal)
                    bindText(stmt: stmt, index: 6, value: status)
                    bindText(stmt: stmt, index: 7, value: timestamp)
                    bindText(stmt: stmt, index: 8, value: reconciledAt)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
                reconciliationID = sqlite3_last_insert_rowid(db)
            }

            // Release everything previously tied to this reconciliation.
            for table in ["expenses", "deposit_records", "transactions"] {
                try withStatement(
                    "UPDATE \(table) SET cleared = 0, reconciliation_id = NULL WHERE reconciliation_id = ?"
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, reconciliationID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            // Re-tie exactly the chosen items. tableName is enum-derived, never user input.
            for item in clearedItems {
                let update = "UPDATE \(item.sourceKind.tableName) SET cleared = 1, reconciliation_id = ? WHERE id = ?"
                try withStatement(update) { stmt in
                    sqlite3_bind_int64(stmt, 1, reconciliationID)
                    sqlite3_bind_int64(stmt, 2, item.sourceID)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }

            try exec("COMMIT;")

            return Reconciliation(
                id: reconciliationID,
                accountID: accountID,
                accountName: "",
                statementDate: statementDate,
                beginningBalance: beginningBalance,
                endingBalance: endingBalance,
                clearedTotal: clearedTotal,
                status: status,
                createdAt: createdAt,
                reconciledAt: reconciledAt
            )
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    /// Completed/in-progress reconciliations for an account, newest first.
    func fetchReconciliations(accountID: Int64) throws -> [Reconciliation] {
        let sql = """
            SELECT r.id, r.account_id, COALESCE(a.name, ''), r.statement_date,
                   r.beginning_balance, r.ending_balance, r.cleared_total,
                   r.status, r.created_at, r.reconciled_at
            FROM reconciliations r
            LEFT JOIN gl_accounts a ON r.account_id = a.id
            WHERE r.account_id = ?
            ORDER BY r.statement_date DESC, r.id DESC
            """
        var rows: [Reconciliation] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, accountID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(Reconciliation(
                    id: sqlite3_column_int64(stmt, 0),
                    accountID: sqlite3_column_int64(stmt, 1),
                    accountName: columnText(stmt, 2),
                    statementDate: columnText(stmt, 3),
                    beginningBalance: sqlite3_column_double(stmt, 4),
                    endingBalance: sqlite3_column_double(stmt, 5),
                    clearedTotal: sqlite3_column_double(stmt, 6),
                    status: columnText(stmt, 7),
                    createdAt: columnText(stmt, 8),
                    reconciledAt: columnText(stmt, 9)
                ))
            }
        }
        return rows
    }

    /// The cleared items that belong to a committed reconciliation (for the
    /// reconciliation report). `reconciliation_id` is globally unique across the
    /// source tables, so no account/date filter is needed.
    func fetchReconciledItems(reconciliationID: Int64) throws -> [ReconcileItem] {
        let sql = """
            SELECT kind, sid, dt, payee, ref, memo, signed_amount FROM (
                SELECT 'expense' AS kind, e.id AS sid, e.expense_date AS dt,
                       CASE WHEN e.vendor_id IS NOT NULL THEN COALESCE(v.name, e.vendor_name_override)
                            ELSE e.vendor_name_override END AS payee,
                       e.check_number AS ref, e.memo AS memo, -e.amount AS signed_amount
                FROM expenses e
                LEFT JOIN vendors v ON e.vendor_id = v.id
                WHERE e.reconciliation_id = ?
                UNION ALL
                SELECT 'deposit', d.id, d.deposit_date, '', d.reference, d.memo, d.total_amount
                FROM deposit_records d
                WHERE d.reconciliation_id = ?
                UNION ALL
                SELECT 'transaction', t.id, COALESCE(t.txn_date, ''), COALESCE(t.payee, ''), '',
                       COALESCE(t.memo, ''), t.amount
                FROM transactions t
                WHERE t.reconciliation_id = ?
            )
            ORDER BY dt, kind, sid
            """
        var items: [ReconcileItem] = []
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, reconciliationID)
            sqlite3_bind_int64(stmt, 2, reconciliationID)
            sqlite3_bind_int64(stmt, 3, reconciliationID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let kind = ReconcileSourceKind(rawValue: columnText(stmt, 0)) else { continue }
                items.append(ReconcileItem(
                    sourceKind: kind,
                    sourceID: sqlite3_column_int64(stmt, 1),
                    date: columnText(stmt, 2),
                    payee: columnText(stmt, 3),
                    reference: columnText(stmt, 4),
                    memo: columnText(stmt, 5),
                    signedAmount: sqlite3_column_double(stmt, 6),
                    cleared: true,
                    reconciliationID: reconciliationID
                ))
            }
        }
        return items
    }

    /// Undo a committed reconciliation: clear the header and release its items
    /// back to uncleared. Used by the cutover tool and any "redo last
    /// reconciliation" affordance.
    func deleteReconciliation(id: Int64) throws {
        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for table in ["expenses", "deposit_records", "transactions"] {
                try withStatement(
                    "UPDATE \(table) SET cleared = 0, reconciliation_id = NULL WHERE reconciliation_id = ?"
                ) { stmt in
                    sqlite3_bind_int64(stmt, 1, id)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw DBError.stepFailed(lastErrorMessage)
                    }
                }
            }
            try withStatement("DELETE FROM reconciliations WHERE id = ?") { stmt in
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DBError.stepFailed(lastErrorMessage)
                }
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    /// One-time cutover: create an "opening" reconciliation that clears every
    /// still-unreconciled item dated on/through `throughDate` and sets the
    /// ending balance to Dad's last-known-good statement balance (e.g. from the
    /// old QB "Previous Reconciliation" report). Unlike a normal reconcile this
    /// does NOT require the difference to be zero — it establishes the baseline
    /// so ongoing monthly reconciliations start clean. Reuses the same engine,
    /// so the source/sign rules stay centralized.
    @discardableResult
    func createOpeningReconciliation(accountID: Int64, accountName: String, throughDate: String, statementEndingBalance: Double) throws -> Reconciliation {
        let items = try fetchReconcileItems(accountID: accountID, accountName: accountName, throughDate: throughDate)
        return try commitReconciliation(
            existingID: nil,
            accountID: accountID,
            statementDate: throughDate,
            beginningBalance: 0,
            endingBalance: statementEndingBalance,
            clearedItems: items
        )
    }

    func fetchCompanyInfo() throws -> CompanyInfo {
        let sql = "SELECT name, phone, address1, city_state_zip, email, license_number, payment_terms, invoice_footer FROM company_info WHERE id=1"
        var info = CompanyInfo()
        try withStatement(sql) { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                info.name = columnText(stmt, 0)
                info.phone = columnText(stmt, 1)
                info.address1 = columnText(stmt, 2)
                info.cityStateZip = columnText(stmt, 3)
                info.email = columnText(stmt, 4)
                info.licenseNumber = columnText(stmt, 5)
                info.paymentTerms = columnText(stmt, 6)
                info.invoiceFooter = columnText(stmt, 7)
            }
        }
        return info
    }

    func saveCompanyInfo(_ info: CompanyInfo) throws {
        let sql = """
            INSERT INTO company_info (id, name, phone, address1, city_state_zip, email, license_number, payment_terms, invoice_footer)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name=excluded.name,
                phone=excluded.phone,
                address1=excluded.address1,
                city_state_zip=excluded.city_state_zip,
                email=excluded.email,
                license_number=excluded.license_number,
                payment_terms=excluded.payment_terms,
                invoice_footer=excluded.invoice_footer
            """
        try withStatement(sql) { stmt in
            bindText(stmt: stmt, index: 1, value: info.name)
            bindText(stmt: stmt, index: 2, value: info.phone)
            bindText(stmt: stmt, index: 3, value: info.address1)
            bindText(stmt: stmt, index: 4, value: info.cityStateZip)
            bindText(stmt: stmt, index: 5, value: info.email)
            bindText(stmt: stmt, index: 6, value: info.licenseNumber)
            bindText(stmt: stmt, index: 7, value: info.paymentTerms)
            bindText(stmt: stmt, index: 8, value: info.invoiceFooter)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.stepFailed(lastErrorMessage)
            }
        }
    }

    // MARK: - Double-entry posting layer (ADR-001)

    /// Creates the ledger table. The ledger is *derived* from the operational tables
    /// (see `rebuildJournal`), so it can always be regenerated and never drifts silently.
    func migrateV27() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS journal_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                txn_kind TEXT NOT NULL,
                txn_id INTEGER NOT NULL,
                line_date TEXT NOT NULL DEFAULT '',
                account_id INTEGER NOT NULL REFERENCES gl_accounts(id),
                debit REAL NOT NULL DEFAULT 0,
                credit REAL NOT NULL DEFAULT 0,
                memo TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS idx_journal_lines_txn ON journal_lines(txn_kind, txn_id);
            CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id, line_date);
            """
        )
    }

    /// One side of a journal entry.
    struct JournalPosting {
        let accountID: Int64
        let debit: Double
        let credit: Double
    }

    /// Post a balanced set of journal lines for one operational transaction, replacing any
    /// prior lines for `(kind, txnID)` so posting is idempotent. Throws if unbalanced.
    func postJournalEntry(kind: String, txnID: Int64, date: String,
                          lines: [JournalPosting], memo: String = "") throws {
        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }
        guard abs(totalDebit - totalCredit) < 0.005 else {
            throw DBError.stepFailed("Unbalanced journal entry \(kind)#\(txnID): debit \(totalDebit) != credit \(totalCredit)")
        }
        try withStatement("DELETE FROM journal_lines WHERE txn_kind = ? AND txn_id = ?") { stmt in
            bindText(stmt: stmt, index: 1, value: kind)
            sqlite3_bind_int64(stmt, 2, txnID)
            _ = sqlite3_step(stmt)
        }
        for line in lines where abs(line.debit) > 0.0001 || abs(line.credit) > 0.0001 {
            try withStatement(
                "INSERT INTO journal_lines(txn_kind, txn_id, line_date, account_id, debit, credit, memo, created_at) VALUES (?,?,?,?,?,?,?,?)"
            ) { stmt in
                bindText(stmt: stmt, index: 1, value: kind)
                sqlite3_bind_int64(stmt, 2, txnID)
                bindText(stmt: stmt, index: 3, value: date)
                sqlite3_bind_int64(stmt, 4, line.accountID)
                sqlite3_bind_double(stmt, 5, line.debit)
                sqlite3_bind_double(stmt, 6, line.credit)
                bindText(stmt: stmt, index: 7, value: memo)
                bindText(stmt: stmt, index: 8, value: isoNow())
                if sqlite3_step(stmt) != SQLITE_DONE { throw DBError.stepFailed(lastErrorMessage) }
            }
        }
    }

    private func ledgerAccountID(named name: String) throws -> Int64 {
        var result: Int64?
        try withStatement("SELECT id FROM gl_accounts WHERE LOWER(name) = LOWER(?) ORDER BY id LIMIT 1") { stmt in
            bindText(stmt: stmt, index: 1, value: name)
            if sqlite3_step(stmt) == SQLITE_ROW { result = sqlite3_column_int64(stmt, 0) }
        }
        guard let id = result else { throw DBError.stepFailed("Ledger account '\(name)' not found") }
        return id
    }

    private func defaultIncomeAccountID() throws -> Int64 {
        var result: Int64?
        try withStatement("SELECT id FROM gl_accounts WHERE type = 'income' ORDER BY number, id LIMIT 1") { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW { result = sqlite3_column_int64(stmt, 0) }
        }
        guard let id = result else { throw DBError.stepFailed("No income account is defined") }
        return id
    }

    // MARK: - Per-transaction ledger posting (single source of truth)

    // Each `repost` reads one operational row by id and writes that transaction's balanced
    // journal lines — or clears them when the row is gone or not postable. Both the full
    // `rebuildJournal` and the live write paths call these, so the accrual rules live in
    // exactly one place and the live ledger can never diverge from a rebuild.

    /// Post (or clear) the ledger entry for a single invoice. Matches `rebuildJournal`: an
    /// invoice recognizes income into A/R regardless of status, so a void leaves it in place.
    func repostInvoice(_ id: Int64) throws {
        var date = "", total = 0.0, found = false
        try withStatement("SELECT issue_date, total FROM native_invoices WHERE id = ?") { s in
            sqlite3_bind_int64(s, 1, id)
            if sqlite3_step(s) == SQLITE_ROW { date = columnText(s, 0); total = sqlite3_column_double(s, 1); found = true }
        }
        guard found else { try deleteJournalEntries(kind: "invoice", txnID: id); return }
        let ar = try ledgerAccountID(named: "Accounts Receivable")
        let income = try defaultIncomeAccountID()
        try postJournalEntry(kind: "invoice", txnID: id, date: date,
            lines: [JournalPosting(accountID: ar, debit: total, credit: 0),
                    JournalPosting(accountID: income, debit: 0, credit: total)])
    }

    /// Post (or clear) the ledger entry for a single customer payment. Cash lands in
    /// Undeposited Funds until a deposit moves it, unless it was booked straight to a bank.
    func repostPayment(_ id: Int64) throws {
        var date = "", amount = 0.0, depositAccount: Int64 = 0, hasDepositLine = false, found = false
        try withStatement(
            """
            SELECT p.payment_date, p.amount, COALESCE(p.deposit_account_id, 0),
                   EXISTS(SELECT 1 FROM deposit_record_lines dl WHERE dl.payment_id = p.id)
            FROM payments_received p WHERE p.id = ?
            """
        ) { s in
            sqlite3_bind_int64(s, 1, id)
            if sqlite3_step(s) == SQLITE_ROW {
                date = columnText(s, 0); amount = sqlite3_column_double(s, 1)
                depositAccount = sqlite3_column_int64(s, 2); hasDepositLine = sqlite3_column_int64(s, 3) != 0; found = true
            }
        }
        guard found, amount > 0.0001 else { try deleteJournalEntries(kind: "payment", txnID: id); return }
        let ar = try ledgerAccountID(named: "Accounts Receivable")
        let undeposited = try ledgerAccountID(named: "Undeposited Funds")
        let cash = (hasDepositLine || depositAccount == 0) ? undeposited : depositAccount
        try postJournalEntry(kind: "payment", txnID: id, date: date,
            lines: [JournalPosting(accountID: cash, debit: amount, credit: 0),
                    JournalPosting(accountID: ar, debit: 0, credit: amount)])
    }

    /// Post (or clear) the ledger entry for a single deposit: money moves from Undeposited
    /// Funds into the destination bank account.
    func repostDeposit(_ id: Int64) throws {
        var date = "", total = 0.0, account: Int64 = 0, found = false
        try withStatement("SELECT deposit_date, account_id, total_amount FROM deposit_records WHERE id = ?") { s in
            sqlite3_bind_int64(s, 1, id)
            if sqlite3_step(s) == SQLITE_ROW { date = columnText(s, 0); account = sqlite3_column_int64(s, 1); total = sqlite3_column_double(s, 2); found = true }
        }
        guard found else { try deleteJournalEntries(kind: "deposit", txnID: id); return }
        let undeposited = try ledgerAccountID(named: "Undeposited Funds")
        try postJournalEntry(kind: "deposit", txnID: id, date: date,
            lines: [JournalPosting(accountID: account, debit: total, credit: 0),
                    JournalPosting(accountID: undeposited, debit: 0, credit: total)])
    }

    /// Post (or clear) the ledger entry for a single expense. A bookkeeping "Bill payment"
    /// expense settles Accounts Payable instead of recognizing a second expense.
    func repostExpense(_ id: Int64) throws {
        var date = "", memo = "", amount = 0.0, account: Int64 = 0, payAccount: Int64 = 0, found = false
        try withStatement("SELECT expense_date, amount, COALESCE(account_id, 0), COALESCE(payment_account_id, 0), memo FROM expenses WHERE id = ?") { s in
            sqlite3_bind_int64(s, 1, id)
            if sqlite3_step(s) == SQLITE_ROW {
                date = columnText(s, 0); amount = sqlite3_column_double(s, 1)
                account = sqlite3_column_int64(s, 2); payAccount = sqlite3_column_int64(s, 3); memo = columnText(s, 4); found = true
            }
        }
        guard found, payAccount != 0, account != 0 else { try deleteJournalEntries(kind: "expense", txnID: id); return }
        let debitAccount = memo.hasPrefix("Bill payment") ? try ledgerAccountID(named: "Accounts Payable") : account
        if amount >= 0 {
            try postJournalEntry(kind: "expense", txnID: id, date: date,
                lines: [JournalPosting(accountID: debitAccount, debit: amount, credit: 0),
                        JournalPosting(accountID: payAccount, debit: 0, credit: amount)])
        } else {
            try postJournalEntry(kind: "expense", txnID: id, date: date,
                lines: [JournalPosting(accountID: payAccount, debit: -amount, credit: 0),
                        JournalPosting(accountID: debitAccount, debit: 0, credit: -amount)])
        }
    }

    /// Post (or clear) the ledger entry for a single bill: recognizes expense into Accounts Payable.
    func repostBill(_ id: Int64) throws {
        var date = "", amount = 0.0, account: Int64 = 0, found = false
        try withStatement("SELECT bill_date, amount, COALESCE(account_id, 0) FROM bills WHERE id = ?") { s in
            sqlite3_bind_int64(s, 1, id)
            if sqlite3_step(s) == SQLITE_ROW { date = columnText(s, 0); amount = sqlite3_column_double(s, 1); account = sqlite3_column_int64(s, 2); found = true }
        }
        guard found, account != 0 else { try deleteJournalEntries(kind: "bill", txnID: id); return }
        let ap = try ledgerAccountID(named: "Accounts Payable")
        try postJournalEntry(kind: "bill", txnID: id, date: date,
            lines: [JournalPosting(accountID: account, debit: amount, credit: 0),
                    JournalPosting(accountID: ap, debit: 0, credit: amount)])
    }

    /// Rebuild the entire double-entry ledger from the operational tables — both the
    /// one-time backfill and an always-available consistency tool (the ledger is derived,
    /// so it can never drift silently). Accrual model: invoices recognize income into A/R;
    /// bills recognize expense into A/P; payments and deposits move cash; a bill payment's
    /// bookkeeping `expenses` row (tagged "Bill payment") is treated as an A/P settlement,
    /// not a second expense. Returns the trial-balance totals (debits, credits).
    @discardableResult
    func rebuildJournal() throws -> (debits: Double, credits: Double) {
        // Collect every operational row id, then repost each through the same single-entry
        // helpers the live write paths use — so a rebuild and live posting are identical.
        var invoiceIDs: [Int64] = [], paymentIDs: [Int64] = [], depositIDs: [Int64] = [], expenseIDs: [Int64] = [], billIDs: [Int64] = []
        try withStatement("SELECT id FROM native_invoices") { s in
            while sqlite3_step(s) == SQLITE_ROW { invoiceIDs.append(sqlite3_column_int64(s, 0)) }
        }
        try withStatement("SELECT id FROM payments_received WHERE amount > 0.0001") { s in
            while sqlite3_step(s) == SQLITE_ROW { paymentIDs.append(sqlite3_column_int64(s, 0)) }
        }
        try withStatement("SELECT id FROM deposit_records") { s in
            while sqlite3_step(s) == SQLITE_ROW { depositIDs.append(sqlite3_column_int64(s, 0)) }
        }
        try withStatement("SELECT id FROM expenses") { s in
            while sqlite3_step(s) == SQLITE_ROW { expenseIDs.append(sqlite3_column_int64(s, 0)) }
        }
        try withStatement("SELECT id FROM bills") { s in
            while sqlite3_step(s) == SQLITE_ROW { billIDs.append(sqlite3_column_int64(s, 0)) }
        }

        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            // Regenerate only the derived entries; preserve any non-derived history.
            // Imported QuickBooks transactions ('qb_import') and onboarding opening
            // balances ('opening') are authored once and must survive a rebuild.
            try exec("DELETE FROM journal_lines WHERE txn_kind IN ('invoice','payment','deposit','expense','bill');")
            for id in invoiceIDs { try repostInvoice(id) }
            for id in paymentIDs { try repostPayment(id) }
            for id in depositIDs { try repostDeposit(id) }
            for id in expenseIDs { try repostExpense(id) }
            for id in billIDs { try repostBill(id) }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
        return try trialBalanceTotals()
    }

    /// Delete all ledger lines of a given kind (e.g. clear a prior 'qb_import' before re-importing).
    func deleteJournalEntries(kind: String) throws {
        try withStatement("DELETE FROM journal_lines WHERE txn_kind = ?") { stmt in
            bindText(stmt: stmt, index: 1, value: kind)
            if sqlite3_step(stmt) != SQLITE_DONE { throw DBError.stepFailed(lastErrorMessage) }
        }
    }

    func deleteJournalEntries(kind: String, txnID: Int64) throws {
        try withStatement("DELETE FROM journal_lines WHERE txn_kind = ? AND txn_id = ?") { stmt in
            bindText(stmt: stmt, index: 1, value: kind)
            sqlite3_bind_int64(stmt, 2, txnID)
            if sqlite3_step(stmt) != SQLITE_DONE { throw DBError.stepFailed(lastErrorMessage) }
        }
    }

    /// Total debits and credits across the whole ledger — equal in a valid double-entry set.
    func trialBalanceTotals() throws -> (debits: Double, credits: Double) {
        var d = 0.0, c = 0.0
        try withStatement("SELECT IFNULL(SUM(debit), 0), IFNULL(SUM(credit), 0) FROM journal_lines") { s in
            if sqlite3_step(s) == SQLITE_ROW { d = sqlite3_column_double(s, 0); c = sqlite3_column_double(s, 1) }
        }
        return (d, c)
    }

    /// Signed ledger balance of an account: debits - credits (positive for asset/expense
    /// accounts with a normal debit balance, negative for liability/income/equity).
    func ledgerAccountBalance(_ accountID: Int64) throws -> Double {
        var bal = 0.0
        try withStatement("SELECT IFNULL(SUM(debit) - SUM(credit), 0) FROM journal_lines WHERE account_id = ?") { s in
            sqlite3_bind_int64(s, 1, accountID)
            if sqlite3_step(s) == SQLITE_ROW { bal = sqlite3_column_double(s, 0) }
        }
        return bal
    }

    /// Ledger balance of a named account (convenience for reports and tests).
    func ledgerBalance(named name: String) throws -> Double {
        try ledgerAccountBalance(try ledgerAccountID(named: name))
    }

    // MARK: - Computed financial statements (derived from the ledger)
    // NOTE: these read the ledger as-is. Call `rebuildJournal()` first (or once the app
    // posts inline, the ledger is always current) so the statements reflect the books.

    /// Grouped account totals for a statement section. `creditNormal` flips the sign so
    /// income/liability/equity come out positive; date range is `[from, to]` (from=nil → through `to`).
    private func reportAccountLines(types: [String], creditNormal: Bool,
                                    from: String?, to: String) throws -> [ReportAccountLine] {
        let typeList = types.map { "'\($0)'" }.joined(separator: ", ")   // literals, not user input
        let amountExpr = creditNormal ? "SUM(j.credit - j.debit)" : "SUM(j.debit - j.credit)"
        let dateClause = (from == nil) ? "j.line_date <= ?" : "j.line_date >= ? AND j.line_date <= ?"
        let sql = """
            SELECT a.id, a.name, IFNULL(\(amountExpr), 0) AS amount
            FROM gl_accounts a JOIN journal_lines j ON j.account_id = a.id
            WHERE a.type IN (\(typeList)) AND \(dateClause)
            GROUP BY a.id, a.name
            HAVING ABS(IFNULL(\(amountExpr), 0)) > 0.005
            ORDER BY a.number, a.id
            """
        var lines: [ReportAccountLine] = []
        try withStatement(sql) { s in
            var idx: Int32 = 1
            if let from { bindText(stmt: s, index: idx, value: from); idx += 1 }
            bindText(stmt: s, index: idx, value: to)
            while sqlite3_step(s) == SQLITE_ROW {
                lines.append(ReportAccountLine(accountID: sqlite3_column_int64(s, 0),
                                               name: columnText(s, 1),
                                               amount: sqlite3_column_double(s, 2)))
            }
        }
        return lines
    }

    /// Profit & Loss over `[start, end]`, derived from the ledger. Income and expenses are
    /// reported as positive amounts; `netIncome = totalIncome − totalExpenses`.
    func computeProfitLoss(start: String, end: String) throws -> ProfitLossReport {
        ProfitLossReport(
            start: start, end: end,
            income: try reportAccountLines(types: ["income"], creditNormal: true, from: start, to: end),
            expenses: try reportAccountLines(types: ["expense"], creditNormal: false, from: start, to: end))
    }

    /// Balance Sheet as of `asOf`, derived from the ledger. It balances *by construction*:
    /// total assets = total liabilities + total equity, where equity includes Retained
    /// Earnings = cumulative net income (income − expenses) through `asOf`.
    func computeBalanceSheet(asOf: String) throws -> BalanceSheetReport {
        let assets = try reportAccountLines(types: ["asset"], creditNormal: false, from: nil, to: asOf)
        let liabilities = try reportAccountLines(types: ["liability"], creditNormal: true, from: nil, to: asOf)
        var equity = try reportAccountLines(types: ["equity"], creditNormal: true, from: nil, to: asOf)

        var retained = 0.0
        try withStatement(
            """
            SELECT IFNULL(SUM(j.credit - j.debit), 0)
            FROM journal_lines j JOIN gl_accounts a ON a.id = j.account_id
            WHERE a.type IN ('income', 'expense') AND j.line_date <= ?
            """
        ) { s in
            bindText(stmt: s, index: 1, value: asOf)
            if sqlite3_step(s) == SQLITE_ROW { retained = sqlite3_column_double(s, 0) }
        }
        if abs(retained) > 0.005 {
            equity.append(ReportAccountLine(accountID: 0, name: "Retained Earnings", amount: retained))
        }
        return BalanceSheetReport(asOf: asOf, assets: assets, liabilities: liabilities, equity: equity)
    }
}

// MARK: - Financial-statement value types

struct ReportAccountLine: Identifiable, Hashable {
    let accountID: Int64
    let name: String
    let amount: Double
    var id: Int64 { accountID }
}

struct ProfitLossReport {
    let start: String
    let end: String
    let income: [ReportAccountLine]
    let expenses: [ReportAccountLine]
    var totalIncome: Double { income.reduce(0) { $0 + $1.amount } }
    var totalExpenses: Double { expenses.reduce(0) { $0 + $1.amount } }
    var netIncome: Double { totalIncome - totalExpenses }
}

struct BalanceSheetReport {
    let asOf: String
    let assets: [ReportAccountLine]
    let liabilities: [ReportAccountLine]
    let equity: [ReportAccountLine]   // includes a synthetic "Retained Earnings" line
    var totalAssets: Double { assets.reduce(0) { $0 + $1.amount } }
    var totalLiabilities: Double { liabilities.reduce(0) { $0 + $1.amount } }
    var totalEquity: Double { equity.reduce(0) { $0 + $1.amount } }
    /// True when assets = liabilities + equity (always, for a correctly posted ledger).
    var isBalanced: Bool { abs(totalAssets - (totalLiabilities + totalEquity)) < 0.005 }
}
