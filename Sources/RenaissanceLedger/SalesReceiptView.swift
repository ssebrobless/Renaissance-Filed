import AppKit
import SwiftUI

struct SalesReceiptsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showNewReceipt = false
    @State private var detailReceipt: SalesReceiptRow?
    @State private var search = ""

    private var filtered: [SalesReceiptRow] {
        guard !search.isEmpty else { return model.salesReceipts }
        return model.salesReceipts.filter {
            $0.receiptNumber.localizedCaseInsensitiveContains(search)
                || $0.customerDisplayName.localizedCaseInsensitiveContains(search)
                || $0.jobName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sales Receipts")
                        .font(.title2.bold())
                    Text("Record one-step paid sales without creating an invoice first.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("+ New Sales Receipt") { showNewReceipt = true }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("salesReceipts.newButton")
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                Text("Receipt #").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .leading)
                Text("Customer").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Method").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .leading)
                Text("Deposit Route").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 180, alignment: .leading)
                Text("Total").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.salesReceipts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.fill").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Sales Receipts").font(.title2)
                    Text("Use sales receipts for cash, check, or card sales that are paid the same day.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { receipt in
                    HStack(spacing: 0) {
                        Text(receipt.receiptNumber)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt.customerDisplayName)
                            if receipt.hasJob {
                                Text(receipt.jobName)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            } else if let detail = receipt.customerDisplayDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(receipt.receiptDate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(receipt.paymentMethodLabel)
                            .frame(width: 120, alignment: .leading)
                        Text(receipt.depositRouteLabel)
                            .foregroundStyle(AppTheme.ink3)
                            .frame(width: 180, alignment: .leading)
                        Text(salesReceiptCurrency(receipt.total))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .trailing)
                            .foregroundStyle(AppTheme.ok)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("salesReceipt.row.\(receipt.id)")
                    .onTapGesture { detailReceipt = receipt }
                }
                .accessibilityIdentifier("salesReceipts.list")
            }
        }
        .accessibilityIdentifier("salesReceipts.root")
        .sheet(isPresented: $showNewReceipt) {
            SalesReceiptSheet {
                showNewReceipt = false
                model.refreshSalesReceipts()
            }
            .environmentObject(model)
        }
        .sheet(item: $detailReceipt) { receipt in
            SalesReceiptDetailSheet(receipt: receipt) {
                detailReceipt = nil
                model.refreshSalesReceipts()
            }
            .environmentObject(model)
        }
    }
}

struct SalesReceiptSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var prefilledCustomerID: Int64 = 0
    var receipt: SalesReceiptRow? = nil
    var duplicateSource: SalesReceiptRow? = nil
    var onSave: () -> Void

    @State private var selectedCustomerID: Int64 = 0
    @State private var selectedJobID: Int64 = 0
    @State private var receiptNumber = ""
    @State private var receiptDate = Date()
    @State private var selectedPaymentMethodID: Int64 = 0
    @State private var selectedDepositAccountID: Int64 = 0
    @State private var memo = ""
    @State private var lines: [InvoiceLineEntry] = [InvoiceLineEntry()]
    @State private var errorMessage = ""
    @State private var didInitialize = false
    @State private var showTemplatePicker = false
    @State private var showSaveTemplate = false
    @Environment(\.dismiss) private var dismiss

    private var total: Double { lines.reduce(0) { $0 + $1.amount } }
    private var canSave: Bool { total > 0 }
    private var isEditing: Bool { receipt != nil }
    private var isDuplicating: Bool { duplicateSource != nil && receipt == nil }
    private var availableJobs: [JobRow] {
        model.jobs
            .filter { $0.customerID == selectedCustomerID }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }
    private var bankAccounts: [AccountRow] {
        model.accounts
            .filter { $0.type == "asset" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var templateDefaultName: String {
        if let customer = model.customers.first(where: { $0.id == selectedCustomerID }) {
            return "\(customer.displayName) Sales Receipt"
        }
        return "Sales Receipt Template"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(sheetTitle)
                    .font(.title2.bold())
                Spacer()
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(AppTheme.bad).font(.caption)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerFields
                    lineItemsSection
                    memoAndTotalSection
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Use Template") { showTemplatePicker = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("salesReceipt.useTemplateButton")
                Button("Memorize") { showSaveTemplate = true }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(currentMemorizedTemplate == nil)
                    .accessibilityIdentifier("salesReceipt.memorizeButton")
                SaveSplitButton(
                    isEditing: isEditing,
                    canSave: canSave,
                    onSaveAndClose: {
                        if saveReceipt() { dismiss() }
                    },
                    onSaveAndNew: isEditing ? nil : {
                        if saveReceipt() { resetForNewReceipt() }
                    }
                )
                .accessibilityIdentifier("salesReceipt.saveButton")
            }
            .padding()
        }
        .frame(width: 940, height: 640)
        .onAppear(perform: setup)
        .onChange(of: selectedCustomerID) { _ in
            guard selectedJobID != 0 else { return }
            if !availableJobs.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = 0
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            MemorizedTransactionPickerSheet(
                type: .salesReceipt,
                payloadType: MemorizedSalesReceiptTemplate.self,
                onApply: applyMemorizedTemplate
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveMemorizedTransactionSheet(
                type: .salesReceipt,
                defaultName: templateDefaultName,
                payloadProvider: { currentMemorizedTemplate }
            )
            .environmentObject(model)
        }
        .accessibilityIdentifier(isEditing ? "salesReceipt.editSheet" : "salesReceipt.newSheet")
    }

    private var headerFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Customer").font(.caption).foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedCustomerID) {
                        Text("- Walk-in / No Customer -").tag(Int64(0))
                        ForEach(model.customers) { customer in
                            Text(customer.displayLabel + (customer.company.isEmpty ? "" : " - " + customer.company)).tag(customer.id)
                        }
                    }
                    .frame(width: 280)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Job").font(.caption).foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedJobID) {
                        Text("- No Job -").tag(Int64(0))
                        ForEach(availableJobs) { job in
                            Text(job.displayLabel).tag(job.id)
                        }
                    }
                    .frame(width: 220)
                    .disabled(selectedCustomerID == 0 || availableJobs.isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Receipt #").font(.caption).foregroundStyle(AppTheme.ink3)
                    TextField("", text: $receiptNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .accessibilityIdentifier("salesReceipt.numberField")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Date").font(.caption).foregroundStyle(AppTheme.ink3)
                    SmartDateField(date: $receiptDate)
                }
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment Method").font(.caption).foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedPaymentMethodID) {
                        Text("- Default Cash -").tag(Int64(0))
                        ForEach(model.paymentMethods) { method in
                            Text(method.name).tag(method.id)
                        }
                    }
                    .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Deposit To").font(.caption).foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedDepositAccountID) {
                        Text("Hold in Undeposited Funds").tag(Int64(0))
                        ForEach(bankAccounts) { account in
                            Text("Direct to \(account.name)").tag(account.id)
                        }
                    }
                    .frame(width: 240)
                    Text(depositRouteHelpText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .frame(width: 260, alignment: .leading)
                }
            }
        }
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ITEM").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 130, alignment: .leading)
                Text("DESCRIPTION").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 60, alignment: .trailing)
                Text("RATE").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .trailing)
                Text("AMOUNT").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
                Spacer().frame(width: 30)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(AppTheme.surface)

            Divider()

            ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                 SalesReceiptLineEditorRow(
                     line: $line,
                     rowIndex: index,
                     serviceItems: model.serviceItems
                 ) {
                     if lines.count > 1 {
                        lines.removeAll { $0.id == line.id }
                     }
                 }
                Divider()
            }

            Button("+ Add Line") {
                lines.append(InvoiceLineEntry())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .accessibilityIdentifier("salesReceipt.addLineButton")
        }
        .background(AppTheme.canvas)
        .cornerRadius(8)
    }

    private var memoAndTotalSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memo / Notes").font(.caption).foregroundStyle(AppTheme.ink3)
                TextField("", text: $memo, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("salesReceipt.memoField")
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Text("PAID TODAY").font(.headline).foregroundStyle(AppTheme.ink3)
                    Text(salesReceiptCurrency(total)).font(.title2.bold())
                }
                Text(depositRouteSummaryText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
            .padding()
            .background(AppTheme.surface)
            .cornerRadius(8)
        }
    }

    private var selectedDepositAccountName: String {
        bankAccounts.first { $0.id == selectedDepositAccountID }?.name ?? "selected bank account"
    }

    private var depositRouteHelpText: String {
        selectedDepositAccountID == 0
            ? "Matches QuickBooks: money waits here until Record Deposit groups it into the real bank deposit."
            : "Use only when this sale already hit \(selectedDepositAccountName) by itself."
    }

    private var depositRouteSummaryText: String {
        selectedDepositAccountID == 0
            ? "Will appear in Record Deposit as undeposited sales receipt money."
            : "Will skip Record Deposit and post directly to \(selectedDepositAccountName)."
    }

    private func setup() {
        guard !didInitialize else { return }
        didInitialize = true

        if let receipt {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = receipt.customerID
            selectedJobID = receipt.jobID
            receiptNumber = receipt.receiptNumber
            receiptDate = formatter.date(from: receipt.receiptDate) ?? Date()
            selectedPaymentMethodID = receipt.paymentMethodID
            selectedDepositAccountID = receipt.depositAccountID
            memo = editableMemo(receipt.memo)
            let existingLines = (try? model.db.fetchSalesReceiptLines(receiptID: receipt.id)) ?? []
            lines = existingLines.isEmpty
                ? [InvoiceLineEntry()]
                : existingLines.map {
                    InvoiceLineEntry(
                        description: $0.description,
                        quantity: String(format: "%.2f", $0.quantity),
                        rate: String(format: "%.2f", $0.rate),
                        isDescriptionManuallyEdited: true,
                        isRateManuallyEdited: true
                    )
                }
            return
        }

        if let duplicateSource {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = duplicateSource.customerID
            selectedJobID = duplicateSource.jobID
            receiptNumber = model.nextSalesReceiptNumber()
            receiptDate = formatter.date(from: duplicateSource.receiptDate) ?? Date()
            selectedPaymentMethodID = duplicateSource.paymentMethodID
            selectedDepositAccountID = duplicateSource.depositAccountID
            memo = editableMemo(duplicateSource.memo)
            let existingLines = (try? model.db.fetchSalesReceiptLines(receiptID: duplicateSource.id)) ?? []
            lines = existingLines.isEmpty
                ? [InvoiceLineEntry()]
                : existingLines.map {
                    InvoiceLineEntry(
                        description: $0.description,
                        quantity: String(format: "%.2f", $0.quantity),
                        rate: String(format: "%.2f", $0.rate),
                        isDescriptionManuallyEdited: true,
                        isRateManuallyEdited: true
                    )
                }
            return
        }

        if selectedCustomerID == 0 && prefilledCustomerID != 0 {
            selectedCustomerID = prefilledCustomerID
        }
        if receiptNumber.isEmpty {
            receiptNumber = model.nextSalesReceiptNumber()
        }
    }

    private var currentMemorizedTemplate: MemorizedSalesReceiptTemplate? {
        let templateLines = lines
            .filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                MemorizedLineTemplate(
                    description: $0.description,
                    quantity: Double($0.quantity) ?? 1,
                    rate: Double($0.rate) ?? 0
                )
            }
        guard !templateLines.isEmpty else { return nil }
        return MemorizedSalesReceiptTemplate(
            customerID: selectedCustomerID,
            jobID: selectedJobID,
            memo: memo,
            paymentMethodID: selectedPaymentMethodID,
            depositAccountID: selectedDepositAccountID,
            lines: templateLines
        )
    }

    private func applyMemorizedTemplate(_ template: MemorizedSalesReceiptTemplate) {
        selectedCustomerID = template.customerID
        selectedJobID = template.jobID
        memo = template.memo
        selectedPaymentMethodID = template.paymentMethodID
        selectedDepositAccountID = template.depositAccountID
        lines = template.lines.isEmpty
            ? [InvoiceLineEntry()]
            : template.lines.map {
                InvoiceLineEntry(
                    description: $0.description,
                    quantity: String(format: "%.2f", $0.quantity),
                    rate: String(format: "%.2f", $0.rate),
                    isDescriptionManuallyEdited: true,
                    isRateManuallyEdited: true
                )
            }
    }

    private var sheetTitle: String {
        if isEditing { return "Edit Sales Receipt" }
        if isDuplicating { return "Duplicate Sales Receipt" }
        return "New Sales Receipt"
    }

    private func saveReceipt() -> Bool {
        let validLines = lines.filter { !$0.description.isEmpty && $0.amount > 0 }
        guard !validLines.isEmpty else {
            errorMessage = "Add at least one line item with description and amount."
            return false
        }

        let trimmedNumber = receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNumber.isEmpty else {
            errorMessage = "Enter a sales receipt number."
            return false
        }

        let receiptDateString = DateFormatter.isoDate.string(from: receiptDate)
        let payload = validLines.map {
            (
                description: $0.description,
                quantity: Double($0.quantity) ?? 1,
                rate: Double($0.rate) ?? 0,
                amount: $0.amount
            )
        }

        do {
            if model.duplicateWarningSettings.warnOnDuplicateInvoiceNumbers,
               try model.db.salesReceiptNumberExists(trimmedNumber, excludingID: receipt?.id) {
                errorMessage = "Sales receipt number \(trimmedNumber) is already in use. Change the number or turn off duplicate warnings in Settings."
                return false
            }

            if let receipt {
                try model.db.updateSalesReceiptWithLines(
                    id: receipt.id,
                    number: trimmedNumber,
                    customerID: selectedCustomerID == 0 ? nil : selectedCustomerID,
                    jobID: selectedJobID == 0 ? nil : selectedJobID,
                    receiptDate: receiptDateString,
                    paymentMethodID: selectedPaymentMethodID == 0 ? nil : selectedPaymentMethodID,
                    depositAccountID: selectedDepositAccountID == 0 ? nil : selectedDepositAccountID,
                    memo: resolvedMemoForSave(editedMemo: memo, originalRawMemo: receipt.memo),
                    total: total,
                    lines: payload
                )
            } else {
                _ = try model.db.saveSalesReceiptWithLines(
                    number: trimmedNumber,
                    customerID: selectedCustomerID == 0 ? nil : selectedCustomerID,
                    jobID: selectedJobID == 0 ? nil : selectedJobID,
                    receiptDate: receiptDateString,
                    paymentMethodID: selectedPaymentMethodID == 0 ? nil : selectedPaymentMethodID,
                    depositAccountID: selectedDepositAccountID == 0 ? nil : selectedDepositAccountID,
                    memo: memo,
                    total: total,
                    lines: payload
                )
            }
            model.refreshSalesReceipts()
            model.refreshNativeInvoices()
            onSave()
            return true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func resetForNewReceipt() {
        selectedCustomerID = 0
        selectedJobID = 0
        receiptNumber = model.nextSalesReceiptNumber()
        receiptDate = Date()
        selectedPaymentMethodID = 0
        selectedDepositAccountID = 0
        memo = ""
        lines = [InvoiceLineEntry()]
        errorMessage = ""
    }
}

struct SalesReceiptDetailSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var onDismiss: () -> Void

    @State private var currentReceipt: SalesReceiptRow
    @State private var lines: [SalesReceiptLineRow] = []
    @State private var showEdit = false
    @State private var showDuplicate = false
    @Environment(\.dismiss) private var dismiss

    init(receipt: SalesReceiptRow, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _currentReceipt = State(initialValue: receipt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sales Receipt \(currentReceipt.receiptNumber)")
                        .font(.title2.bold())
                    Text(currentReceipt.customerDisplayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink3)
                    if currentReceipt.hasJob {
                        Text(currentReceipt.jobName)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    } else if let detail = currentReceipt.customerDisplayDetail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
                Spacer()
                Button("Edit") { showEdit = true }
                Button("Duplicate") { showDuplicate = true }
                Button("Done") { closeSheet() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 28) {
                        salesReceiptField("Date", value: currentReceipt.receiptDate)
                        salesReceiptField("Method", value: currentReceipt.paymentMethodLabel)
                        salesReceiptField("Deposit", value: currentReceipt.depositAccountLabel)
                        salesReceiptField("Total", value: salesReceiptCurrency(currentReceipt.total))
                    }

                    if !currentReceipt.displayMemo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MEMO").font(.caption).foregroundStyle(AppTheme.ink3)
                            Text(currentReceipt.displayMemo)
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("LINE ITEMS")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.ink3)
                            .padding(.bottom, 6)

                        HStack(spacing: 0) {
                            Text("Description").font(.caption).foregroundStyle(AppTheme.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Qty").font(.caption).foregroundStyle(AppTheme.ink3)
                                .frame(width: 60, alignment: .trailing)
                            Text("Rate").font(.caption).foregroundStyle(AppTheme.ink3)
                                .frame(width: 100, alignment: .trailing)
                            Text("Amount").font(.caption).foregroundStyle(AppTheme.ink3)
                                .frame(width: 110, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surface)

                        Divider()

                        if lines.isEmpty {
                            Text("No line items recorded.")
                                .foregroundStyle(AppTheme.ink3)
                                .padding(8)
                        } else {
                            ForEach(lines) { line in
                                HStack(spacing: 0) {
                                    Text(line.description)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.2f", line.quantity))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 60, alignment: .trailing)
                                    Text(salesReceiptCurrency(line.rate))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 100, alignment: .trailing)
                                    Text(salesReceiptCurrency(line.amount))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 110, alignment: .trailing)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                    .background(AppTheme.canvas)
                    .cornerRadius(8)
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Print / Save PDF") { printReceipt() }
                    .buttonStyle(.renaissanceSecondary)
                Button("Email Draft") { emailReceipt() }
                    .buttonStyle(.renaissanceSecondary)
            }
            .padding()
        }
        .frame(width: 760, height: 580)
        .onAppear(perform: loadData)
        .onDisappear { onDismiss() }
        .sheet(isPresented: $showEdit) {
            SalesReceiptSheet(receipt: currentReceipt) {
                showEdit = false
                model.refreshSalesReceipts()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showDuplicate) {
            SalesReceiptSheet(duplicateSource: currentReceipt) {
                showDuplicate = false
                model.refreshSalesReceipts()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .accessibilityIdentifier("salesReceipt.detail.\(currentReceipt.id)")
    }

    private func loadData() {
        lines = (try? model.db.fetchSalesReceiptLines(receiptID: currentReceipt.id)) ?? []
        if let refreshed = try? model.db.fetchSalesReceipt(id: currentReceipt.id) {
            currentReceipt = refreshed
        }
    }

    private func closeSheet() {
        onDismiss()
        dismiss()
    }

    private func printReceipt() {
        let printView = SalesReceiptPrintView(receipt: currentReceipt, lines: lines, companyInfo: model.companyInfo)
        PDFExportService.printView(jobTitle: "Sales Receipt \(currentReceipt.receiptNumber)", view: printView)
    }

    private func emailReceipt() {
        let printView = SalesReceiptPrintView(receipt: currentReceipt, lines: lines, companyInfo: model.companyInfo)
        do {
            let pdfURL = try PDFExportService.writePDF(
                fileName: "Sales-Receipt-\(currentReceipt.receiptNumber).pdf",
                view: printView
            )
            try FileShareService.emailFile(
                fileURL: pdfURL,
                subject: "Sales Receipt \(currentReceipt.receiptNumber)",
                recipientEmails: salesReceiptRecipientEmails(customerID: currentReceipt.customerID)
            )
        } catch {
            model.statusMessage = "Sales receipt email failed: \(error.localizedDescription)"
        }
    }

    private func salesReceiptRecipientEmails(customerID: Int64) -> [String] {
        guard let customer = model.customers.first(where: { $0.id == customerID }) else {
            return []
        }
        return FileShareService.normalizedRecipientEmails(from: customer.email)
    }
}

private struct SalesReceiptLineEditorRow: View {
    @Binding var line: InvoiceLineEntry
    let rowIndex: Int
    let serviceItems: [ServiceItemRow]
    var onDelete: () -> Void

    private var itemOptions: [AutocompleteOption] {
        serviceItems.map {
            AutocompleteOption(
                id: $0.id,
                title: $0.name,
                subtitle: $0.description,
                completionText: $0.name
            )
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            AutocompleteSelectionField(
                placeholder: "Item",
                text: $line.itemName,
                selectedID: $line.selectedItemID,
                options: itemOptions,
                allowsCustomValue: true,
                accessibilityID: "salesReceipt.line.itemField.\(rowIndex)"
            ) { option in
                applySelectedItem(option.id)
            }
            .frame(width: 130)

            TextField("Description of work or materials", text: descriptionBinding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("salesReceipt.line.descriptionField.\(rowIndex)")

            CalcStringField(text: $line.quantity, placeholder: "1")
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("salesReceipt.line.quantityField.\(rowIndex)")

            CalcStringField(text: rateBinding, placeholder: "0.00")
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("salesReceipt.line.rateField.\(rowIndex)")

            Text(salesReceiptCurrency(line.amount))
                .frame(width: 110, alignment: .trailing)
                .font(.system(size: 13, design: .monospaced))

            Button(action: onDelete) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(AppTheme.bad)
            }
            .buttonStyle(.plain)
            .frame(width: 22)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { line.description },
            set: { newValue in
                line.markDescriptionEdited(byUser: newValue)
            }
        )
    }

    private var rateBinding: Binding<String> {
        Binding(
            get: { line.rate },
            set: { newValue in
                line.markRateEdited(byUser: newValue)
            }
        )
    }

    private func applySelectedItem(_ itemID: Int64) {
        guard itemID != 0, let item = serviceItems.first(where: { $0.id == itemID }) else { return }
        line.applyItemDefaults(
            itemName: item.name,
            defaultDescription: item.description.isEmpty ? item.name : item.description,
            defaultRate: item.unitPrice
        )
    }
}

struct SalesReceiptPrintView: View {
    let receipt: SalesReceiptRow
    let lines: [SalesReceiptLineRow]
    var companyInfo: CompanyInfo = CompanyInfo()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(companyInfo.name)
                        .font(.system(size: 20, weight: .bold))
                    if !companyInfo.address1.isEmpty {
                        Text(companyInfo.address1)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !companyInfo.cityStateZip.isEmpty {
                        Text(companyInfo.cityStateZip)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !companyInfo.phone.isEmpty {
                        Text(companyInfo.phone)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if !companyInfo.email.isEmpty {
                        Text(companyInfo.email)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Text("Sales Receipt")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ink3)
                        .padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Receipt #").foregroundStyle(AppTheme.ink3)
                        Text(receipt.receiptNumber).bold()
                    }
                    HStack {
                        Text("Date").foregroundStyle(AppTheme.ink3)
                        Text(receipt.receiptDate)
                    }
                    HStack {
                        Text("Method").foregroundStyle(AppTheme.ink3)
                        Text(receipt.paymentMethodLabel)
                    }
                }
            }
            .padding(.bottom, 24)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("SOLD TO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.ink3)
                    .padding(.top, 12)
                Text(receipt.customerDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = receipt.customerDisplayDetail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.ink3)
                }
                if receipt.hasJob {
                    Text(receipt.jobName)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.ink3)
                }
            }
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 0) {
                Text("Description").font(.system(size: 9, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").font(.system(size: 9, weight: .bold)).frame(width: 55, alignment: .trailing)
                Text("Rate").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .trailing)
                Text("Amount").font(.system(size: 9, weight: .bold)).frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(AppTheme.surface)

            ForEach(lines) { line in
                HStack(spacing: 0) {
                    Text(line.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.2f", line.quantity))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 55, alignment: .trailing)
                    Text(salesReceiptPrintCurrency(line.rate))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                    Text(salesReceiptPrintCurrency(line.amount))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                Divider()
            }

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 16) {
                        Text("TOTAL PAID").fontWeight(.bold)
                        Text(salesReceiptPrintCurrency(receipt.total))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.ok)
                    }
                    HStack(spacing: 16) {
                        Text("Deposit").foregroundStyle(AppTheme.ink3)
                        Text(receipt.depositAccountLabel)
                    }
                }
                .frame(width: 300)
            }
            .padding(.top, 12)

            if !receipt.displayMemo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.ink3)
                        .padding(.top, 20)
                    Text(receipt.displayMemo)
                        .font(.system(size: 10))
                }
            }

            Spacer()

            Divider()
            Text(companyInfo.invoiceFooter.isEmpty ? "Thank you for your business." : companyInfo.invoiceFooter)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.ink3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
        .padding(36)
        .font(.system(size: 11))
    }
}

private func salesReceiptField(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption).foregroundStyle(AppTheme.ink3)
        Text(value).font(.body.bold())
    }
}

private func salesReceiptCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}

private func salesReceiptPrintCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
