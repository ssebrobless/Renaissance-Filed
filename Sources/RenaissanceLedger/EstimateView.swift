import SwiftUI

struct EstimatesView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showNewEstimate = false
    @State private var detailEstimate: EstimateRow?
    @State private var editingEstimate: EstimateRow?
    @State private var reviewOrderSheet: OrderSheetRow?
    @State private var shouldAutoOpenPendingOrderSheetReview = false
    @State private var search = ""

    private var filtered: [EstimateRow] {
        guard !search.isEmpty else { return model.estimates }
        return model.estimates.filter {
            $0.estimateNumber.localizedCaseInsensitiveContains(search)
            || $0.customerName.localizedCaseInsensitiveContains(search)
            || $0.displayMemo.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimates")
                        .font(.title2.bold())
                    Text("Open any row to review details or make changes.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    if model.orderSheetInboxSettings.isEnabled {
                        Text("Watching \(model.orderSheetInboxSettings.folderURL.lastPathComponent) for phone-shared order sheets.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Import From Mac...") { model.importOrderSheetPicker() }
                    .disabled(model.isImportingOrderSheets)
                    .accessibilityIdentifier("estimates.importOrderSheetButton")
                if model.orderSheetInboxSettings.isEnabled {
                    Button("Scan Phone Inbox") {
                        model.scanOrderSheetInboxNow()
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(model.isImportingOrderSheets)
                    .accessibilityIdentifier("estimates.scanPhoneInboxButton")
                }
                if !model.orderSheets.isEmpty {
                    Button("Review Pending (\(model.orderSheets.count))") {
                        startReviewing(model.orderSheets.first)
                    }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(model.isImportingOrderSheets)
                    .accessibilityIdentifier("estimates.reviewOrderSheetsButton")
                }
                Button("+ New Estimate") { showNewEstimate = true }
                    .buttonStyle(.renaissancePrimary)
                    .accessibilityIdentifier("estimates.newButton")
            }
            .padding()

            Divider()

            if !model.orderSheets.isEmpty {
                PendingOrderSheetQueueView(
                    rows: model.orderSheets,
                    onReview: { row in startReviewing(row) },
                    onOpenImage: { row in model.openOrderSheetImage(row) }
                )
                .padding([.horizontal, .top])

                Divider()
            } else if model.orderSheetInboxSettings.isEnabled {
                EmptyOrderSheetQueueView {
                    model.scanOrderSheetInboxNow()
                }
                .padding([.horizontal, .top])

                Divider()
            }

            HStack(spacing: 0) {
                Text("Estimate #").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .leading)
                Text("Customer").font(.caption).foregroundStyle(AppTheme.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Valid Until").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Status").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 100, alignment: .leading)
                Text("Total").font(.caption).foregroundStyle(AppTheme.ink3).frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(AppTheme.surface)

            Divider()

            if model.estimates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.plaintext").font(.system(size: 48)).foregroundStyle(AppTheme.ink3)
                    Text("No Estimates").font(.title2)
                    Text("Create estimates before the job is finalized into an invoice.")
                        .foregroundStyle(AppTheme.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { estimate in
                    HStack(spacing: 0) {
                        Text(estimate.estimateNumber)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(estimate.customerDisplayName)
                            if let detail = estimate.customerDisplayDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(estimate.issueDate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(estimate.validUntil)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(estimate.status.capitalized)
                            .foregroundStyle(estimateStatusColor(estimate.status))
                            .font(.caption.bold())
                            .frame(width: 100, alignment: .leading)
                        Text(estimateCurrency(estimate.total))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("estimate.row.\(estimate.id)")
                    .onTapGesture { detailEstimate = estimate }
                }
                .accessibilityIdentifier("estimates.list")
            }
        }
        .accessibilityIdentifier("estimates.root")
        .onAppear {
            openHarnessEstimateIfNeeded()
            if model.consumePendingReviewFirstOrderSheet() {
                shouldAutoOpenPendingOrderSheetReview = true
            }
            if model.orderSheetInboxSettings.isEnabled {
                model.scanOrderSheetInboxForReview()
            }
            autoOpenPendingOrderSheetReviewIfNeeded()
        }
        .onChange(of: model.estimates.count) { _ in
            openHarnessEstimateIfNeeded()
            autoOpenPendingOrderSheetReviewIfNeeded()
        }
        .onChange(of: model.orderSheets) { _ in
            autoOpenPendingOrderSheetReviewIfNeeded()
        }
        .sheet(isPresented: $showNewEstimate) {
            NewEstimateSheet {
                showNewEstimate = false
                model.refreshEstimates()
            }
            .environmentObject(model)
        }
        .sheet(item: $detailEstimate) { estimate in
            EstimateDetailSheet(estimate: estimate) {
                detailEstimate = nil
                model.refreshEstimates()
            }
            .environmentObject(model)
        }
        .sheet(item: $editingEstimate) { estimate in
            NewEstimateSheet(estimate: estimate) {
                editingEstimate = nil
                model.refreshEstimates()
            }
            .environmentObject(model)
        }
        .sheet(item: $reviewOrderSheet) { orderSheet in
            OrderSheetReviewView(orderSheet: orderSheet) {
                reviewOrderSheet = nil
                model.refreshOrderSheets()
                model.refreshEstimates()
            }
            .environmentObject(model)
        }
    }

    private func openHarnessEstimateIfNeeded() {
        if detailEstimate == nil,
           let estimateID = model.peekPendingEstimateID(),
           let estimate = model.estimates.first(where: { $0.id == estimateID }) ?? (try? model.db.fetchEstimate(id: estimateID)) {
            model.selectedTab = .estimates
            detailEstimate = estimate
            model.clearPendingEstimateID(estimateID)
        }

        if editingEstimate == nil,
           let estimateID = model.peekPendingEditEstimateID(),
           let estimate = model.estimates.first(where: { $0.id == estimateID }) ?? (try? model.db.fetchEstimate(id: estimateID)) {
            model.selectedTab = .estimates
            editingEstimate = estimate
            model.clearPendingEditEstimateID(estimateID)
        }
    }

    private func startReviewing(_ row: OrderSheetRow?) {
        guard let row else { return }
        reviewOrderSheet = row
    }

    private func autoOpenPendingOrderSheetReviewIfNeeded() {
        guard shouldAutoOpenPendingOrderSheetReview, reviewOrderSheet == nil else { return }
        guard let firstPending = model.orderSheets.first else { return }
        shouldAutoOpenPendingOrderSheetReview = false
        reviewOrderSheet = firstPending
    }
}

struct NewEstimateSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var prefilledCustomerID: Int64 = 0
    var estimate: EstimateRow? = nil
    var duplicateSource: EstimateRow? = nil
    var changeOrderSource: EstimateRow? = nil
    var onSave: () -> Void

    @State private var selectedCustomerID: Int64 = 0
    @State private var customerNameText = ""
    @State private var selectedJobID: Int64 = 0
    @State private var estimateNumber = ""
    @State private var issueDate = Date()
    @State private var validUntil = Date().addingTimeInterval(30 * 86400)
    @State private var status = "draft"
    @State private var memo = ""
    @State private var lines: [InvoiceLineEntry] = [InvoiceLineEntry()]
    @State private var errorMessage = ""
    @State private var didInitialize = false
    @State private var appliedHarnessPreview = false
    @State private var showTemplatePicker = false
    @State private var showSaveTemplate = false
    @Environment(\.dismiss) private var dismiss

    private let baseStatusOptions = ["draft", "sent", "accepted", "inactive", "converted", "historical"]
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
    private var isEditing: Bool { estimate != nil }
    private var isDuplicating: Bool { duplicateSource != nil && estimate == nil }
    private var isChangeOrder: Bool { changeOrderSource != nil && estimate == nil }
    private var availableJobs: [JobRow] {
        model.jobs
            .filter { $0.customerID == selectedCustomerID }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }
    private var statusOptions: [String] {
        guard let estimate else { return baseStatusOptions }
        if baseStatusOptions.contains(estimate.status) {
            return baseStatusOptions
        }
        return baseStatusOptions + [estimate.status]
    }
    private var templateDefaultName: String {
        if let customer = model.customers.first(where: { $0.id == selectedCustomerID }) {
            return "\(customer.displayName) Estimate"
        }
        return "Estimate Template"
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
                    if let changeOrderSource {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "link.badge.plus")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Linked to Estimate \(changeOrderSource.estimateNumber)")
                                    .font(.subheadline.weight(.semibold))
                                Text("This creates a new estimate from the existing one while preserving the original and keeping the relationship visible in estimate history.")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink3)
                            }
                        }
                        .padding(12)
                        .background(AppTheme.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

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
                                    accessibilityID: "estimate.customerField"
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
                                .accessibilityIdentifier("estimate.jobPicker")
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Estimate #").font(.caption).foregroundStyle(AppTheme.ink3)
                                TextField("", text: $estimateNumber)
                                    .textFieldStyle(.roundedBorder)
                                    .foregroundStyle(.black)
                                    .frame(width: 160)
                                    .accessibilityIdentifier("estimate.numberField")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date").font(.caption).foregroundStyle(AppTheme.ink3)
                                SmartDateField(date: $issueDate)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Valid Until").font(.caption).foregroundStyle(AppTheme.ink3)
                                SmartDateField(date: $validUntil)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Status").font(.caption).foregroundStyle(AppTheme.ink3)
                                Picker("", selection: $status) {
                                    ForEach(statusOptions, id: \.self) { option in
                                        Text(option.capitalized).tag(option)
                                    }
                                }
                                .frame(width: 140)
                                .accessibilityIdentifier("estimate.statusPicker")
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
                            EstimateLineEditorRow(
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
                        .accessibilityIdentifier("estimate.addLineButton")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .background(AppTheme.cardFillSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(.caption).foregroundStyle(AppTheme.ink3)
                            TextField("", text: $memo, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(.black)
                                .lineLimit(3)
                                .frame(maxWidth: 320)
                                .accessibilityIdentifier("estimate.memoField")
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            HStack {
                                Text("ESTIMATE TOTAL").font(.headline).foregroundStyle(AppTheme.ink3)
                                Text(estimateCurrency(total)).font(.title2.bold())
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
                    .accessibilityIdentifier("estimate.cancelButton")
                Spacer()
                Button("Use Template") { showTemplatePicker = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.useTemplateButton")
                Button("Memorize") { showSaveTemplate = true }
                    .buttonStyle(.renaissanceSecondary)
                    .disabled(currentMemorizedTemplate == nil)
                    .accessibilityIdentifier("estimate.memorizeButton")
                SaveSplitButton(
                    isEditing: isEditing,
                    canSave: canSave,
                    onSaveAndClose: {
                        if saveEstimate(printAfterSave: false) { dismiss() }
                    },
                    onSaveAndNew: isEditing ? nil : {
                        if saveEstimate(printAfterSave: false) { resetForNewEstimate() }
                    }
                )
                .accessibilityIdentifier("estimate.saveButton")
                Button("Save & Print") { if saveEstimate(printAfterSave: true) { dismiss() } }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(!canSave)
                    .accessibilityIdentifier("estimate.saveAndPrintButton")
            }
            .padding()
            .background(AppTheme.panel)
        }
        .frame(minWidth: 720, idealWidth: 960, minHeight: 560, idealHeight: 620)
        .background(AppTheme.surface)
        .onAppear {
            setup()
            applyHarnessPreviewIfNeeded()
        }
        .onChange(of: selectedCustomerID) { _ in
            guard selectedJobID != 0 else { return }
            if !availableJobs.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = 0
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            MemorizedTransactionPickerSheet(
                type: .estimate,
                payloadType: MemorizedEstimateTemplate.self,
                onApply: applyMemorizedTemplate
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveMemorizedTransactionSheet(
                type: .estimate,
                defaultName: templateDefaultName,
                payloadProvider: { currentMemorizedTemplate }
            )
            .environmentObject(model)
        }
        .accessibilityIdentifier(isEditing ? "estimate.editSheet" : "estimate.newSheet")
    }

    private func setup() {
        guard !didInitialize else { return }
        didInitialize = true

        if let estimate {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = estimate.customerID
            customerNameText = estimate.customerDisplayName
            selectedJobID = estimate.jobID
            estimateNumber = estimate.estimateNumber
            issueDate = formatter.date(from: estimate.issueDate) ?? Date()
            validUntil = formatter.date(from: estimate.validUntil) ?? issueDate
            status = estimate.status
            memo = editableMemo(estimate.memo)
            let existingLines = (try? model.db.fetchEstimateLines(estimateID: estimate.id)) ?? []
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

        if let copySource = duplicateSource ?? changeOrderSource {
            let formatter = DateFormatter.isoDate
            selectedCustomerID = copySource.customerID
            customerNameText = copySource.customerDisplayName
            selectedJobID = copySource.jobID
            estimateNumber = model.nextEstimateNumber()
            issueDate = Date()
            validUntil = formatter.date(from: copySource.validUntil) ?? Date().addingTimeInterval(30 * 86400)
            status = "draft"
            memo = editableMemo(copySource.memo)
            if changeOrderSource != nil {
                let linkNote = "Created from Estimate \(copySource.estimateNumber)"
                memo = memo.isEmpty ? linkNote : "\(memo)\n\(linkNote)"
            }
            let existingLines = (try? model.db.fetchEstimateLines(estimateID: copySource.id)) ?? []
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

        if prefilledCustomerID != 0 {
            selectedCustomerID = prefilledCustomerID
            if let customer = model.customers.first(where: { $0.id == prefilledCustomerID }) {
                customerNameText = customer.displayLabel
            }
            selectedJobID = 0
        }
        if estimateNumber.isEmpty {
            estimateNumber = model.nextEstimateNumber()
        }
    }

    private func applyHarnessPreviewIfNeeded() {
        guard !appliedHarnessPreview,
              let query = model.consumePendingPreviewEstimateItemQuery()
        else { return }
        appliedHarnessPreview = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        appendHarnessLog("estimate preview query consumed='\(trimmed)'")
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if lines.isEmpty {
                lines = [InvoiceLineEntry()]
            }
            lines[0].selectedItemID = 0
            lines[0].itemName = trimmed
            appendHarnessLog("estimate preview applied firstLine='\(lines[0].itemName)' lineCount=\(lines.count)")
        }
    }

    private var currentMemorizedTemplate: MemorizedEstimateTemplate? {
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
        return MemorizedEstimateTemplate(
            customerID: selectedCustomerID,
            jobID: selectedJobID,
            memo: memo,
            status: status,
            lines: templateLines
        )
    }

    private func applyMemorizedTemplate(_ template: MemorizedEstimateTemplate) {
        if template.customerID != 0 {
            selectedCustomerID = template.customerID
        }
        selectedJobID = template.jobID
        memo = template.memo
        status = template.status
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
        if isEditing { return "Edit Estimate" }
        if isChangeOrder { return "New Estimate From Existing" }
        if isDuplicating { return "Duplicate Estimate" }
        return "New Estimate"
    }

    private func saveEstimate(printAfterSave: Bool = false) -> Bool {
        let validLines = lines.filter { !$0.description.isEmpty && $0.amount > 0 }
        guard !validLines.isEmpty else {
            errorMessage = "Add at least one line item with description and amount."
            return false
        }

        let trimmedNumber = estimateNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNumber.isEmpty else {
            errorMessage = "Enter an estimate number."
            return false
        }

        let typedName = trimmedCustomerName
        guard selectedCustomerID != 0 || !typedName.isEmpty else {
            errorMessage = "Pick or type a customer."
            return false
        }

        let formatter = DateFormatter.isoDate
        let payload = validLines.map {
            (
                description: $0.description,
                quantity: Double($0.quantity) ?? 1,
                rate: Double($0.rate) ?? 0,
                amount: $0.amount
            )
        }

        do {
            if model.duplicateWarningSettings.warnOnDuplicateEstimateNumbers,
               try model.db.estimateNumberExists(trimmedNumber, excludingID: estimate?.id) {
                errorMessage = "Estimate number \(trimmedNumber) is already in use. Change the number or turn off duplicate warnings in Settings."
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
            if let estimate {
                try model.db.updateEstimateWithLines(
                    id: estimate.id,
                    number: trimmedNumber,
                    customerID: customerID,
                    jobID: selectedJobID == 0 ? nil : selectedJobID,
                    issueDate: formatter.string(from: issueDate),
                    validUntil: formatter.string(from: validUntil),
                    memo: resolvedMemoForSave(editedMemo: memo, originalRawMemo: estimate.memo),
                    total: total,
                    status: status,
                    lines: payload,
                    customerNameOverride: override
                )
                savedID = estimate.id
            } else {
                savedID = try model.db.saveEstimateWithLines(
                    number: trimmedNumber,
                    customerID: customerID,
                    issueDate: formatter.string(from: issueDate),
                    validUntil: formatter.string(from: validUntil),
                    memo: memo,
                    total: total,
                    status: status,
                    lines: payload,
                    jobID: selectedJobID == 0 ? nil : selectedJobID,
                    customerNameOverride: override,
                    sourceEstimateID: changeOrderSource?.id,
                    sourceRelationship: changeOrderSource == nil ? "" : "change_order",
                    sourceNote: changeOrderSource.map { "Created from Estimate \($0.estimateNumber)" } ?? ""
                )
            }
            if printAfterSave,
               let saved = try model.db.fetchEstimate(id: savedID) {
                let savedLines = (try? model.db.fetchEstimateLines(estimateID: savedID)) ?? []
                let printView = EstimatePrintView(estimate: saved, lines: savedLines, companyInfo: model.companyInfo)
                PDFExportService.printView(jobTitle: "Estimate \(saved.estimateNumber)", view: printView)
            }
            onSave()
            return true
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func resetForNewEstimate() {
        selectedCustomerID = 0
        customerNameText = ""
        selectedJobID = 0
        estimateNumber = model.nextEstimateNumber()
        issueDate = Date()
        validUntil = Date().addingTimeInterval(30 * 86400)
        status = "draft"
        memo = ""
        lines = [InvoiceLineEntry()]
        errorMessage = ""
    }
}

struct EstimateDetailSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var onDismiss: () -> Void

    @State private var currentEstimate: EstimateRow
    @State private var lines: [EstimateLineRow] = []
    @State private var progressSnapshot: EstimateProgressSnapshot?
    @State private var showEditSheet = false
    @State private var showDuplicateSheet = false
    @State private var showChangeOrderSheet = false
    @State private var showConvertSheet = false
    @State private var pendingInvoiceProgressSelection = EstimateInvoiceProgressSelection()
    @State private var showConvertInvoiceSheet = false
    @State private var linkedInvoice: NativeInvoiceRow?
    @State private var linkedInvoices: [NativeInvoiceRow] = []
    @State private var sourceEstimateLink: EstimateRevisionLinkRow?
    @State private var childEstimateLinks: [EstimateRevisionLinkRow] = []
    @State private var sourceOrderSheets: [OrderSheetRow] = []
    @State private var didTriggerHarnessEmail = false
    @Environment(\.dismiss) private var dismiss

    init(estimate: EstimateRow, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _currentEstimate = State(initialValue: estimate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimate \(currentEstimate.estimateNumber)")
                        .font(.title2.bold())
                    Text(currentEstimate.customerDisplayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink3)
                    if currentEstimate.hasJob {
                        Text("Job: \(currentEstimate.jobName)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    if let detail = currentEstimate.customerDisplayDetail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
                Spacer()
                Text(estimateStatusLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(estimateStatusBadgeColor.opacity(0.15))
                    .foregroundStyle(estimateStatusBadgeColor)
                    .cornerRadius(6)
                Button("Edit") { showEditSheet = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.editButton")
                Button("Duplicate") { showDuplicateSheet = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.duplicateButton")
                Button("New From") { showChangeOrderSheet = true }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.changeOrderButton")
                Button(isInactiveEstimate ? "Mark Active" : "Mark Inactive") { toggleInactiveEstimate() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.toggleInactiveButton")
                if canConvertToInvoice {
                    Button("Invoice") { showConvertSheet = true }
                        .buttonStyle(.renaissancePrimary)
                        .accessibilityIdentifier("estimate.detail.convertButton")
                }
                if latestLinkedInvoiceID != 0 {
                    Button("Open Invoice") { openLinkedInvoice() }
                        .buttonStyle(.renaissanceSecondary)
                        .accessibilityIdentifier("estimate.detail.openLinkedInvoiceButton")
                }
                Button("Print") { printEstimate() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.printButton")
                Button("Email QB File") { emailEstimate() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.emailButton")
                Button("Done") { dismiss() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("estimate.detail.doneButton")
            }
            .padding()
            .background(AppTheme.panel)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 28) {
                        estimateField("Issue Date", value: currentEstimate.issueDate)
                        estimateField("Valid Until", value: currentEstimate.validUntil)
                        estimateField("Total", value: estimateCurrency(currentEstimate.total))
                        if let progressSnapshot {
                            estimateField("Invoiced", value: estimateCurrency(progressSnapshot.invoicedTotal))
                            estimateField("Remaining", value: estimateCurrency(progressSnapshot.remainingTotal))
                        }
                        if latestLinkedInvoiceID != 0 {
                            estimateField("Linked Invoice", value: "#\(latestLinkedInvoiceID)")
                        }
                    }

                    if sourceEstimateLink != nil || !childEstimateLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("RELATED ESTIMATES")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)

                            if let sourceEstimateLink {
                                relatedEstimateRow(
                                    label: "Based on",
                                    estimate: sourceEstimateLink.estimate,
                                    note: sourceEstimateLink.sourceNote
                                )
                            }

                            ForEach(childEstimateLinks) { link in
                                relatedEstimateRow(
                                    label: "Created from this",
                                    estimate: link.estimate,
                                    note: link.sourceNote
                                )
                                if link.id != childEstimateLinks.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.surface)
                        .cornerRadius(8)
                    }

                    if !currentEstimate.displayMemo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOTES").font(.caption).foregroundStyle(AppTheme.ink3)
                            Text(currentEstimate.displayMemo)
                        }
                    }

                    if !sourceOrderSheets.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SOURCE ORDER SHEETS")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)

                            ForEach(sourceOrderSheets) { sheet in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sheet.originalFilename)
                                            .font(.subheadline.weight(.medium))
                                        Text("Approved from staged order sheet review")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                    Spacer()
                                    Button("Open Source Sheet") {
                                        model.openOrderSheetImage(sheet)
                                    }
                                    .buttonStyle(.renaissanceSecondary)
                                }
                                if sheet.id != sourceOrderSheets.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.surface)
                        .cornerRadius(8)
                    }

                    if !linkedInvoices.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("RELATED INVOICES")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)

                            ForEach(linkedInvoices) { invoice in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Invoice \(invoice.invoiceNumber)")
                                            .font(.subheadline.weight(.medium))
                                        Text("\(invoice.issueDate)  |  \(estimateCurrency(invoice.total))")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                    Spacer()
                                    Text(invoice.status.capitalized)
                                        .font(.caption.bold())
                                        .foregroundStyle(invoice.balance > 0 ? AppTheme.warn : AppTheme.ok)
                                    Button("Open") {
                                        linkedInvoice = invoice
                                    }
                                    .buttonStyle(.renaissanceSecondary)
                                }
                                if invoice.id != linkedInvoices.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.surface)
                        .cornerRadius(8)
                    }

                    if isHistoricalEstimatePlaceholderOnly(lines) {
                        estimateHistoricalDetailGapNotice(
                            title: "Historical estimate detail is not fully backfilled yet.",
                            message: "This imported QuickBooks estimate already has the correct historical total. The remaining gap is only the original line-by-line estimate detail from QuickBooks."
                        )
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
                                    Text(estimateCurrency(line.rate))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 100, alignment: .trailing)
                                    Text(estimateCurrency(line.amount))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 110, alignment: .trailing)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                    .background(AppTheme.cardFillSoft)
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(minWidth: 980, idealWidth: 1100, minHeight: 620, idealHeight: 680)
        .background(AppTheme.surface)
        .onAppear {
            loadData()
            applyHarnessProgressChooserPreviewIfNeeded()
        }
        .onDisappear { onDismiss() }
        .accessibilityIdentifier("estimate.detail.\(currentEstimate.id)")
        .sheet(isPresented: $showEditSheet) {
            NewEstimateSheet(estimate: currentEstimate) {
                showEditSheet = false
                model.refreshEstimates()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showDuplicateSheet) {
            NewEstimateSheet(duplicateSource: currentEstimate) {
                showDuplicateSheet = false
                model.refreshEstimates()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showChangeOrderSheet) {
            NewEstimateSheet(changeOrderSource: currentEstimate) {
                showChangeOrderSheet = false
                model.refreshEstimates()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showConvertSheet) {
            EstimateInvoiceProgressChooserSheet(
                estimate: currentEstimate,
                progress: estimateProgressSnapshot,
                loadLines: { try model.db.fetchEstimateLines(estimateID: currentEstimate.id) },
                onStart: { selection in
                    pendingInvoiceProgressSelection = selection
                    showConvertSheet = false
                    showConvertInvoiceSheet = true
                }
            )
        }
        .sheet(isPresented: $showConvertInvoiceSheet) {
            NewInvoiceSheet(
                prefilledCustomerID: currentEstimate.customerID,
                sourceEstimate: currentEstimate,
                sourceEstimateProgressSelection: pendingInvoiceProgressSelection
            ) {
                showConvertInvoiceSheet = false
                model.refreshEstimates()
                model.refreshNativeInvoices()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(item: $linkedInvoice) { invoice in
            InvoiceDetailSheet(invoice: invoice) {
                linkedInvoice = nil
                model.refreshNativeInvoices()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
    }

    private func applyHarnessProgressChooserPreviewIfNeeded() {
        guard model.consumePendingPreviewEstimateInvoiceProgressChooser() else { return }
        guard canConvertToInvoice else {
            appendHarnessLog("estimate progress chooser preview skipped estimateID=\(currentEstimate.id) remaining=\(estimateProgressSnapshot.remainingTotal)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appendHarnessLog("estimate progress chooser preview opening estimateID=\(currentEstimate.id)")
            showConvertSheet = true
            scheduleHarnessSnapshotIfNeeded(
                path: model.harnessLaunch.snapshotPath,
                delay: max(model.harnessLaunch.snapshotDelaySeconds ?? 0, 1.2)
            )
        }
    }

    private func loadData() {
        if let refreshed = try? model.db.fetchEstimate(id: currentEstimate.id) {
            currentEstimate = refreshed
        }
        lines = (try? model.db.fetchEstimateLines(estimateID: currentEstimate.id)) ?? []
        progressSnapshot = try? model.db.fetchEstimateProgressSnapshot(estimateID: currentEstimate.id)
        linkedInvoices = (try? model.db.fetchEstimateLinkedInvoices(estimateID: currentEstimate.id)) ?? []
        sourceEstimateLink = try? model.db.fetchEstimateRevisionSource(estimateID: currentEstimate.id)
        childEstimateLinks = (try? model.db.fetchEstimateRevisionChildren(estimateID: currentEstimate.id)) ?? []
        sourceOrderSheets = model.fetchLinkedOrderSheets(estimateID: currentEstimate.id)
        scheduleHarnessEmailIfNeeded()
    }

    private func relatedEstimateRow(label: String, estimate: EstimateRow, note: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label): Estimate \(estimate.estimateNumber)")
                    .font(.subheadline.weight(.medium))
                Text("\(estimate.issueDate)  |  \(estimateCurrency(estimate.total))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                if !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }
            Spacer()
            Text(estimate.status.capitalized)
                .font(.caption.bold())
                .foregroundStyle(estimateStatusColor(estimate.status))
        }
    }

    private func scheduleHarnessEmailIfNeeded() {
        guard !didTriggerHarnessEmail, model.consumePendingEmailEstimateOnOpen() else { return }
        didTriggerHarnessEmail = true
        appendHarnessLog("estimate email scheduled for estimate \(currentEstimate.id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            appendHarnessLog("estimate email firing for estimate \(currentEstimate.id)")
            emailEstimate()
        }
    }

    private func estimateField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(AppTheme.ink3)
            Text(value).font(.body.bold())
        }
    }

    private func openLinkedInvoice() {
        guard latestLinkedInvoiceID != 0 else { return }
        linkedInvoice = try? model.db.fetchInvoice(id: latestLinkedInvoiceID)
    }

    private var estimateProgressSnapshot: EstimateProgressSnapshot {
        progressSnapshot ?? .empty(estimateID: currentEstimate.id, estimateTotal: currentEstimate.total)
    }

    private var canConvertToInvoice: Bool {
        !isInactiveEstimate && currentEstimate.status.lowercased() != "void" && estimateProgressSnapshot.hasRemainingBalance
    }

    private var latestLinkedInvoiceID: Int64 {
        if let firstLinkedInvoice = linkedInvoices.first {
            return firstLinkedInvoice.id
        }
        let progressInvoiceID = estimateProgressSnapshot.latestInvoiceID
        if progressInvoiceID != 0 { return progressInvoiceID }
        return currentEstimate.linkedInvoiceID
    }

    private var isInactiveEstimate: Bool {
        currentEstimate.status.lowercased() == "inactive"
    }

    private var estimateStatusLabel: String {
        if isInactiveEstimate {
            return "Inactive"
        }
        if estimateProgressSnapshot.linkedInvoiceCount > 0 && estimateProgressSnapshot.hasRemainingBalance {
            return "Partially Invoiced"
        }
        return currentEstimate.status.capitalized
    }

    private var estimateStatusBadgeColor: Color {
        if isInactiveEstimate {
            return .secondary
        }
        if estimateProgressSnapshot.linkedInvoiceCount > 0 && estimateProgressSnapshot.hasRemainingBalance {
            return .orange
        }
        return estimateStatusColor(currentEstimate.status)
    }

    private func toggleInactiveEstimate() {
        do {
            let nextStatus = isInactiveEstimate ? "draft" : "inactive"
            try model.db.updateEstimateStatus(id: currentEstimate.id, status: nextStatus)
            model.refreshEstimates()
            loadData()
            onDismiss()
        } catch {
            model.statusMessage = "Estimate status update failed: \(error.localizedDescription)"
        }
    }

    private func printEstimate() {
        let printView = EstimatePrintView(estimate: currentEstimate, lines: lines, companyInfo: model.companyInfo)
        PDFExportService.printView(jobTitle: "Estimate \(currentEstimate.estimateNumber)", view: printView)
    }

    private func emailEstimate() {
        let printView = EstimatePrintView(estimate: currentEstimate, lines: lines, companyInfo: model.companyInfo)
        do {
            let iifURL = try QuickBooksIIFExportService.writeEstimateIIF(
                estimate: currentEstimate,
                lines: lines
            )
            var attachments = [iifURL]
            if let pdfURL = try? PDFExportService.writePDF(
                fileName: "Estimate-\(currentEstimate.estimateNumber).pdf",
                view: printView
            ) {
                attachments.append(pdfURL)
            }
            try FileShareService.emailFiles(
                fileURLs: attachments,
                subject: "Estimate \(currentEstimate.estimateNumber) - QuickBooks IIF",
                recipientEmails: customerRecipientEmails(for: currentEstimate.customerID)
            )
        } catch {
            model.statusMessage = "Estimate email failed: \(error.localizedDescription)"
        }
    }

    private func customerRecipientEmails(for customerID: Int64) -> [String] {
        guard let customer = model.customers.first(where: { $0.id == customerID }) else {
            return []
        }
        return FileShareService.normalizedRecipientEmails(from: customer.email)
    }

    private func estimateHistoricalDetailGapNotice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.warn)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

struct EstimateLineEditorRow: View {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AutocompleteSelectionField(
                    placeholder: "Item",
                    text: $line.itemName,
                    selectedID: $line.selectedItemID,
                    options: itemOptions,
                    allowsCustomValue: true,
                    accessibilityID: "estimate.line.itemField.\(rowIndex)"
                ) { option in
                    applySelectedItem(option.id)
                }
                .frame(width: 130)

                TextField("Description of work or materials", text: descriptionBinding)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("estimate.line.descriptionField.\(rowIndex)")
                CalcStringField(text: $line.quantity, placeholder: "1")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("estimate.line.quantityField.\(rowIndex)")
                CalcStringField(text: rateBinding, placeholder: "0.00")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("estimate.line.rateField.\(rowIndex)")
                Text(estimateCurrency(line.amount))
                    .frame(width: 110, alignment: .trailing)
                    .font(.system(size: 13, design: .monospaced))
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(AppTheme.bad)
                }
                .buttonStyle(.plain)
                .frame(width: 22)
            }

            if !line.reviewHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                        .foregroundStyle(AppTheme.warn)
                    Text(line.reviewHint)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 138)
            }
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

func estimateStatusColor(_ status: String) -> Color {
    switch status {
    case "accepted": return .green
    case "sent": return .blue
    case "inactive": return .secondary
    case "converted": return .purple
    case "historical": return .secondary
    default: return .orange
    }
}

func estimateCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
