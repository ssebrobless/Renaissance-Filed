import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showAddSheet = false
    @State private var showWriteCheck = false
    @State private var editingExpense: ExpenseRow?
    @State private var editingCheck: ExpenseRow?
    @State private var search = ""

    private var filtered: [ExpenseRow] {
        guard !search.isEmpty else { return model.expenses }
        return model.expenses.filter {
            $0.displayVendorName.localizedCaseInsensitiveContains(search)
            || $0.vendorName.localizedCaseInsensitiveContains(search)
            || $0.jobName.localizedCaseInsensitiveContains(search)
            || $0.accountName.localizedCaseInsensitiveContains(search)
            || $0.paymentAccountName.localizedCaseInsensitiveContains(search)
            || $0.checkNumber.contains(search)
            || $0.displayMemo.localizedCaseInsensitiveContains(search)
        }
    }

    private var totalShown: Double { filtered.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Expenses")
                    .font(.title2.bold())
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Write Check") { showWriteCheck = true }
                    .accessibilityIdentifier("expenses.writeCheckButton")
                Button("+ Add Expense") { showAddSheet = true }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("expenses.addButton")
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Vendor / Payee").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Category").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 180, alignment: .leading)
                Text("Paid From").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 170, alignment: .leading)
                Text("Check #").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 90, alignment: .leading)
                Text("Memo").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Amount").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.expenses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Expenses").font(.title2)
                    Text("Record your first expense or write a check using the buttons above.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { expense in
                    HStack(spacing: 0) {
                        Text(expense.expenseDate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.displayVendorName)
                            if let detail = expense.displayVendorDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                            if expense.hasJob {
                                Text("Job: \(expense.jobName)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(expense.accountName)
                            .frame(width: 180, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(expense.paymentAccountName)
                            .frame(width: 170, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(expense.checkNumber)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                        Text(expense.displayMemo)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppTheme.ink3)
                            .lineLimit(1)
                        Text(formatExpense(expense.amount))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.bad)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("expense.row.\(expense.id)")
                    .onTapGesture {
                        if expense.checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            editingExpense = expense
                        } else {
                            editingCheck = expense
                        }
                    }
                }
                .accessibilityIdentifier("expenses.list")
            }

            if !filtered.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Text("Total: \(formatExpense(totalShown))")
                        .font(.headline)
                        .foregroundStyle(AppTheme.bad)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(AppTheme.surface)
            }
        }
        .accessibilityIdentifier("expenses.root")
        .onAppear {
            openHarnessExpenseIfNeeded()
            openHarnessWriteCheckIfNeeded()
        }
        .sheet(isPresented: $showAddSheet) {
            ExpenseSheet(expense: nil) {
                showAddSheet = false
                model.refreshExpenses()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showWriteCheck) {
            WriteCheckSheet(expense: nil) {
                showWriteCheck = false
                model.refreshExpenses()
            }
            .environmentObject(model)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseSheet(expense: expense) {
                editingExpense = nil
                model.refreshExpenses()
            }
            .environmentObject(model)
        }
        .sheet(item: $editingCheck) { expense in
            WriteCheckSheet(expense: expense) {
                editingCheck = nil
                model.refreshExpenses()
            }
            .environmentObject(model)
        }
    }

    private func openHarnessWriteCheckIfNeeded() {
        guard !showWriteCheck, model.consumePendingOpenWriteCheck() else { return }
        showWriteCheck = true
    }

    private func openHarnessExpenseIfNeeded() {
        guard let expenseID = model.consumePendingOpenExpenseID(),
              let expense = model.expenses.first(where: { $0.id == expenseID }) ?? (try? model.db.fetchExpense(id: expenseID)) else {
            return
        }
        if expense.checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editingExpense = expense
        } else {
            editingCheck = expense
        }
    }

    private func formatExpense(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

#if false
struct WriteCheckSheetLegacy: View {
    @EnvironmentObject private var model: AppViewModel
    var onSave: () -> Void

    @State private var checkDate = Date()
    @State private var selectedVendorID: Int64 = 0
    @State private var selectedJobID: Int64 = 0
    @State private var payeeName = ""
    @State private var amount = ""
    @State private var selectedExpenseAccountID: Int64 = 0
    @State private var selectedBankAccountID: Int64 = 0
    @State private var expenseCategoryText = ""
    @State private var bankAccountText = ""
    @State private var jobText = ""
    @State private var checkNumber = ""
    @State private var memo = ""
    @State private var errorMessage = ""
    @State private var lastSuggestedCheckNumber = ""
    @State private var appliedHarnessPreview = false
    @State private var showTemplatePicker = false
    @State private var showSaveTemplate = false
    @Environment(\.dismiss) private var dismiss

    private let previewScale: CGFloat = 0.58

    private var expenseAccounts: [AccountRow] { model.accounts.filter { $0.type == "expense" } }
    private var assetAccounts: [AccountRow] { model.accounts.filter { $0.type == "asset" } }
    private var jobOptions: [AutocompleteOption] {
        model.jobs
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
            .map {
                AutocompleteOption(
                    id: $0.id,
                    title: $0.displayLabel,
                    subtitle: $0.siteAddress,
                    completionText: $0.displayLabel
                )
            }
    }
    private var vendorOptions: [AutocompleteOption] {
        model.vendors.map {
            let subtitle = [$0.displayDetail, $0.company]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " - ")
            return AutocompleteOption(
                id: $0.id,
                title: $0.displayName,
                subtitle: subtitle,
                completionText: $0.displayName
            )
        }
    }
    private var expenseAccountOptions: [AutocompleteOption] {
        expenseAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }
    private var bankAccountOptions: [AutocompleteOption] {
        assetAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }
    private var amountValue: Double { parseCurrencyAmount(amount) }
    private var trimmedPayeeName: String { payeeName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedExpenseAccountName: String {
        expenseAccounts.first(where: { $0.id == selectedExpenseAccountID })?.name ?? ""
    }
    private var selectedBankAccountName: String {
        assetAccounts.first(where: { $0.id == selectedBankAccountID })?.name ?? ""
    }
    private var canSave: Bool {
        !trimmedPayeeName.isEmpty
        && amountValue > 0
        && selectedExpenseAccountID != 0
        && selectedBankAccountID != 0
        && !checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var templateDefaultName: String {
        let payee = trimmedPayeeName
        return payee.isEmpty ? "Check Template" : "\(payee) Check"
    }
    private var currentDraft: CheckDraft {
        CheckDraft(
            payeeName: trimmedPayeeName,
            checkNumber: checkNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            expenseDate: DateFormatter.isoDate.string(from: checkDate),
            amount: amountValue,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryName: selectedExpenseAccountName,
            bankAccountName: selectedBankAccountName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Write Check")
                        .font(.title2.bold())
                    Text("Fill out the check, save it into expenses, and print from the same screen.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.bad)
                        .font(.caption)
                        .frame(maxWidth: 240, alignment: .trailing)
                }
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 20) {
                Form {
                    Section("Check Details") {
                        LabeledContent("Date") { SmartDateField(date: $checkDate) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Payee")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            AutocompleteSelectionField(
                                placeholder: "Pay to the Order Of",
                                text: $payeeName,
                                selectedID: $selectedVendorID,
                                options: vendorOptions,
                                allowsCustomValue: true,
                                accessibilityID: "writeCheck.payeeField"
                            )
                        }
                        HStack {
                            Text("Amount")
                            Spacer()
                            CalcStringField(text: $amount, placeholder: "0.00")
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("writeCheck.amountField")
                        }
                    }

                    Section("Coding") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Job")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            AutocompleteSelectionField(
                                placeholder: "Optional job",
                                text: $jobText,
                                selectedID: $selectedJobID,
                                options: jobOptions,
                                accessibilityID: "writeCheck.jobField"
                            )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Expense Category")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            AutocompleteSelectionField(
                                placeholder: "Type a category",
                                text: $expenseCategoryText,
                                selectedID: $selectedExpenseAccountID,
                                options: expenseAccountOptions,
                                accessibilityID: "writeCheck.categoryField"
                            )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Bank Account")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                            AutocompleteSelectionField(
                                placeholder: "Type a bank account",
                                text: $bankAccountText,
                                selectedID: $selectedBankAccountID,
                                options: bankAccountOptions,
                                accessibilityID: "writeCheck.bankAccountField"
                            )
                        }
                        TextField("Check #", text: $checkNumber)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("writeCheck.checkNumberField")
                        TextField("Memo", text: $memo)
                            .accessibilityIdentifier("writeCheck.memoField")
                    }

                    Section("Workflow") {
                        LabeledContent("Suggested Number") {
                            Text(lastSuggestedCheckNumber.isEmpty ? "Select a bank account" : lastSuggestedCheckNumber)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(AppTheme.ink3)
                        }
                        Text("Use Save & Print when you are issuing a real check. The check is saved first, then the print panel opens.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
                .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)
                .frame(width: 390)

                checkPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Use Template") { showTemplatePicker = true }
                    .accessibilityIdentifier("writeCheck.useTemplateButton")
                Button("Memorize") { showSaveTemplate = true }
                    .disabled(currentMemorizedTemplate == nil)
                    .accessibilityIdentifier("writeCheck.memorizeButton")
                Button("Email QB File") { emailCheckDraft() }
                    .disabled(!canSave)
                    .accessibilityIdentifier("writeCheck.emailButton")
                SaveSplitButton(
                    isEditing: false,
                    canSave: canSave,
                    onSaveAndClose: {
                        if saveCheck(printAfterSave: false) { dismiss() }
                    },
                    onSaveAndNew: {
                        if saveCheck(printAfterSave: false) {
                            selectedVendorID = 0
                            payeeName = ""
                            selectedJobID = 0
                            amount = ""
                            selectedExpenseAccountID = 0
                            expenseCategoryText = ""
                            memo = ""
                            itemLines = [CheckItemEntry()]
                            codingMode = .category
                            errorMessage = ""
                            refreshSuggestedCheckNumber(force: true)
                        }
                    }
                )
                .accessibilityIdentifier("writeCheck.saveButton")
                Button("Save & Print") { if saveCheck(printAfterSave: true) { dismiss() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("writeCheck.saveAndPrintButton")
            }
            .padding()
        }
        .frame(width: 1080, height: 680)
        .onAppear {
            setup()
            applyHarnessPreviewIfNeeded()
        }
        .onChange(of: selectedBankAccountID) { _ in
            bankAccountText = assetAccounts.first(where: { $0.id == selectedBankAccountID })?.name ?? bankAccountText
            refreshSuggestedCheckNumber()
        }
        .onChange(of: selectedJobID) { _ in
            jobText = jobOptions.first(where: { $0.id == selectedJobID })?.title ?? jobText
        }
        .onChange(of: selectedExpenseAccountID) { _ in
            expenseCategoryText = expenseAccounts.first(where: { $0.id == selectedExpenseAccountID })?.name ?? expenseCategoryText
        }
        .sheet(isPresented: $showTemplatePicker) {
            MemorizedTransactionPickerSheet(
                type: .check,
                payloadType: MemorizedCheckTemplate.self,
                onApply: applyMemorizedTemplate
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveMemorizedTransactionSheet(
                type: .check,
                defaultName: templateDefaultName,
                payloadProvider: { currentMemorizedTemplate }
            )
            .environmentObject(model)
        }
        .accessibilityIdentifier("writeCheck.sheet")
    }

    private var checkPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Print Preview")
                    .font(.headline)
                Spacer()
                if !selectedBankAccountName.isEmpty {
                    Text(selectedBankAccountName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }

            ScrollView([.vertical, .horizontal]) {
                CheckPrintView(draft: currentDraft, companyInfo: model.companyInfo)
                    .scaleEffect(previewScale, anchor: .topLeading)
                    .frame(width: 612 * previewScale, height: 792 * previewScale, alignment: .topLeading)
                    .padding(.bottom, 8)
            }
            .background(AppTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }

    private func setup() {
        if let checking = assetAccounts.first(where: { $0.name.lowercased().contains("checking") }) ?? assetAccounts.first {
            selectedBankAccountID = checking.id
            bankAccountText = checking.name
        }
        refreshSuggestedCheckNumber(force: true)
    }

    private func applyHarnessPreviewIfNeeded() {
        guard !appliedHarnessPreview,
              let query = model.consumePendingPreviewWriteCheckPayeeQuery()
        else { return }
        appliedHarnessPreview = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        appendHarnessLog("write-check preview query consumed='\(trimmed)'")
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            selectedVendorID = 0
            payeeName = trimmed
            appendHarnessLog("write-check preview applied payee='\(payeeName)'")
        }
    }

    private func refreshSuggestedCheckNumber(force: Bool = false) {
        guard selectedBankAccountID != 0 else {
            if force {
                checkNumber = ""
                lastSuggestedCheckNumber = ""
            }
            return
        }

        let suggested = model.nextCheckNumber(paymentAccountID: selectedBankAccountID)
        if force || checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checkNumber == lastSuggestedCheckNumber {
            checkNumber = suggested
        }
        lastSuggestedCheckNumber = suggested
    }

    private var currentMemorizedTemplate: MemorizedCheckTemplate? {
        guard !trimmedPayeeName.isEmpty else { return nil }
        return MemorizedCheckTemplate(
            vendorID: selectedVendorID,
            payeeName: trimmedPayeeName,
            jobID: selectedJobID,
            expenseAccountID: selectedExpenseAccountID,
            bankAccountID: selectedBankAccountID,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultAmount: amountValue
        )
    }

    private func applyMemorizedTemplate(_ template: MemorizedCheckTemplate) {
        selectedVendorID = template.vendorID
        payeeName = template.payeeName
        selectedJobID = template.jobID
        selectedExpenseAccountID = template.expenseAccountID
        selectedBankAccountID = template.bankAccountID
        memo = template.memo
        amount = template.defaultAmount > 0 ? String(format: "%.2f", template.defaultAmount) : amount
    }

    private func saveCheck(printAfterSave: Bool) -> Bool {
        guard amountValue > 0 else {
            errorMessage = "Enter a valid amount greater than zero."
            return false
        }
        guard !trimmedPayeeName.isEmpty else {
            errorMessage = "Enter the payee name."
            return false
        }
        guard selectedExpenseAccountID != 0 else {
            errorMessage = "Choose the expense category for this check."
            return false
        }
        guard selectedBankAccountID != 0 else {
            errorMessage = "Choose the bank account this check is drawn from."
            return false
        }
        guard !checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter or accept the suggested check number."
            return false
        }

        let vendorID: Int64? = selectedVendorID == 0 ? nil : selectedVendorID

        do {
            _ = try model.db.insertExpense(
                vendorNameOverride: trimmedPayeeName,
                vendorID: vendorID,
                expenseDate: currentDraft.expenseDate,
                amount: amountValue,
                accountID: selectedExpenseAccountID,
                paymentAccountID: selectedBankAccountID,
                checkNumber: currentDraft.checkNumber,
                memo: currentDraft.memo,
                jobID: selectedJobID == 0 ? nil : selectedJobID
            )
            if printAfterSave {
                printCheck(currentDraft, companyInfo: model.companyInfo)
            }
            onSave()
            return true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func emailCheckDraft() {
        do {
            let iifURL = try QuickBooksIIFExportService.writeCheckIIF(draft: currentDraft)
            var attachments = [iifURL]
            if let pdfURL = try? PDFExportService.writePDF(
                fileName: "Check-\(currentDraft.checkNumber.isEmpty ? "Draft" : currentDraft.checkNumber).pdf",
                view: CheckPrintView(draft: currentDraft, companyInfo: model.companyInfo)
            ) {
                attachments.append(pdfURL)
            }
            try FileShareService.emailFiles(
                fileURLs: attachments,
                subject: "Check \(currentDraft.checkNumber.isEmpty ? "Draft" : currentDraft.checkNumber) - QuickBooks IIF"
            )
        } catch {
            errorMessage = "Email failed: \(error.localizedDescription)"
        }
    }
}

#endif

struct WriteCheckSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let expense: ExpenseRow?
    var onSave: () -> Void

    @State private var checkDate = Date()
    @State private var selectedVendorID: Int64 = 0
    @State private var selectedJobID: Int64 = 0
    @State private var payeeName = ""
    @State private var amount = ""
    @State private var selectedExpenseAccountID: Int64 = 0
    @State private var selectedBankAccountID: Int64 = 0
    @State private var expenseCategoryText = ""
    @State private var bankAccountText = ""
    @State private var jobText = ""
    @State private var checkNumber = ""
    @State private var memo = ""
    @State private var codingMode: CheckCodingMode = .category
    @State private var itemLines: [CheckItemEntry] = [CheckItemEntry()]
    @State private var errorMessage = ""
    @State private var lastSuggestedCheckNumber = ""
    @State private var appliedHarnessPreview = false
    @State private var showTemplatePicker = false
    @State private var showSaveTemplate = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var expenseAccounts: [AccountRow] { model.accounts.filter { $0.type == "expense" } }
    private var assetAccounts: [AccountRow] { model.accounts.filter { $0.type == "asset" } }
    private var isEditing: Bool { expense != nil }
    private var amountValue: Double { parseCurrencyAmount(amount) }
    private var itemTotal: Double { currentItemDraftLines.reduce(0) { $0 + $1.amount } }
    private var effectiveAmountValue: Double { codingMode == .items ? itemTotal : amountValue }
    private var trimmedPayeeName: String { payeeName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedExpenseAccountName: String { expenseAccounts.first(where: { $0.id == selectedExpenseAccountID })?.name ?? "" }
    private var selectedBankAccountName: String { assetAccounts.first(where: { $0.id == selectedBankAccountID })?.name ?? "" }
    private var templateDefaultName: String {
        let payee = trimmedPayeeName
        return payee.isEmpty ? "Check Template" : "\(payee) Check"
    }

    private var jobOptions: [AutocompleteOption] {
        model.jobs
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
            .map {
                AutocompleteOption(
                    id: $0.id,
                    title: $0.displayLabel,
                    subtitle: $0.siteAddress,
                    completionText: $0.displayLabel
                )
            }
    }

    private var vendorOptions: [AutocompleteOption] {
        model.vendors.map {
            let subtitle = [$0.displayDetail, $0.company]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " - ")
            return AutocompleteOption(
                id: $0.id,
                title: $0.displayName,
                subtitle: subtitle,
                completionText: $0.displayName
            )
        }
    }

    private var expenseAccountOptions: [AutocompleteOption] {
        expenseAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }

    private var bankAccountOptions: [AutocompleteOption] {
        assetAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }

    private var currentItemDraftLines: [CheckItemDraft] {
        itemLines.compactMap { line in
            let itemName = line.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let quantity = max(0, Double(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
            let rate = max(0, parseCurrencyAmount(line.rate))
            let amount = quantity * rate
            guard !itemName.isEmpty || !description.isEmpty || amount > 0 else { return nil }
            return CheckItemDraft(
                id: line.id,
                serviceItemID: line.selectedItemID,
                itemName: itemName,
                description: description.isEmpty ? itemName : description,
                quantity: quantity == 0 ? 1 : quantity,
                rate: rate,
                amount: amount == 0 ? rate : amount
            )
        }
    }

    private var itemDetailSummary: String {
        let labels = currentItemDraftLines.map { line in
            let item = line.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.isEmpty ? detail : item
        }.filter { !$0.isEmpty }

        guard !labels.isEmpty else { return "" }
        if labels.count == 1 { return labels[0] }
        if labels.count == 2 { return "\(labels[0]); \(labels[1])" }
        return "\(labels[0]); \(labels[1]) +\(labels.count - 2) more"
    }

    private var canSave: Bool {
        guard !trimmedPayeeName.isEmpty,
              selectedExpenseAccountID != 0,
              selectedBankAccountID != 0,
              !checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch codingMode {
        case .category:
            return amountValue > 0
        case .items:
            return itemTotal > 0 && !currentItemDraftLines.isEmpty
        }
    }

    private var currentDraft: CheckDraft {
        CheckDraft(
            payeeName: trimmedPayeeName,
            checkNumber: checkNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            expenseDate: DateFormatter.isoDate.string(from: checkDate),
            amount: effectiveAmountValue,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryName: selectedExpenseAccountName,
            bankAccountName: selectedBankAccountName,
            detailSummary: itemDetailSummary,
            itemLines: codingMode == .items ? currentItemDraftLines : []
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                sheetTitleBar
                if !errorMessage.isEmpty {
                    errorBanner
                }
                ScrollView {
                    VStack(spacing: 22) {
                        paperCheckCard
                        bookkeepingPanel
                        secondaryActionsBar
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 980, height: 880)
        .onAppear {
            setup()
            applyHarnessPreviewIfNeeded()
        }
        .onChange(of: selectedBankAccountID) { _ in
            bankAccountText = assetAccounts.first(where: { $0.id == selectedBankAccountID })?.name ?? bankAccountText
            refreshSuggestedCheckNumber()
        }
        .onChange(of: selectedJobID) { _ in
            jobText = jobOptions.first(where: { $0.id == selectedJobID })?.title ?? jobText
        }
        .onChange(of: selectedExpenseAccountID) { _ in
            expenseCategoryText = expenseAccounts.first(where: { $0.id == selectedExpenseAccountID })?.name ?? expenseCategoryText
        }
        .sheet(isPresented: $showTemplatePicker) {
            MemorizedTransactionPickerSheet(
                type: .check,
                payloadType: MemorizedCheckTemplate.self,
                onApply: applyMemorizedTemplate
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveMemorizedTransactionSheet(
                type: .check,
                defaultName: templateDefaultName,
                payloadProvider: { currentMemorizedTemplate }
            )
            .environmentObject(model)
        }
        .alert("Delete Check?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteCheck() }
        } message: {
            Text("This check will be permanently deleted.")
        }
        .accessibilityIdentifier("writeCheck.sheet")
    }

    // MARK: - Title bar

    private var sheetTitleBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Edit Check" : "Write Check")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(titleSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.ink3)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.renaissanceSecondary)
                .controlSize(.small)
            SaveSplitButton(
                isEditing: isEditing,
                canSave: canSave,
                onSaveAndClose: {
                    if saveCheck(printAfterSave: false) { dismiss() }
                },
                onSaveAndNew: isEditing ? nil : {
                    if saveCheck(printAfterSave: false) {
                        selectedVendorID = 0
                        payeeName = ""
                        selectedJobID = 0
                        amount = ""
                        selectedExpenseAccountID = 0
                        expenseCategoryText = ""
                        memo = ""
                        itemLines = [CheckItemEntry()]
                        codingMode = .category
                        errorMessage = ""
                        refreshSuggestedCheckNumber(force: true)
                    }
                }
            )
            .accessibilityIdentifier("writeCheck.saveButton")
            Button("Save & Print") { if saveCheck(printAfterSave: true) { dismiss() } }
                .buttonStyle(.renaissancePrimary)
                .disabled(!canSave)
                .accessibilityIdentifier("writeCheck.saveAndPrintButton")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(
            LinearGradient(
                colors: [AppTheme.surface.opacity(0.96), AppTheme.panel.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border.opacity(0.55)).frame(height: 1)
        }
    }

    private var titleSubtitle: String {
        let company = model.companyInfo.name.isEmpty ? "Your Company Name" : model.companyInfo.name
        let bank = selectedBankAccountName.isEmpty ? "" : " · \(selectedBankAccountName)"
        return "\(company)\(bank)"
    }

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.bad)
            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ink)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(AppTheme.bad.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.bad.opacity(0.25)).frame(height: 1)
        }
    }

    // MARK: - Paper check

    private var paperCheckCard: some View {
        ZStack(alignment: .topLeading) {
            // VOID DRAFT watermark
            Text("VOID DRAFT")
                .font(.system(size: 130, weight: .bold, design: .serif))
                .tracking(8)
                .foregroundStyle(AppTheme.accent.opacity(0.07))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                checkTopRow
                Spacer().frame(height: 28)
                payToRow
                Spacer().frame(height: 16)
                writtenAmountRow
                Spacer().frame(height: 24)
                memoSignatureRow
                Spacer(minLength: 14)
                micrLine
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            // security pattern strip on right edge
            HStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: AppTheme.accent.opacity(0.18), location: 0.0),
                                .init(color: AppTheme.accent.opacity(0.18), location: 0.4),
                                .init(color: .clear, location: 0.4),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .topLeading, endPoint: .topTrailing
                        )
                    )
                    .frame(width: 8)
                    .opacity(0.0) // visual nicety only — leave subtle
            }
            .allowsHitTesting(false)
        }
        .frame(width: 880, height: 400)
        .background(
            ZStack {
                AppTheme.paper
                // ruled-paper fiber lines
                GeometryReader { geo in
                    Path { path in
                        let lineSpacing: CGFloat = 32
                        var y: CGFloat = lineSpacing
                        while y < geo.size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            y += lineSpacing
                        }
                    }
                    .stroke(AppTheme.accent.opacity(0.05), lineWidth: 1)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.18), radius: 14, x: 0, y: 6)
    }

    private var checkTopRow: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.companyInfo.name.isEmpty ? "Your Company Name" : model.companyInfo.name)
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.ink)
                if !model.companyInfo.address1.isEmpty || !model.companyInfo.cityStateZip.isEmpty {
                    Text(addressLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.ink2)
                }
                if !model.companyInfo.phone.isEmpty {
                    Text(model.companyInfo.phone)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.ink2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                HStack(spacing: 10) {
                    Text("CHECK")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2.6)
                        .foregroundStyle(AppTheme.ink3)
                    Text("No.")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                    TextField("", text: $checkNumber)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 70)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(AppTheme.ink.opacity(0.4)).frame(height: 1)
                        }
                        .accessibilityIdentifier("writeCheck.checkNumberField")
                }
                HStack(spacing: 8) {
                    Text("DATE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2.6)
                        .foregroundStyle(AppTheme.ink3)
                    DatePicker("", selection: $checkDate, displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .font(.system(size: 14, design: .monospaced))
                        .frame(width: 130)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(AppTheme.ink.opacity(0.55)).frame(height: 1)
                        }
                }
            }
            .frame(width: 260, alignment: .trailing)
        }
    }

    private var addressLine: String {
        let parts = [model.companyInfo.address1, model.companyInfo.cityStateZip]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var payToRow: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PAY TO THE ORDER OF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(AppTheme.ink3)
                AutocompleteSelectionField(
                    placeholder: "",
                    text: $payeeName,
                    selectedID: $selectedVendorID,
                    options: vendorOptions,
                    allowsCustomValue: true,
                    accessibilityID: "writeCheck.payeeField"
                )
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.ink).frame(height: 1)
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink2)
                    CalcStringField(text: $amount, placeholder: "0.00")
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("writeCheck.amountField")
                }
                .padding(.horizontal, 14)
                .frame(width: 200, height: 46)
                .background(AppTheme.cardFillSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.ink.opacity(0.55), lineWidth: 1)
                )
            }
        }
    }

    private var writtenAmountRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(amountInWords(amountValue))
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(AppTheme.ink)
                Rectangle()
                    .fill(AppTheme.ink.opacity(0.35))
                    .frame(height: 1)
                    .padding(.bottom, 5)
            }
            .padding(.horizontal, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.ink).frame(height: 1)
            }
            Text("DOLLARS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.6)
                .foregroundStyle(AppTheme.ink3)
                .padding(.bottom, 4)
        }
    }

    private var memoSignatureRow: some View {
        HStack(alignment: .bottom, spacing: 30) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MEMO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(AppTheme.ink3)
                TextField("", text: $memo)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .foregroundStyle(AppTheme.ink2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AppTheme.ink.opacity(0.55)).frame(height: 1)
                    }
                    .accessibilityIdentifier("writeCheck.memoField")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.companyInfo.name.isEmpty ? "Your Company Name" : model.companyInfo.name)
                    .font(.system(size: 18, design: .serif))
                    .italic()
                    .foregroundStyle(AppTheme.ink.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AppTheme.ink.opacity(0.55)).frame(height: 1)
                    }
                Text("AUTHORIZED SIGNATURE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
    }

    private var micrLine: some View {
        Text("⑆123456789⑆ ⑈000000000⑈ \(checkNumber.isEmpty ? "—" : checkNumber)")
            .font(.system(size: 14, design: .monospaced))
            .tracking(2.4)
            .foregroundStyle(AppTheme.ink)
            .padding(.leading, 30)
    }

    // MARK: - Bookkeeping panel ("Not on the check")

    private var bookkeepingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOT ON THE CHECK")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(AppTheme.accent2)
                    Text("Where it goes in the books")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer()
                Picker("", selection: $codingMode) {
                    ForEach(CheckCodingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityIdentifier("writeCheck.codingModePicker")
            }

            HStack(alignment: .top, spacing: 14) {
                FieldStack(label: "PAY FROM") {
                    AutocompleteSelectionField(
                        placeholder: "Choose bank account",
                        text: $bankAccountText,
                        selectedID: $selectedBankAccountID,
                        options: bankAccountOptions,
                        accessibilityID: "writeCheck.bankAccountField"
                    )
                }
                .frame(maxWidth: .infinity)
                FieldStack(label: "CLASS / JOB") {
                    AutocompleteSelectionField(
                        placeholder: "Optional job",
                        text: $jobText,
                        selectedID: $selectedJobID,
                        options: jobOptions,
                        accessibilityID: "writeCheck.jobField"
                    )
                }
                .frame(maxWidth: .infinity)
            }

            splitsTable

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(splitsBalanced ? AppTheme.ok : AppTheme.warn)
                        .frame(width: 8, height: 8)
                    Text(splitsBalanced ? "Splits balance the check amount" : "Splits don't balance the check amount yet")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ink3)
                }
                Text("·").foregroundStyle(AppTheme.ink3)
                HStack(spacing: 4) {
                    Text("Next check no.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ink3)
                    Text(lastSuggestedCheckNumber.isEmpty ? "—" : lastSuggestedCheckNumber)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.ink2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 880, alignment: .leading)
        .background(AppTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var splitsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(codingMode == .items ? "ITEM" : "EXPENSE ACCOUNT")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(codingMode == .items ? "DESCRIPTION" : "MEMO")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if codingMode == .items {
                    Text("QTY × RATE").frame(width: 130, alignment: .leading)
                } else {
                    Text("JOB").frame(width: 110, alignment: .leading)
                }
                Text("AMOUNT").frame(width: 110, alignment: .trailing)
                Spacer().frame(width: 28)
            }
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(AppTheme.ink3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.panel.opacity(0.45))
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.hairline).frame(height: 1)
            }

            if codingMode == .items {
                ForEach($itemLines) { $line in
                    CheckItemEditorRow(
                        line: $line,
                        serviceItems: model.serviceItems,
                        onDelete: {
                            itemLines.removeAll { $0.id == line.id }
                            if itemLines.isEmpty {
                                itemLines = [CheckItemEntry()]
                            }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AppTheme.hairline).frame(height: 1)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    AutocompleteSelectionField(
                        placeholder: "Type a category",
                        text: $expenseCategoryText,
                        selectedID: $selectedExpenseAccountID,
                        options: expenseAccountOptions,
                        accessibilityID: "writeCheck.categoryField"
                    )
                    .frame(maxWidth: .infinity)
                    Text(memo.isEmpty ? "—" : memo)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(jobText.isEmpty ? "—" : jobText)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ink3)
                        .frame(width: 110, alignment: .leading)
                        .lineLimit(1)
                    Text(amountValue > 0 ? formatExpense(amountValue) : "—")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 110, alignment: .trailing)
                    Spacer().frame(width: 28)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.hairline).frame(height: 1)
                }
            }

            HStack(spacing: 0) {
                if codingMode == .items {
                    Button {
                        itemLines.append(CheckItemEntry())
                    } label: {
                        Text("+ Add item line")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppTheme.accent2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("writeCheck.addItemLineButton")
                } else {
                    Text("Single posting account")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                Text("TOTAL")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.ink3)
                    .frame(width: 110, alignment: .trailing)
                Text(formatExpense(effectiveAmountValue))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 110, alignment: .trailing)
                    .padding(.leading, 6)
                Spacer().frame(width: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.canvas.opacity(0.5))
        }
        .background(AppTheme.cardFillSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var splitsBalanced: Bool {
        switch codingMode {
        case .category:
            return amountValue > 0
        case .items:
            return itemTotal > 0
        }
    }

    // MARK: - Secondary actions

    private var secondaryActionsBar: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button("Delete") { showDeleteConfirm = true }
                    .foregroundStyle(AppTheme.bad)
            }
            Spacer()
            Button("Use Template") { showTemplatePicker = true }
                .buttonStyle(.renaissanceSecondary)
                .accessibilityIdentifier("writeCheck.useTemplateButton")
            Button("Memorize") { showSaveTemplate = true }
                .buttonStyle(.renaissanceSecondary)
                .disabled(currentMemorizedTemplate == nil)
                .accessibilityIdentifier("writeCheck.memorizeButton")
            Button("Email QB File") { emailCheckDraft() }
                .buttonStyle(.renaissanceSecondary)
                .disabled(!canSave)
                .accessibilityIdentifier("writeCheck.emailButton")
        }
        .frame(width: 880)
        .font(.system(size: 12))
    }

    private var currentMemorizedTemplate: MemorizedCheckTemplate? {
        guard !trimmedPayeeName.isEmpty else { return nil }
        return MemorizedCheckTemplate(
            vendorID: selectedVendorID,
            payeeName: trimmedPayeeName,
            jobID: selectedJobID,
            codingMode: codingMode,
            expenseAccountID: selectedExpenseAccountID,
            bankAccountID: selectedBankAccountID,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultAmount: codingMode == .items ? itemTotal : amountValue,
            itemLines: codingMode == .items ? currentItemDraftLines : []
        )
    }

    private func setup() {
        codingMode = model.checkWorkflowSettings.defaultCodingMode

        if let expense {
            let formatter = DateFormatter.isoDate
            checkDate = formatter.date(from: expense.expenseDate) ?? Date()
            selectedVendorID = expense.vendorID
            selectedJobID = expense.jobID
            payeeName = expense.displayVendorName
            amount = String(format: "%.2f", expense.amount)
            selectedExpenseAccountID = expense.accountID
            selectedBankAccountID = expense.paymentAccountID
            expenseCategoryText = expenseAccounts.first(where: { $0.id == expense.accountID })?.name ?? ""
            bankAccountText = assetAccounts.first(where: { $0.id == expense.paymentAccountID })?.name ?? ""
            jobText = expense.jobName
            checkNumber = expense.checkNumber
            memo = editableMemo(expense.memo)
            if let existingItemLines = try? model.db.fetchExpenseCheckItemLines(expenseID: expense.id), !existingItemLines.isEmpty {
                codingMode = .items
                itemLines = existingItemLines.map {
                    CheckItemEntry(
                        selectedItemID: $0.serviceItemID,
                        itemName: $0.itemName,
                        description: $0.description,
                        quantity: String(format: "%.2f", $0.quantity),
                        rate: String(format: "%.2f", $0.rate)
                    )
                }
            }
        } else {
            if model.checkWorkflowSettings.defaultBankAccountID != 0,
               let account = assetAccounts.first(where: { $0.id == model.checkWorkflowSettings.defaultBankAccountID }) {
                selectedBankAccountID = account.id
                bankAccountText = account.name
            } else if let checking = assetAccounts.first(where: { $0.name.lowercased().contains("checking") }) ?? assetAccounts.first {
                selectedBankAccountID = checking.id
                bankAccountText = checking.name
            }
            refreshSuggestedCheckNumber(force: true)
        }
    }

    private func applyHarnessPreviewIfNeeded() {
        guard !appliedHarnessPreview,
              let query = model.consumePendingPreviewWriteCheckPayeeQuery()
        else { return }
        appliedHarnessPreview = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        appendHarnessLog("write-check preview query consumed='\(trimmed)'")
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            selectedVendorID = 0
            payeeName = trimmed
            appendHarnessLog("write-check preview applied payee='\(payeeName)'")
        }
    }

    private func refreshSuggestedCheckNumber(force: Bool = false) {
        guard selectedBankAccountID != 0 else {
            if force {
                checkNumber = ""
                lastSuggestedCheckNumber = ""
            }
            return
        }

        let suggested = model.nextCheckNumber(paymentAccountID: selectedBankAccountID)
        if force || checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checkNumber == lastSuggestedCheckNumber {
            checkNumber = suggested
        }
        lastSuggestedCheckNumber = suggested
    }

    private func applyMemorizedTemplate(_ template: MemorizedCheckTemplate) {
        selectedVendorID = template.vendorID
        payeeName = template.payeeName
        selectedJobID = template.jobID
        selectedExpenseAccountID = template.expenseAccountID
        selectedBankAccountID = template.bankAccountID
        codingMode = template.codingMode
        memo = template.memo
        if codingMode == .items {
            itemLines = template.itemLines.isEmpty
                ? [CheckItemEntry()]
                : template.itemLines.map {
                    CheckItemEntry(
                        selectedItemID: $0.serviceItemID,
                        itemName: $0.itemName,
                        description: $0.description,
                        quantity: String(format: "%.2f", $0.quantity),
                        rate: String(format: "%.2f", $0.rate)
                    )
                }
        } else {
            amount = template.defaultAmount > 0 ? String(format: "%.2f", template.defaultAmount) : amount
        }
        bankAccountText = assetAccounts.first(where: { $0.id == selectedBankAccountID })?.name ?? bankAccountText
        expenseCategoryText = expenseAccounts.first(where: { $0.id == selectedExpenseAccountID })?.name ?? expenseCategoryText
        jobText = jobOptions.first(where: { $0.id == selectedJobID })?.title ?? jobText
        refreshSuggestedCheckNumber()
    }

    private func saveCheck(printAfterSave: Bool) -> Bool {
        guard !trimmedPayeeName.isEmpty else {
            errorMessage = "Enter the payee name."
            return false
        }
        guard selectedExpenseAccountID != 0 else {
            errorMessage = codingMode == .items
                ? "Choose the posting account for this itemized check."
                : "Choose the expense category for this check."
            return false
        }
        guard selectedBankAccountID != 0 else {
            errorMessage = "Choose the bank account this check is drawn from."
            return false
        }
        guard !checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter or accept the suggested check number."
            return false
        }
        if codingMode == .category && amountValue <= 0 {
            errorMessage = "Enter a valid amount greater than zero."
            return false
        }
        if codingMode == .items && currentItemDraftLines.isEmpty {
            errorMessage = "Add at least one item line with an amount."
            return false
        }

        let vendorID: Int64? = selectedVendorID == 0 ? nil : selectedVendorID
        let jobID: Int64? = selectedJobID == 0 ? nil : selectedJobID
        let itemDrafts = codingMode == .items ? currentItemDraftLines : []

        do {
            let expenseID: Int64
            if let expense {
                try model.db.updateExpense(
                    id: expense.id,
                    vendorNameOverride: trimmedPayeeName,
                    vendorID: vendorID,
                    expenseDate: currentDraft.expenseDate,
                    amount: effectiveAmountValue,
                    accountID: selectedExpenseAccountID,
                    paymentAccountID: selectedBankAccountID,
                    checkNumber: currentDraft.checkNumber,
                    memo: resolvedMemoForSave(editedMemo: currentDraft.memo, originalRawMemo: expense.memo),
                    jobID: jobID
                )
                expenseID = expense.id
            } else {
                expenseID = try model.db.insertExpense(
                    vendorNameOverride: trimmedPayeeName,
                    vendorID: vendorID,
                    expenseDate: currentDraft.expenseDate,
                    amount: effectiveAmountValue,
                    accountID: selectedExpenseAccountID,
                    paymentAccountID: selectedBankAccountID,
                    checkNumber: currentDraft.checkNumber,
                    memo: currentDraft.memo,
                    jobID: jobID
                )
            }

            try model.db.replaceExpenseCheckItemLines(expenseID: expenseID, lines: itemDrafts)

            if printAfterSave {
                printCheck(currentDraft, companyInfo: model.companyInfo, workflowSettings: model.checkWorkflowSettings)
            }
            onSave()
            return true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func deleteCheck() {
        guard let expense else { return }
        do {
            try model.db.deleteExpense(id: expense.id)
            onSave()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func emailCheckDraft() {
        do {
            let iifURL = try QuickBooksIIFExportService.writeCheckIIF(draft: currentDraft)
            var attachments = [iifURL]
            if let pdfURL = try? PDFExportService.writePDF(
                fileName: "Check-\(currentDraft.checkNumber.isEmpty ? "Draft" : currentDraft.checkNumber).pdf",
                view: CheckPrintView(
                    draft: currentDraft,
                    companyInfo: model.companyInfo,
                    workflowSettings: model.checkWorkflowSettings
                )
            ) {
                attachments.append(pdfURL)
            }
            try FileShareService.emailFiles(
                fileURLs: attachments,
                subject: "Check \(currentDraft.checkNumber.isEmpty ? "Draft" : currentDraft.checkNumber) - QuickBooks IIF"
            )
        } catch {
            errorMessage = "Email failed: \(error.localizedDescription)"
        }
    }
}

private struct FieldStack<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(AppTheme.ink3)
            content()
        }
    }
}

private struct CheckItemEditorRow: View {
    @Binding var line: CheckItemEntry
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
                allowsCustomValue: true
            ) { option in
                applySelectedItem(option.id)
            }
            .frame(width: 120)

            TextField("Description", text: $line.description)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            CalcStringField(text: $line.quantity, placeholder: "1")
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)

            CalcStringField(text: $line.rate, placeholder: "0.00")
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)

            Text(formatExpense(line.amount))
                .frame(width: 90, alignment: .trailing)
                .font(.system(size: 12, design: .monospaced))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func applySelectedItem(_ itemID: Int64) {
        guard itemID != 0, let item = serviceItems.first(where: { $0.id == itemID }) else { return }
        line.applyItemDefaults(
            itemID: item.id,
            itemName: item.name,
            defaultDescription: item.description.isEmpty ? item.name : item.description,
            defaultRate: item.unitPrice
        )
    }
}

struct ExpenseSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let expense: ExpenseRow?
    var onSave: () -> Void

    @State private var expenseDate = Date()
    @State private var selectedVendorID: Int64 = 0
    @State private var selectedJobID: Int64 = 0
    @State private var vendorName = ""
    @State private var amount = ""
    @State private var selectedAccountID: Int64 = 0
    @State private var selectedPaymentAccountID: Int64 = 0
    @State private var categoryNameText = ""
    @State private var paymentAccountNameText = ""
    @State private var jobText = ""
    @State private var checkNumber = ""
    @State private var memo = ""
    @State private var errorMessage = ""
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var expenseAccounts: [AccountRow] { model.accounts.filter { $0.type == "expense" } }
    private var assetAccounts: [AccountRow] { model.accounts.filter { $0.type == "asset" } }
    private var jobOptions: [AutocompleteOption] {
        model.jobs
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
            .map {
                AutocompleteOption(
                    id: $0.id,
                    title: $0.displayLabel,
                    subtitle: $0.siteAddress,
                    completionText: $0.displayLabel
                )
            }
    }
    private var vendorOptions: [AutocompleteOption] {
        model.vendors.map {
            let subtitle = [$0.displayDetail, $0.company]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " - ")
            return AutocompleteOption(
                id: $0.id,
                title: $0.displayName,
                subtitle: subtitle,
                completionText: $0.displayName
            )
        }
    }
    private var expenseAccountOptions: [AutocompleteOption] {
        expenseAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }
    private var paymentAccountOptions: [AutocompleteOption] {
        assetAccounts.map {
            AutocompleteOption(id: $0.id, title: $0.name, subtitle: $0.number, completionText: $0.name)
        }
    }
    private var isEditing: Bool { expense != nil }
    private var amountValue: Double { parseCurrencyAmount(amount) }
    private var trimmedVendorName: String { vendorName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isCheck: Bool { !checkNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canPrintCheck: Bool {
        isCheck
        && !trimmedVendorName.isEmpty
        && amountValue > 0
        && selectedPaymentAccountID != 0
    }
    private var formTitle: String {
        if isEditing && isCheck { return "Edit Check" }
        if isEditing { return "Edit Expense" }
        return "Add Expense"
    }
    private var currentDraft: CheckDraft {
        CheckDraft(
            payeeName: trimmedVendorName,
            checkNumber: checkNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            expenseDate: DateFormatter.isoDate.string(from: expenseDate),
            amount: amountValue,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryName: expenseAccounts.first(where: { $0.id == selectedAccountID })?.name ?? "",
            bankAccountName: assetAccounts.first(where: { $0.id == selectedPaymentAccountID })?.name ?? "",
            detailSummary: expenseAccounts.first(where: { $0.id == selectedAccountID })?.name ?? ""
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(formTitle)
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                Section("Details") {
                    LabeledContent("Date") { SmartDateField(date: $expenseDate) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vendor / Payee")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        AutocompleteSelectionField(
                            placeholder: "Vendor / Payee *",
                            text: $vendorName,
                            selectedID: $selectedVendorID,
                            options: vendorOptions,
                            allowsCustomValue: true,
                            accessibilityID: "expense.vendorField"
                        )
                    }
                    HStack {
                        Text("Amount *")
                        Spacer()
                        CalcStringField(text: $amount, placeholder: "0.00")
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Categorization") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Job")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        AutocompleteSelectionField(
                            placeholder: "Optional job",
                            text: $jobText,
                            selectedID: $selectedJobID,
                            options: jobOptions,
                            accessibilityID: "expense.jobField"
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        AutocompleteSelectionField(
                            placeholder: "Type a category",
                            text: $categoryNameText,
                            selectedID: $selectedAccountID,
                            options: expenseAccountOptions,
                            accessibilityID: "expense.categoryField"
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Paid From")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        AutocompleteSelectionField(
                            placeholder: "Type a bank account",
                            text: $paymentAccountNameText,
                            selectedID: $selectedPaymentAccountID,
                            options: paymentAccountOptions,
                            accessibilityID: "expense.paymentAccountField"
                        )
                    }
                    TextField("Check # (if applicable)", text: $checkNumber)
                        .font(.system(.body, design: .monospaced))
                    TextField("Memo", text: $memo)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(AppTheme.bad)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                if isEditing {
                    Button("Delete") { showDeleteConfirm = true }
                        .foregroundStyle(AppTheme.bad)
                }
                Button("Cancel") { dismiss() }
                Spacer()
                if canPrintCheck {
                    Button("Email QB File") {
                        emailCheckDraft()
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("expense.emailButton")
                    Button("Print Check") {
                        printCheck(currentDraft, companyInfo: model.companyInfo)
                    }
                    .buttonStyle(.renaissanceSecondary)
                }
                Button(isEditing ? "Save Changes" : "Save Expense") {
                    saveExpense(printAfterSave: false)
                }
                .buttonStyle(.renaissancePrimary)
                .disabled(trimmedVendorName.isEmpty || amountValue <= 0)
                .accessibilityIdentifier("expense.saveButton")
                if canPrintCheck {
                    Button(isEditing ? "Save & Print" : "Save & Print Check") {
                        saveExpense(printAfterSave: true)
                    }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("expense.saveAndPrintButton")
                }
            }
            .padding()
        }
        .frame(width: 500, height: 560)
        .onAppear { setup() }
        .onChange(of: selectedAccountID) { _ in
            categoryNameText = expenseAccounts.first(where: { $0.id == selectedAccountID })?.name ?? categoryNameText
        }
        .onChange(of: selectedJobID) { _ in
            jobText = jobOptions.first(where: { $0.id == selectedJobID })?.title ?? jobText
        }
        .onChange(of: selectedPaymentAccountID) { _ in
            paymentAccountNameText = assetAccounts.first(where: { $0.id == selectedPaymentAccountID })?.name ?? paymentAccountNameText
        }
        .alert("Delete Expense?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteExpense() }
        } message: {
            Text("This expense will be permanently deleted.")
        }
        .accessibilityIdentifier(isEditing ? "expense.editSheet" : "expense.newSheet")
    }

    private func setup() {
        if let expense {
            let formatter = DateFormatter.isoDate
            expenseDate = formatter.date(from: expense.expenseDate) ?? Date()
            selectedVendorID = expense.vendorID
            selectedJobID = expense.jobID
            vendorName = expense.displayVendorName
            amount = String(format: "%.2f", expense.amount)
            selectedAccountID = expense.accountID
            selectedPaymentAccountID = expense.paymentAccountID
            jobText = expense.jobName
            categoryNameText = expenseAccounts.first(where: { $0.id == expense.accountID })?.name ?? ""
            paymentAccountNameText = assetAccounts.first(where: { $0.id == expense.paymentAccountID })?.name ?? ""
            checkNumber = expense.checkNumber
            memo = editableMemo(expense.memo)
        } else if let checking = assetAccounts.first(where: { $0.name.lowercased().contains("checking") }) ?? assetAccounts.first {
            selectedPaymentAccountID = checking.id
            paymentAccountNameText = checking.name
        }
    }

    private func emailCheckDraft() {
        do {
            let iifURL = try QuickBooksIIFExportService.writeCheckIIF(draft: currentDraft)
            var attachments = [iifURL]
            if let pdfURL = try? PDFExportService.writePDF(
                fileName: "Check-\(currentDraft.checkNumber.isEmpty ? "Draft" : currentDraft.checkNumber).pdf",
                view: CheckPrintView(
                    draft: currentDraft,
                    companyInfo: model.companyInfo,
                    workflowSettings: model.checkWorkflowSettings
                )
            ) {
                attachments.append(pdfURL)
            }
            try FileShareService.emailFiles(
                fileURLs: attachments,
                subject: "Check \(currentDraft.checkNumber.isEmpty ? "Draft" : currentDraft.checkNumber) - QuickBooks IIF"
            )
        } catch {
            errorMessage = "Email failed: \(error.localizedDescription)"
        }
    }

    private func saveExpense(printAfterSave: Bool) {
        guard amountValue > 0 else {
            errorMessage = "Enter a valid amount greater than zero."
            return
        }
        guard !trimmedVendorName.isEmpty else {
            errorMessage = "Enter the vendor or payee name."
            return
        }
        guard selectedAccountID != 0 else {
            errorMessage = "Pick an expense category — every expense must post to a category."
            return
        }
        guard selectedPaymentAccountID != 0 else {
            errorMessage = "Pick the bank or credit account this expense was paid from."
            return
        }

        let vendorID: Int64? = selectedVendorID == 0 ? nil : selectedVendorID
        let accountID: Int64? = selectedAccountID == 0 ? nil : selectedAccountID
        let paymentAccountID: Int64? = selectedPaymentAccountID == 0 ? nil : selectedPaymentAccountID

        do {
            if let expense {
                try model.db.updateExpense(
                    id: expense.id,
                    vendorNameOverride: trimmedVendorName,
                    vendorID: vendorID,
                    expenseDate: currentDraft.expenseDate,
                    amount: amountValue,
                    accountID: accountID,
                    paymentAccountID: paymentAccountID,
                    checkNumber: currentDraft.checkNumber,
                    memo: resolvedMemoForSave(editedMemo: currentDraft.memo, originalRawMemo: expense.memo),
                    jobID: selectedJobID == 0 ? nil : selectedJobID
                )
            } else {
                _ = try model.db.insertExpense(
                    vendorNameOverride: trimmedVendorName,
                    vendorID: vendorID,
                    expenseDate: currentDraft.expenseDate,
                    amount: amountValue,
                    accountID: accountID,
                    paymentAccountID: paymentAccountID,
                    checkNumber: currentDraft.checkNumber,
                    memo: currentDraft.memo,
                    jobID: selectedJobID == 0 ? nil : selectedJobID
                )
            }
            if printAfterSave && canPrintCheck {
                printCheck(currentDraft, companyInfo: model.companyInfo, workflowSettings: model.checkWorkflowSettings)
            }
            onSave()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func deleteExpense() {
        guard let expense else { return }
        do {
            try model.db.deleteExpense(id: expense.id)
            onSave()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

private func parseCurrencyAmount(_ raw: String) -> Double {
    Double(
        raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    ) ?? 0
}

private func formatExpense(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
