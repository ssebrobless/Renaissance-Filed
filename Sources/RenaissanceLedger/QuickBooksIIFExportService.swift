import Foundation

enum QuickBooksIIFExportError: LocalizedError {
    case noLines

    var errorDescription: String? {
        switch self {
        case .noLines:
            return "QuickBooks export needs at least one line item."
        }
    }
}

enum QuickBooksIIFExportService {
    static func writeEstimateIIF(estimate: EstimateRow, lines: [EstimateLineRow]) throws -> URL {
        guard !lines.isEmpty else {
            throw QuickBooksIIFExportError.noLines
        }

        let incomeAccount = "Income"
        let estimateAccount = "Estimates"
        let customerName = estimate.customerDisplayLabel
        let documentNumber = estimate.estimateNumber
        let txnDate = quickBooksDate(estimate.issueDate)
        let dueDate = quickBooksDate(estimate.validUntil.isEmpty ? estimate.issueDate : estimate.validUntil)

        var output = [String]()
        output.append(iifRow(["!ACCNT", "NAME", "ACCNTTYPE", "ACCNUM", "EXTRA"]))
        output.append(iifRow(["ACCNT", incomeAccount, "INC", "", ""]))
        output.append(iifRow(["ACCNT", estimateAccount, "NONPOSTING", "4", "ESTIMATE"]))
        output.append(iifRow(["!INVITEM", "NAME", "INVITEMTYPE", "DESC", "PURCHASEDESC", "ACCNT", "ASSETACCNT", "COGSACCNT", "PRICE", "COST", "TAXABLE"]))
        for (index, line) in lines.enumerated() {
            output.append(iifRow([
                "INVITEM",
                itemName(prefix: "EST", documentNumber: documentNumber, index: index),
                "SERV",
                line.description,
                "",
                incomeAccount,
                "",
                "",
                decimal(line.rate),
                "0",
                "N"
            ]))
        }
        output.append(iifRow(["!CUST", "NAME"]))
        output.append(iifRow(["CUST", customerName]))
        output.append(iifRow([
            "!TRNS", "TRNSID", "TRNSTYPE", "DATE", "ACCNT", "NAME", "CLASS", "AMOUNT",
            "DOCNUM", "MEMO", "CLEAR", "TOPRINT", "NAMEISTAXABLE", "ADDR1", "ADDR2", "ADDR3",
            "ADDR4", "ADDR5", "DUEDATE", "TERMS", "PAID", "SHIPDATE"
        ]))
        output.append(iifRow([
            "!SPL", "SPLID", "TRNSTYPE", "DATE", "ACCNT", "NAME", "CLASS", "AMOUNT",
            "DOCNUM", "MEMO", "CLEAR", "QNTY", "PRICE", "INVITEM", "PAYMETH", "TAXABLE",
            "VALADJ", "REIMBEXP", "SERVICEDATE", "OTHER2", "OTHER3"
        ]))
        output.append(iifRow(["!ENDTRNS"]))
        output.append(iifRow([
            "TRNS", "", "ESTIMATE", txnDate, estimateAccount, customerName, "", decimal(estimate.total),
            documentNumber, estimate.displayMemo, "N", "Y", "N", customerName, "", "", "", "",
            dueDate, "", "N", txnDate
        ]))
        for (index, line) in lines.enumerated() {
            output.append(iifRow([
                "SPL", "", "ESTIMATE", txnDate, incomeAccount, "", "", decimal(-line.amount),
                "", line.description, "N", quantity(line.quantity), decimal(line.rate),
                itemName(prefix: "EST", documentNumber: documentNumber, index: index), "", "N",
                "N", "NOTHING", txnDate, "", ""
            ]))
        }
        output.append(iifRow(["ENDTRNS"]))

        return try writeIIFFile(
            fileName: "Estimate-\(sanitizedFileName(documentNumber)).iif",
            contents: output.joined(separator: "\n") + "\n"
        )
    }

    static func writeInvoiceIIF(invoice: NativeInvoiceRow, lines: [InvoiceLineRow]) throws -> URL {
        guard !lines.isEmpty else {
            throw QuickBooksIIFExportError.noLines
        }

        let receivableAccount = "Accounts Receivable"
        let incomeAccount = "Income"
        let customerName = invoice.customerDisplayLabel
        let documentNumber = invoice.invoiceNumber
        let txnDate = quickBooksDate(invoice.issueDate)
        let dueDate = quickBooksDate(invoice.dueDate.isEmpty ? invoice.issueDate : invoice.dueDate)

        var output = [String]()
        output.append(iifRow(["!ACCNT", "NAME", "ACCNTTYPE", "DESC", "ACCNUM", "EXTRA"]))
        output.append(iifRow(["ACCNT", receivableAccount, "AR", "", "1200", ""]))
        output.append(iifRow(["ACCNT", incomeAccount, "INC", "", "4100", ""]))
        output.append(iifRow(["!INVITEM", "NAME", "INVITEMTYPE", "DESC", "PURCHASEDESC", "ACCNT", "ASSETACCNT", "COGSACCNT", "PRICE", "COST", "TAXABLE"]))
        for (index, line) in lines.enumerated() {
            output.append(iifRow([
                "INVITEM",
                itemName(prefix: "INV", documentNumber: documentNumber, index: index),
                "SERV",
                line.description,
                "",
                incomeAccount,
                "",
                "",
                decimal(line.rate),
                "0",
                "N"
            ]))
        }
        output.append(iifRow(["!CUST", "NAME"]))
        output.append(iifRow(["CUST", customerName]))
        output.append(iifRow([
            "!TRNS", "TRNSID", "TRNSTYPE", "DATE", "ACCNT", "NAME", "CLASS", "AMOUNT",
            "DOCNUM", "MEMO", "CLEAR", "TOPRINT", "NAMEISTAXABLE", "ADDR1", "ADDR3",
            "TERMS", "SHIPVIA", "SHIPDATE"
        ]))
        output.append(iifRow([
            "!SPL", "SPLID", "TRNSTYPE", "DATE", "ACCNT", "NAME", "CLASS", "AMOUNT",
            "DOCNUM", "MEMO", "CLEAR", "QNTY", "PRICE", "INVITEM", "TAXABLE", "OTHER2",
            "YEARTODATE", "WAGEBASE"
        ]))
        output.append(iifRow(["!ENDTRNS"]))
        output.append(iifRow([
            "TRNS", "", "INVOICE", txnDate, receivableAccount, customerName, "", decimal(invoice.total),
            documentNumber, invoice.displayMemo, "N", "Y", "N", customerName, "", "", "", dueDate
        ]))
        for (index, line) in lines.enumerated() {
            output.append(iifRow([
                "SPL", "", "INVOICE", txnDate, incomeAccount, "", "", decimal(-line.amount),
                "", line.description, "N", quantity(line.quantity), decimal(line.rate),
                itemName(prefix: "INV", documentNumber: documentNumber, index: index), "N", "", "0", "0"
            ]))
        }
        output.append(iifRow(["ENDTRNS"]))

        return try writeIIFFile(
            fileName: "Invoice-\(sanitizedFileName(documentNumber)).iif",
            contents: output.joined(separator: "\n") + "\n"
        )
    }

    static func writeCheckIIF(draft: CheckDraft) throws -> URL {
        let bankAccount = draft.bankAccountName.isEmpty ? "Checking" : draft.bankAccountName
        let expenseAccount = draft.categoryName.isEmpty ? "Expense" : draft.categoryName
        let vendorName = draft.payeeName.isEmpty ? "Payee" : draft.payeeName
        let txnDate = quickBooksDate(draft.expenseDate)
        let effectiveLines = draft.itemLines.isEmpty
            ? [CheckItemDraft(serviceItemID: 0, itemName: draft.detailSummary, description: draft.memo, quantity: 1, rate: draft.amount, amount: draft.amount)]
            : draft.itemLines

        var output = [String]()
        output.append(iifRow(["!ACCNT", "NAME", "ACCNTTYPE", "DESC", "ACCNUM", "EXTRA"]))
        output.append(iifRow(["ACCNT", bankAccount, "BANK", "", "", ""]))
        output.append(iifRow(["ACCNT", expenseAccount, "EXP", "", "", ""]))
        output.append(iifRow(["!INVITEM", "NAME", "INVITEMTYPE", "DESC", "PURCHASEDESC", "ACCNT", "ASSETACCNT", "COGSACCNT", "PRICE", "COST", "TAXABLE"]))
        for (index, line) in effectiveLines.enumerated() {
            let description = line.description.isEmpty ? (line.itemName.isEmpty ? "Check Detail" : line.itemName) : line.description
            output.append(iifRow([
                "INVITEM",
                itemName(prefix: "CHK", documentNumber: draft.checkNumber.isEmpty ? "Draft" : draft.checkNumber, index: index),
                "SERV",
                description,
                "",
                expenseAccount,
                "",
                "",
                decimal(line.rate),
                "0",
                "N"
            ]))
        }
        output.append(iifRow(["!VEND", "NAME"]))
        output.append(iifRow(["VEND", vendorName]))
        output.append(iifRow([
            "!TRNS", "TRNSID", "TRNSTYPE", "DATE", "ACCNT", "NAME", "CLASS", "AMOUNT",
            "DOCNUM", "CLEAR", "TOPRINT", "NAMEISTAXABLE", "ADDR1", "ADDR2", "ADDR3", "ADDR4", "ADDR5"
        ]))
        output.append(iifRow([
            "!SPL", "SPLID", "TRNSTYPE", "DATE", "ACCNT", "NAME", "CLASS", "AMOUNT",
            "DOCNUM", "CLEAR", "QNTY", "PRICE", "INVITEM", "PAYMETH", "TAXABLE", "VALADJ", "REIMBEXP"
        ]))
        output.append(iifRow(["!ENDTRNS"]))
        output.append(iifRow([
            "TRNS", "", "CHECK", txnDate, bankAccount, vendorName, "", decimal(-draft.amount),
            draft.checkNumber, "N", "Y", "N", "", "", "", "", ""
        ]))
        for (index, line) in effectiveLines.enumerated() {
            let splitAmount = line.amount == 0 && effectiveLines.count == 1 ? draft.amount : line.amount
            let quantityValue = abs(line.quantity - 1) < 0.0001 ? "" : quantity(line.quantity)
            let priceValue = line.rate == 0 && !quantityValue.isEmpty ? "" : decimal(line.rate == 0 && quantityValue.isEmpty ? splitAmount : line.rate)
            output.append(iifRow([
                "SPL", "", "CHECK", txnDate, expenseAccount, "", "", decimal(splitAmount),
                "", "N", quantityValue, priceValue,
                itemName(prefix: "CHK", documentNumber: draft.checkNumber.isEmpty ? "Draft" : draft.checkNumber, index: index),
                "", "", "NOTHING", ""
            ]))
        }
        output.append(iifRow(["ENDTRNS"]))

        let fallbackNumber = draft.checkNumber.isEmpty ? "Draft" : draft.checkNumber
        return try writeIIFFile(
            fileName: "Check-\(sanitizedFileName(fallbackNumber)).iif",
            contents: output.joined(separator: "\n") + "\n"
        )
    }

    private static func writeIIFFile(fileName: String, contents: String) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try contents.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private static func iifRow(_ fields: [String]) -> String {
        fields.map(iifField).joined(separator: "\t")
    }

    private static func iifField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let allowed = value.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        return String(allowed)
    }

    private static func itemName(prefix: String, documentNumber: String, index: Int) -> String {
        let base = "\(prefix)-\(sanitizedFileName(documentNumber))-\(String(format: "%02d", index + 1))"
        return String(base.prefix(31))
    }

    private static func quickBooksDate(_ isoDate: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: isoDate) else {
            return isoDate
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        return formatter.string(from: date)
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    private static func quantity(_ value: Double) -> String {
        if abs(value - 1.0) < 0.0001 {
            return ""
        }
        return decimal(value)
    }
}
