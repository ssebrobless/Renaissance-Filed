import SwiftUI

struct InvoiceTabView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showNewInvoice = false
    @State private var detailInvoice: NativeInvoiceRow?
    @State private var editingInvoice: NativeInvoiceRow?
    @State private var search = ""

    private var filtered: [NativeInvoiceRow] {
        guard !search.isEmpty else { return model.nativeInvoices }
        return model.nativeInvoices.filter {
            $0.invoiceNumber.localizedCaseInsensitiveContains(search)
            || $0.customerName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invoices")
                        .font(.title2.bold())
                    Text("Open any invoice to review, edit, print, or record payment.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("+ New Invoice") { showNewInvoice = true }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("invoices.newButton")
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                Text("Invoice #").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 110, alignment: .leading)
                Text("Customer").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Status").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 80, alignment: .leading)
                Text("Total").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .trailing)
                Text("Balance").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.nativeInvoices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Invoices").font(.title2)
                    Text("Create your first invoice using the button above.").foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { invoice in
                    HStack(spacing: 0) {
                        Text(invoice.invoiceNumber)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 110, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invoice.customerDisplayName)
                            if let detail = invoice.customerDisplayDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(invoice.issueDate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(invoice.status.capitalized)
                            .foregroundStyle(statusColor(invoice.status))
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        Text(formatCurrency(invoice.total))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .trailing)
                        Text(formatCurrency(invoice.balance))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(invoice.balance > 0 ? AppTheme.bad : AppTheme.ok)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("invoice.row.\(invoice.id)")
                    .onTapGesture { detailInvoice = invoice }
                }
                .accessibilityIdentifier("invoices.list")
            }
        }
        .accessibilityIdentifier("invoices.root")
        .onAppear { openHarnessInvoiceIfNeeded() }
        .onChange(of: model.nativeInvoices.count) { _ in
            openHarnessInvoiceIfNeeded()
        }
        .sheet(isPresented: $showNewInvoice) {
            NewInvoiceSheet {
                showNewInvoice = false
                model.refreshNativeInvoices()
            }
            .environmentObject(model)
        }
        .sheet(item: $detailInvoice) { invoice in
            InvoiceDetailSheet(invoice: invoice) {
                detailInvoice = nil
                model.refreshNativeInvoices()
            }
            .environmentObject(model)
        }
        .sheet(item: $editingInvoice) { invoice in
            NewInvoiceSheet(invoice: invoice) {
                editingInvoice = nil
                model.refreshNativeInvoices()
            }
            .environmentObject(model)
        }
    }

    private func openHarnessInvoiceIfNeeded() {
        if detailInvoice == nil,
           let invoiceID = model.peekPendingInvoiceID(),
           let invoice = model.nativeInvoices.first(where: { $0.id == invoiceID }) ?? (try? model.db.fetchInvoice(id: invoiceID)) {
            model.selectedTab = .invoices
            detailInvoice = invoice
            model.clearPendingInvoiceID(invoiceID)
        }

        if editingInvoice == nil,
           let invoiceID = model.peekPendingEditInvoiceID(),
           let invoice = model.nativeInvoices.first(where: { $0.id == invoiceID }) ?? (try? model.db.fetchInvoice(id: invoiceID)) {
            model.selectedTab = .invoices
            editingInvoice = invoice
            model.clearPendingEditInvoiceID(invoiceID)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "paid": return .green
        case "partial": return .orange
        case "void": return .secondary
        default: return .red
        }
    }
}

struct NewInvoiceSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var prefilledCustomerID: Int64 = 0
    var invoice: NativeInvoiceRow? = nil
    var duplicateSource: NativeInvoiceRow? = nil
    var sourceEstimate: EstimateRow? = nil
    var sourceEstimateProgressSelection: EstimateInvoiceProgressSelection = EstimateInvoiceProgressSelection()
    var onSave: () -> Void

    @State private var selectedCustomerID: Int64 = 0
    @State private var customerNameText = ""
    @State private var selectedJobID: Int64 = 0
    @State private var invoiceNumber = ""
    @State private var issueDate = Date()
    @State private var dueDate = Date().addingTimeInterval(30 * 86400)
    @State private var memo = ""
    @State private var lines: [InvoiceLineEntry] = [InvoiceLineEntry()]
    @State private var errorMessage = ""
    @State private var didInitialize = false
    @State private var appliedHarnessPreview = false
    @State private var appliedHarnessManualDescriptionVerification = false
    @State private var harnessManualDescriptionStatus = ""
    @State private var showTemplatePicker = false
    @State private var showSaveTemplate = false
    @Environment(\.dismiss) private var dismiss

    private var total: Double { lines.reduce(0) { $0 + $1.amount } }
    private var trimmedCustomerName: String { customerNameText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        (selectedCustomerID != 0 || !trimmedCustomerName.isEmpty) && total > 0
    }
    private var customerOptions: [AutocompleteOption] {
        model.customers.map {
            let subtitle = $0.company.isEmpty ? "" : $0.company
            return AutocompleteOption(
                id: $0.id,
                title: $0.displayLabel,
                subtitle: subtitle,
                completionText: $0.displayLabel
            )
        }
    }
    private var isEditing: Bool { invoice != nil }
    private var isDuplicating: Bool { duplicateSource != nil && invoice == nil }
    private var isConvertingEstimate: Bool { sourceEstimate != nil && invoice == nil }
    private var availableJobs: [JobRow] {
        model.jobs
            .filter { $0.customerID == selectedCustomerID }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }
    private var templateDefaultName: String {
        if let customer = model.customers.first(where: { $0.id == selectedCustomerID }) {
            return "\(customer.displayName) Invoice"
        }
        return "Invoice Template"
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

            if !harnessManualDescriptionStatus.isEmpty {
                Text(harnessManualDescriptionStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(harnessManualDescriptionStatus.hasPrefix("Harness OK") ? AppTheme.ok : AppTheme.bad)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Customer").font(.caption).foregroundStyle(AppTheme.ink3)
                                AutocompleteSelectionField(
                                    placeholder: "Type or pick a customer",
                                    text: $customerNameText,
                                    selectedID: $selectedCustomerID,
                                    options: customerOptions,
                                    allowsCustomValue: true,
                                    accessibilityID: "invoice.customerField"
                                )
                                .frame(width: 320)
                                Text("Type a new name to create the customer on save, or pick existing and edit how it prints.")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                                    .frame(maxWidth: 320, alignment: .leading)
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
                                .accessibilityIdentifier("invoice.jobPicker")
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invoice #").font(.caption).foregroundStyle(AppTheme.ink3)
                                TextField("", text: $invoiceNumber)
                                    .textFieldStyle(.roundedBorder)
                                    .foregroundStyle(.black)
                                    .frame(width: 150)
                                    .accessibilityIdentifier("invoice.numberField")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3)
                                SmartDateField(date: $issueDate)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Due Date").font(.caption).foregroundStyle(AppTheme.ink3)
                                SmartDateField(date: $dueDate)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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
                            LineItemRow(
                                line: $line,
                                rowIndex: index,
                                serviceItems: model.serviceItems
                            ) {
                                if lines.count > 1 {
                                    lines.removeAll { $0.id == $line.wrappedValue.id }
                                }
                            }
                            Divider()
                        }

                        Button("+ Add Line") {
                            lines.append(InvoiceLineEntry())
                        }
                        .accessibilityIdentifier("invoice.addLineButton")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .background(AppTheme.cardFillSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Memo / Notes").font(.caption).foregroundStyle(AppTheme.ink3)
                            TextField("", text: $memo, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(.black)
                                .lineLimit(3)
                                .frame(maxWidth: 300)
                                .accessibilityIdentifier("invoice.memoField")
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            HStack {
                                Text("TOTAL DUE").font(.headline).foregroundStyle(AppTheme.ink3)
                                Text(formatCurrency(total)).font(.title2.bold())
                            }
                            if let invoice, invoice.paid > 0 {
                                HStack {
                                    Text("PAID").font(.caption).foregroundStyle(AppTheme.ink3)
                                    Text(formatCurrency(invoice.paid)).font(.headline)
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("invoice.cancelButton")
                Spacer()
                Button("Use Template") { showTemplatePicker = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("invoice.useTemplateButton")
                Button("Memorize") { showSaveTemplate = true }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(currentMemorizedTemplate == nil)
                    .accessibilityIdentifier("invoice.memorizeButton")
                SaveSplitButton(
                    isEditing: isEditing,
                    canSave: canSave,
                    onSaveAndClose: {
                        if saveInvoice(printAfterSave: false) { dismiss() }
                    },
                    onSaveAndNew: isEditing ? nil : {
                        if saveInvoice(printAfterSave: false) { resetForNewInvoice() }
                    }
                )
                .accessibilityIdentifier("invoice.saveButton")
                Button("Save & Print") { if saveInvoice(printAfterSave: true) { dismiss() } }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(!canSave)
                    .accessibilityIdentifier("invoice.saveAndPrintButton")
            }
            .padding()
            .background(AppTheme.panel)
        }
        .frame(minWidth: 720, idealWidth: 940, minHeight: 560, idealHeight: 620)
        .background(AppTheme.surface)
        .onAppear {
            setup()
            applyHarnessPreviewIfNeeded()
            applyHarnessManualDescriptionVerificationIfNeeded()
        }
        .onChange(of: selectedCustomerID) { _ in
            guard selectedJobID != 0 else { return }
            if !availableJobs.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = 0
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            MemorizedTransactionPickerSheet(
                type: .invoice,
                payloadType: MemorizedInvoiceTemplate.self,
                onApply: applyMemorizedTemplate
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveMemorizedTransactionSheet(
                type: .invoice,
                defaultName: templateDefaultName,
                payloadProvider: { currentMemorizedTemplate }
            )
            .environmentObject(model)
        }
        .accessibilityIdentifier(isEditing ? "invoice.editSheet" : "invoice.newSheet")
    }

    private func setup() {
        guard !didInitialize else { return }
        didInitialize = true

        if let invoice {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = invoice.customerID
            customerNameText = invoice.customerDisplayName
            selectedJobID = invoice.jobID
            invoiceNumber = invoice.invoiceNumber
            issueDate = formatter.date(from: invoice.issueDate) ?? Date()
            dueDate = formatter.date(from: invoice.dueDate) ?? issueDate
            memo = editableMemo(invoice.memo)
            let existingLines = (try? model.db.fetchInvoiceLines(invoiceID: invoice.id)) ?? []
            lines = existingLines.isEmpty
                ? [InvoiceLineEntry()]
                : existingLines.map {
                    InvoiceLineEntry(
                        selectedItemID: 0,
                        description: $0.description,
                        quantity: String(format: "%.2f", $0.quantity),
                        rate: String(format: "%.2f", $0.rate),
                        isDescriptionManuallyEdited: true,
                        isRateManuallyEdited: true
                    )
                }
            return
        }

        if let sourceEstimate {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = sourceEstimate.customerID
            customerNameText = sourceEstimate.customerDisplayName
            selectedJobID = sourceEstimate.jobID
            invoiceNumber = model.nextInvoiceNumber()
            issueDate = Date()
            dueDate = formatter.date(from: sourceEstimate.validUntil) ?? Date().addingTimeInterval(30 * 86400)
            memo = editableMemo(sourceEstimate.memo)
            let existingLines = (try? model.db.fetchEstimateLines(estimateID: sourceEstimate.id)) ?? []
            lines = buildInvoiceLines(
                from: existingLines,
                estimate: sourceEstimate,
                selection: sourceEstimateProgressSelection
            )
            return
        }

        if let duplicateSource {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = duplicateSource.customerID
            customerNameText = duplicateSource.customerDisplayName
            selectedJobID = duplicateSource.jobID
            invoiceNumber = model.nextInvoiceNumber()
            issueDate = Date()
            dueDate = formatter.date(from: duplicateSource.dueDate) ?? Date().addingTimeInterval(30 * 86400)
            memo = editableMemo(duplicateSource.memo)
            let existingLines = (try? model.db.fetchInvoiceLines(invoiceID: duplicateSource.id)) ?? []
            lines = existingLines.isEmpty
                ? [InvoiceLineEntry()]
                : existingLines.map {
                    InvoiceLineEntry(
                        selectedItemID: 0,
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
            if let customer = model.customers.first(where: { $0.id == prefilledCustomerID }) {
                customerNameText = customer.displayLabel
            }
            selectedJobID = 0
        }
        if invoiceNumber.isEmpty {
            invoiceNumber = model.nextInvoiceNumber()
        }
    }

    private func applyHarnessPreviewIfNeeded() {
        guard !appliedHarnessPreview,
              let query = model.consumePendingPreviewInvoiceItemQuery()
        else { return }
        appliedHarnessPreview = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        appendHarnessLog("invoice preview query consumed='\(trimmed)'")
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if lines.isEmpty {
                lines = [InvoiceLineEntry()]
            }
            lines[0].selectedItemID = 0
            lines[0].itemName = trimmed
            appendHarnessLog("invoice preview applied firstLine='\(lines[0].itemName)' lineCount=\(lines.count)")
        }
    }

    private var currentMemorizedTemplate: MemorizedInvoiceTemplate? {
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
        let offsetDays = max(0, Calendar.current.dateComponents([.day], from: issueDate, to: dueDate).day ?? 30)
        return MemorizedInvoiceTemplate(
            customerID: selectedCustomerID,
            jobID: selectedJobID,
            memo: memo,
            dueOffsetDays: offsetDays,
            lines: templateLines
        )
    }

    private func applyMemorizedTemplate(_ template: MemorizedInvoiceTemplate) {
        if template.customerID != 0 {
            selectedCustomerID = template.customerID
        }
        selectedJobID = template.jobID
        memo = template.memo
        dueDate = Calendar.current.date(byAdding: .day, value: template.dueOffsetDays, to: issueDate) ?? dueDate
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

    private func applyHarnessManualDescriptionVerificationIfNeeded() {
        guard !appliedHarnessManualDescriptionVerification,
              model.consumePendingVerifyInvoiceManualDescription()
        else { return }
        appliedHarnessManualDescriptionVerification = true

        let candidateItems = model.serviceItems
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                let leftRank = harnessVerificationPriority(for: $0.name)
                let rightRank = harnessVerificationPriority(for: $1.name)
                if leftRank != rightRank { return leftRank < rightRank }
                if $0.name.count != $1.name.count { return $0.name.count < $1.name.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        guard candidateItems.count >= 2 else {
            harnessManualDescriptionStatus = "Harness FAIL: need at least two service items to verify manual-description protection."
            appendHarnessLog(harnessManualDescriptionStatus)
            return
        }

        let initialCount = lines.count
        lines.append(InvoiceLineEntry())
        let firstIndex = lines.count - 1
        lines[firstIndex].applyItemDefaults(
            itemName: candidateItems[0].name,
            defaultDescription: candidateItems[0].description.isEmpty ? candidateItems[0].name : candidateItems[0].description,
            defaultRate: candidateItems[0].unitPrice
        )

        let autoFilledDescription = lines[firstIndex].description
        let customDescription = "Harness custom description"
        lines[firstIndex].markDescriptionEdited(byUser: customDescription)

        lines.append(InvoiceLineEntry())
        let secondIndex = lines.count - 1
        lines[secondIndex].applyItemDefaults(
            itemName: candidateItems[1].name,
            defaultDescription: candidateItems[1].description.isEmpty ? candidateItems[1].name : candidateItems[1].description,
            defaultRate: candidateItems[1].unitPrice
        )

        let preserved = lines[firstIndex].description == customDescription
        harnessManualDescriptionStatus = preserved
            ? "Harness OK: manual description survived the next-line autofill check."
            : "Harness FAIL: manual description was overwritten after the next-line autofill."

        appendHarnessLog(
            "invoice manual description verification initialCount=\(initialCount) " +
            "autoFilled='\(autoFilledDescription)' preserved=\(preserved)"
        )
    }

    private func harnessVerificationPriority(for name: String) -> Int {
        switch name {
        case "BristowLabor1":
            return 0
        case "BristowLabor2":
            return 1
        default:
            return 2
        }
    }

    private var sheetTitle: String {
        if isEditing { return "Edit Invoice" }
        if isConvertingEstimate { return "Invoice From Estimate (\(sourceEstimateProgressSelection.mode.shortLabel))" }
        if isDuplicating { return "Duplicate Invoice" }
        return "New Invoice"
    }

    private func saveInvoice(printAfterSave: Bool = false) -> Bool {
        let validLines = lines.filter { !$0.description.isEmpty && $0.amount > 0 }
        guard !validLines.isEmpty else {
            errorMessage = "Add at least one line item with description and amount."
            return false
        }

        let trimmedNumber = invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNumber.isEmpty else {
            errorMessage = "Enter an invoice number."
            return false
        }

        let typedName = trimmedCustomerName
        guard selectedCustomerID != 0 || !typedName.isEmpty else {
            errorMessage = "Pick or type a customer."
            return false
        }

        let issueDateStr = DateFormatter.isoDate.string(from: issueDate)
        let dueDateStr = DateFormatter.isoDate.string(from: dueDate)
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
               try model.db.invoiceNumberExists(trimmedNumber, excludingID: invoice?.id) {
                errorMessage = "Invoice number \(trimmedNumber) is already in use. Change the number or turn off duplicate warnings in Settings."
                return false
            }

            // Resolve customer: auto-create if user typed a brand-new name.
            var customerID = selectedCustomerID
            var override = ""
            if customerID == 0 {
                customerID = try model.db.insertCustomer(
                    name: typedName, company: "", primaryContact: "",
                    email: "", phone: "", address: "", city: "", state: "", zip: ""
                )
                model.refreshCustomers()
            } else if let canonical = model.customers.first(where: { $0.id == customerID }) {
                let canonicalLabel = canonical.displayLabel
                if !typedName.isEmpty && typedName != canonicalLabel && typedName != canonical.displayName {
                    override = typedName
                }
            }

            let savedID: Int64
            if let invoice {
                try model.db.updateInvoiceWithLines(
                    id: invoice.id,
                    number: trimmedNumber,
                    customerID: customerID,
                    jobID: selectedJobID == 0 ? nil : selectedJobID,
                    issueDate: issueDateStr,
                    dueDate: dueDateStr,
                    memo: resolvedMemoForSave(editedMemo: memo, originalRawMemo: invoice.memo),
                    total: total,
                    lines: payload,
                    customerNameOverride: override
                )
                savedID = invoice.id
            } else {
                let invoiceID = try model.db.saveInvoiceWithLines(
                    number: trimmedNumber,
                    customerID: customerID,
                    issueDate: issueDateStr,
                    dueDate: dueDateStr,
                    memo: memo,
                    total: total,
                    lines: payload,
                    jobID: selectedJobID == 0 ? nil : selectedJobID,
                    customerNameOverride: override
                )
                if let sourceEstimate {
                    let progressSnapshot = try model.db.fetchEstimateProgressSnapshot(estimateID: sourceEstimate.id)
                    let shouldMarkEstimateConverted = total >= max(0, progressSnapshot.remainingTotal - 0.01)
                    try model.db.linkEstimateToInvoice(
                        estimateID: sourceEstimate.id,
                        invoiceID: invoiceID,
                        mode: sourceEstimateProgressSelection.mode,
                        percentValue: sourceEstimateProgressSelection.mode == .percentOfEstimate ? sourceEstimateProgressSelection.percentValue : 100,
                        shouldMarkEstimateConverted: shouldMarkEstimateConverted,
                        sourceNote: estimateInvoiceSourceNote(
                            selection: sourceEstimateProgressSelection,
                            snapshot: progressSnapshot,
                            invoiceTotal: total
                        )
                    )
                }
                savedID = invoiceID
            }
            if printAfterSave,
               let saved = try model.db.fetchInvoice(id: savedID) {
                let savedLines = (try? model.db.fetchInvoiceLines(invoiceID: savedID)) ?? []
                let payments = (try? model.db.fetchPaymentsForInvoice(invoiceID: savedID)) ?? []
                let printView = InvoicePrintView(invoice: saved, lines: savedLines, payments: payments, companyInfo: model.companyInfo)
                PDFExportService.printView(jobTitle: "Invoice \(saved.invoiceNumber)", view: printView)
            }
            onSave()
            return true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func resetForNewInvoice() {
        selectedCustomerID = 0
        customerNameText = ""
        selectedJobID = 0
        invoiceNumber = model.nextInvoiceNumber()
        issueDate = Date()
        dueDate = Date().addingTimeInterval(30 * 86400)
        memo = ""
        lines = [InvoiceLineEntry()]
        errorMessage = ""
    }

    private func buildInvoiceLines(
        from estimateLines: [EstimateLineRow],
        estimate: EstimateRow,
        selection: EstimateInvoiceProgressSelection
    ) -> [InvoiceLineEntry] {
        if selection.mode == .fullRemaining,
           let remainingDrafts = try? model.db.fetchEstimateRemainingInvoiceDraft(
                estimateID: estimate.id,
                estimateNumber: estimate.estimateNumber,
                existingEstimateLines: estimateLines
           ) {
            let converted = remainingDrafts.map { draft in
                InvoiceLineEntry(
                    selectedItemID: 0,
                    description: draft.description,
                    quantity: String(format: "%.2f", draft.quantity),
                    rate: String(format: "%.2f", draft.rate),
                    isDescriptionManuallyEdited: true,
                    isRateManuallyEdited: true
                )
            }
            return converted.isEmpty ? [InvoiceLineEntry()] : converted
        }

        guard !estimateLines.isEmpty else { return [InvoiceLineEntry()] }

        let chosenLines: [EstimateLineRow]
        switch selection.mode {
        case .fullRemaining, .percentOfEstimate:
            chosenLines = estimateLines
        case .selectedLines:
            let filtered = estimateLines.filter { selection.selectedEstimateLineIDs.contains($0.id) }
            chosenLines = filtered.isEmpty ? estimateLines : filtered
        }

        let percentMultiplier = max(0, selection.percentValue) / 100

        let converted = chosenLines.map { line -> InvoiceLineEntry in
            let adjustedRate: Double
            switch selection.mode {
            case .fullRemaining, .selectedLines:
                adjustedRate = line.rate
            case .percentOfEstimate:
                adjustedRate = line.rate * percentMultiplier
            }

            return InvoiceLineEntry(
                selectedItemID: 0,
                description: line.description,
                quantity: String(format: "%.2f", line.quantity),
                rate: String(format: "%.2f", adjustedRate),
                isDescriptionManuallyEdited: true,
                isRateManuallyEdited: true
            )
        }

        return converted.isEmpty ? [InvoiceLineEntry()] : converted
    }

    private func estimateInvoiceSourceNote(
        selection: EstimateInvoiceProgressSelection,
        snapshot: EstimateProgressSnapshot,
        invoiceTotal: Double
    ) -> String {
        switch selection.mode {
        case .fullRemaining:
            if invoiceTotal >= max(0, snapshot.remainingTotal - 0.01) {
                return "Remaining balance invoiced in full."
            }
            return "Started from remaining balance, then manually adjusted before save."
        case .percentOfEstimate:
            return "Created from \(selection.percentDisplayValue)% of estimate."
        case .selectedLines:
            return "Created from selected estimate lines."
        }
    }
}

struct RecordPaymentSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let invoice: NativeInvoiceRow
    var onSave: () -> Void

    @State private var paymentDate = Date()
    @State private var amount = ""
    @State private var method = "check"
    @State private var reference = ""
    @State private var memo = ""
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    let methods = ["check", "cash", "credit card", "bank transfer", "zelle", "other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Record Payment")
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                Section {
                    LabeledContent("Invoice", value: invoice.invoiceNumber)
                    LabeledContent("Customer", value: invoice.customerDisplayName)
                    LabeledContent("Balance Due", value: formatCurrency(invoice.balance))
                }
                Section("Payment Details") {
                    LabeledContent("Payment Date") { SmartDateField(date: $paymentDate) }
                    HStack {
                        Text("Amount")
                        Spacer()
                        CalcStringField(text: $amount, placeholder: formatCurrency(invoice.balance))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Method", selection: $method) {
                        ForEach(methods, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Check # / Reference", text: $reference)
                    TextField("Memo", text: $memo)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundStyle(AppTheme.bad).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Record Payment") { savePayment() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()
        }
        .frame(width: 400, height: 420)
    }

    private func savePayment() {
        guard let amt = Double(amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")),
              amt > 0 else {
            errorMessage = "Enter a valid amount."
            return
        }
        do {
            try model.db.insertPaymentReceived(
                customerID: invoice.customerID,
                invoiceID: invoice.id,
                paymentDate: DateFormatter.isoDate.string(from: paymentDate),
                amount: amt,
                method: method,
                reference: reference,
                memo: memo
            )
            onSave()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

private struct LineItemRow: View {
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
                accessibilityID: "invoice.line.itemField.\(rowIndex)"
            ) { option in
                applySelectedItem(option.id)
            }
            .frame(width: 130)

            TextField("Description of work or materials", text: descriptionBinding)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("invoice.line.descriptionField.\(rowIndex)")
            CalcStringField(text: $line.quantity, placeholder: "1")
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("invoice.line.quantityField.\(rowIndex)")
            CalcStringField(text: rateBinding, placeholder: "0.00")
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("invoice.line.rateField.\(rowIndex)")
            Text(formatCurrency(line.amount))
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

private func formatCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
