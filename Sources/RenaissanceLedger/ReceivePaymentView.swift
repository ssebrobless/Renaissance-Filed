import SwiftUI

fileprivate func parsePaymentAmount(_ value: String) -> Double {
    Double(
        value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    ) ?? 0
}

fileprivate func formatPaymentAmount(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private struct ReceivePaymentInvoiceDraft: Identifiable, Hashable {
    let id: Int64
    let invoice: NativeInvoiceRow
    var cashApplied: String = ""
    var creditApplied: String = ""
}

struct ReceivePaymentSheet: View {
    @EnvironmentObject private var model: AppViewModel

    var prefilledCustomerID: Int64 = 0
    var prefilledInvoiceID: Int64? = nil
    var onSave: () -> Void

    @State private var selectedCustomerID: Int64 = 0
    @State private var paymentDate = Date()
    @State private var paymentAmount = ""
    @State private var selectedMethod = ""
    @State private var selectedDepositAccountID: Int64 = -1
    @State private var reference = ""
    @State private var memo = ""
    @State private var invoiceDrafts: [ReceivePaymentInvoiceDraft] = []
    @State private var availableCredits: [CustomerCreditRow] = []
    @State private var errorMessage = ""
    @State private var didInitialize = false

    @Environment(\.dismiss) private var dismiss

    private var paymentMethodOptions: [String] {
        var options: [String] = []
        let candidates = model.paymentMethods.map(\.name) + [
            model.paymentWorkflowSettings.defaultPaymentMethodName,
            "Check",
            "Cash",
            "Credit Card",
            "Bank Transfer",
            "Zelle",
            "Other"
        ]

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !options.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                options.append(trimmed)
            }
        }
        return options
    }

    private var depositAccountOptions: [AccountRow] {
        model.accounts.filter {
            $0.type == "asset" && $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        }
    }

    private var paymentAmountValue: Double {
        parsePaymentAmount(paymentAmount)
    }

    private var totalCashApplied: Double {
        invoiceDrafts.reduce(0) { $0 + parsePaymentAmount($1.cashApplied) }
    }

    private var totalCreditApplied: Double {
        invoiceDrafts.reduce(0) { $0 + parsePaymentAmount($1.creditApplied) }
    }

    private var totalAvailableCredits: Double {
        availableCredits.reduce(0) { $0 + $1.remainingAmount }
    }

    private var unappliedCash: Double {
        paymentAmountValue - totalCashApplied
    }

    private var canSave: Bool { saveBlockReason == nil }

    private var saveBlockReason: String? {
        if selectedCustomerID == 0 {
            return "Pick a customer first."
        }
        if invoiceDrafts.isEmpty {
            return "This customer has no open invoices to apply payment to."
        }
        let appliedAny = invoiceDrafts.contains(where: {
            parsePaymentAmount($0.cashApplied) > 0.01 || parsePaymentAmount($0.creditApplied) > 0.01
        })
        if !appliedAny {
            return "Allocate the payment to one or more open invoices."
        }
        if paymentAmountValue > 0.01 && abs(unappliedCash) > 0.01 {
            let amount = String(format: "$%.2f", abs(unappliedCash))
            if unappliedCash > 0 {
                return "\(amount) unapplied — allocate to an invoice or reduce the payment amount."
            } else {
                return "\(amount) over-allocated — reduce allocations or increase the payment amount."
            }
        }
        if totalCreditApplied > totalAvailableCredits + 0.01 {
            return String(format: "Credit applied ($%.2f) exceeds available credits ($%.2f).",
                          totalCreditApplied, totalAvailableCredits)
        }
        for draft in invoiceDrafts {
            let allocated = parsePaymentAmount(draft.cashApplied) + parsePaymentAmount(draft.creditApplied)
            if allocated > draft.invoice.balance + 0.01 {
                return "Allocation on \(draft.invoice.invoiceNumber) exceeds its balance."
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Receive Payment")
                        .font(.title2.bold())
                    Text("Apply cash and credits to this customer’s open invoices.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.bad)
                        .frame(maxWidth: 320, alignment: .trailing)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerFields
                    invoicesSection
                    availableCreditsSection
                    totalsPanel
                }
                .padding()
            }

            Divider()

            if let reason = saveBlockReason {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(reason).font(.caption)
                    Spacer()
                }
                .foregroundStyle(AppTheme.ink3)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Auto-Fill Allocations") { autoFillAllocations() }
                    .disabled(selectedCustomerID == 0 || invoiceDrafts.isEmpty)
                Button("Receive Payment") { savePayment() }
                    .buttonStyle(.renaissancePrimary)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 920, height: 680)
        .onAppear { setup() }
        .onChange(of: selectedCustomerID) { _ in
            guard didInitialize else { return }
            loadCustomerContext(preserveExistingValues: false)
        }
        .onChange(of: paymentAmount) { _ in
            guard didInitialize, model.paymentWorkflowSettings.autoApplyPaymentsToOldestOpenInvoices else { return }
            autoFillAllocations()
        }
        .accessibilityIdentifier("payments.receiveSheet")
    }

    private var headerFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Customer")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedCustomerID) {
                        Text("- Select Customer -").tag(Int64(0))
                        ForEach(model.customers) { customer in
                            Text(customer.displayLabel + (customer.company.isEmpty ? "" : " - " + customer.company)).tag(customer.id)
                        }
                    }
                    .frame(width: 300)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment Date")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    SmartDateField(date: $paymentDate)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment Amount")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    CalcStringField(text: $paymentAmount, placeholder: "0.00")
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("payments.amountField")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Method")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedMethod) {
                        ForEach(paymentMethodOptions, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Deposit To")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    Picker("", selection: $selectedDepositAccountID) {
                        Text("Undeposited Funds").tag(Int64(-1))
                        ForEach(depositAccountOptions) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    .frame(width: 220)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reference")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    TextField("Check # / Reference", text: $reference)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Memo")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                    TextField("Memo", text: $memo)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 360)
                }
            }
        }
    }

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Open Invoices")
                    .font(.headline)
                Spacer()
                if selectedCustomerID != 0 {
                    Text("\(invoiceDrafts.count) invoice" + (invoiceDrafts.count == 1 ? "" : "s"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }

            if invoiceDrafts.isEmpty {
                paymentEmptyState("No open invoices for this customer.")
            } else {
                VStack(spacing: 0) {
                    paymentTableHeader([
                        ("Date", 100),
                        ("Invoice #", 120),
                        ("Balance", 120),
                        ("Cash", 120),
                        ("Credit", 120),
                        ("Remaining", 120)
                    ])

                    ForEach(Array(invoiceDrafts.enumerated()), id: \.element.id) { index, draft in
                        let cashApplied = parsePaymentAmount(draft.cashApplied)
                        let creditApplied = parsePaymentAmount(draft.creditApplied)
                        let remaining = max(0, draft.invoice.balance - cashApplied - creditApplied)

                        HStack(spacing: 0) {
                            Text(draft.invoice.issueDate)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            Text(draft.invoice.invoiceNumber)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            Text(paymentCurrency(draft.invoice.balance))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 120, alignment: .trailing)
                            CalcStringField(text: Binding(
                                get: { invoiceDrafts[index].cashApplied },
                                set: { invoiceDrafts[index].cashApplied = $0 }
                            ), placeholder: "0.00")
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("payments.invoice.cash.\(draft.id)")
                            CalcStringField(text: Binding(
                                get: { invoiceDrafts[index].creditApplied },
                                set: { invoiceDrafts[index].creditApplied = $0 }
                            ), placeholder: "0.00")
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("payments.invoice.credit.\(draft.id)")
                            Text(paymentCurrency(remaining))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(remaining > 0.01 ? AppTheme.ink3 : AppTheme.ok)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var availableCreditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Credits")
                    .font(.headline)
                Spacer()
                Text(paymentCurrency(totalAvailableCredits))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(AppTheme.ok)
            }

            if availableCredits.isEmpty {
                paymentEmptyState("No available customer credits.")
            } else {
                VStack(spacing: 0) {
                    paymentTableHeader([
                        ("Date", 100),
                        ("Type", 120),
                        ("Reference", 220),
                        ("Original", 120),
                        ("Remaining", 120)
                    ])

                    ForEach(availableCredits) { credit in
                        HStack(spacing: 0) {
                            Text(credit.creditDate)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            Text(credit.creditType.capitalized)
                                .frame(width: 120, alignment: .leading)
                            Text(credit.reference.isEmpty ? "-" : credit.reference)
                                .frame(width: 220, alignment: .leading)
                            Text(paymentCurrency(credit.amount))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 120, alignment: .trailing)
                            Text(paymentCurrency(credit.remainingAmount))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AppTheme.ok)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .background(AppTheme.canvas)
                .cornerRadius(8)
            }
        }
    }

    private var totalsPanel: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                paymentMetric("Cash Applied", totalCashApplied)
                paymentMetric("Credits Applied", totalCreditApplied, tint: AppTheme.ok)
                paymentMetric("Unapplied Cash", unappliedCash, tint: abs(unappliedCash) > 0.01 ? AppTheme.warn : .secondary)
            }
            .padding()
            .background(AppTheme.surface)
            .cornerRadius(8)
        }
    }

    private func setup() {
        guard !didInitialize else { return }
        didInitialize = true

        selectedCustomerID = prefilledCustomerID
        selectedMethod = defaultPaymentMethod()
        selectedDepositAccountID = defaultDepositAccountID()
        loadCustomerContext(preserveExistingValues: false)

        if let prefilledInvoiceID,
           let match = invoiceDrafts.first(where: { $0.id == prefilledInvoiceID }) {
            paymentAmount = formatPaymentAmount(match.invoice.balance)
            if let index = invoiceDrafts.firstIndex(where: { $0.id == prefilledInvoiceID }) {
                invoiceDrafts[index].cashApplied = formatPaymentAmount(match.invoice.balance)
            }
        } else if model.paymentWorkflowSettings.autoApplyPaymentsToOldestOpenInvoices {
            autoFillAllocations()
        }
    }

    private func loadCustomerContext(preserveExistingValues: Bool) {
        guard selectedCustomerID != 0 else {
            invoiceDrafts = []
            availableCredits = []
            return
        }

        let priorDrafts = Dictionary(uniqueKeysWithValues: invoiceDrafts.map { ($0.id, $0) })
        let invoices = (try? model.db.fetchOpenInvoicesForCustomer(customerID: selectedCustomerID)) ?? []
        availableCredits = (try? model.db.fetchCustomerCredits(customerID: selectedCustomerID)) ?? []
        invoiceDrafts = invoices.map { invoice in
            if preserveExistingValues, let prior = priorDrafts[invoice.id] {
                return ReceivePaymentInvoiceDraft(
                    id: invoice.id,
                    invoice: invoice,
                    cashApplied: prior.cashApplied,
                    creditApplied: prior.creditApplied
                )
            }
            return ReceivePaymentInvoiceDraft(id: invoice.id, invoice: invoice)
        }

        if let prefilledInvoiceID,
           selectedCustomerID == prefilledCustomerID,
           let index = invoiceDrafts.firstIndex(where: { $0.id == prefilledInvoiceID }),
           paymentAmountValue <= 0.01 {
            let balance = invoiceDrafts[index].invoice.balance
            paymentAmount = formatPaymentAmount(balance)
            invoiceDrafts[index].cashApplied = formatPaymentAmount(balance)
        } else if model.paymentWorkflowSettings.autoApplyPaymentsToOldestOpenInvoices {
            autoFillAllocations()
        }
    }

    private func autoFillAllocations() {
        guard !invoiceDrafts.isEmpty else { return }

        var remainingCash = max(0, paymentAmountValue)
        var remainingCredits = model.paymentWorkflowSettings.autoApplyAvailableCredits ? totalAvailableCredits : 0

        for index in invoiceDrafts.indices {
            var invoiceRemaining = invoiceDrafts[index].invoice.balance
            var cashApplied = 0.0
            var creditApplied = 0.0

            if remainingCash > 0.01 {
                cashApplied = min(invoiceRemaining, remainingCash)
                remainingCash -= cashApplied
                invoiceRemaining -= cashApplied
            }

            if remainingCredits > 0.01 {
                creditApplied = min(invoiceRemaining, remainingCredits)
                remainingCredits -= creditApplied
            }

            invoiceDrafts[index].cashApplied = cashApplied > 0.01 ? formatPaymentAmount(cashApplied) : ""
            invoiceDrafts[index].creditApplied = creditApplied > 0.01 ? formatPaymentAmount(creditApplied) : ""
        }
    }

    private func savePayment() {
        errorMessage = ""

        let allocations = invoiceDrafts.map {
            (
                invoiceID: $0.id,
                cashAmount: parsePaymentAmount($0.cashApplied),
                creditAmount: parsePaymentAmount($0.creditApplied),
                balance: $0.invoice.balance
            )
        }

        for allocation in allocations {
            if allocation.cashAmount < 0 || allocation.creditAmount < 0 {
                errorMessage = "Allocations cannot be negative."
                return
            }
            if allocation.cashAmount + allocation.creditAmount > allocation.balance + 0.01 {
                errorMessage = "One or more invoices were over-allocated."
                return
            }
        }

        if paymentAmountValue > 0.01, abs(totalCashApplied - paymentAmountValue) > 0.01 {
            errorMessage = "Cash allocations must match the payment amount."
            return
        }

        if totalCreditApplied > totalAvailableCredits + 0.01 {
            errorMessage = "Applied credits exceed the customer’s available credits."
            return
        }

        let creditApplications = buildCreditApplications(from: allocations)
        guard creditApplications != nil || totalCreditApplied <= 0.01 else {
            errorMessage = "Could not map the requested credits onto available customer credits."
            return
        }

        do {
            _ = try model.db.recordCustomerPayment(
                customerID: selectedCustomerID,
                paymentDate: DateFormatter.isoDate.string(from: paymentDate),
                paymentAmount: paymentAmountValue,
                method: selectedMethod,
                reference: reference,
                memo: memo,
                depositAccountID: selectedDepositAccountID > 0 ? selectedDepositAccountID : nil,
                cashAllocations: allocations.compactMap { allocation in
                    allocation.cashAmount > 0.01 ? (invoiceID: allocation.invoiceID, amount: allocation.cashAmount) : nil
                },
                creditApplications: creditApplications ?? []
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = "Receive payment failed: \(error.localizedDescription)"
        }
    }

    private func buildCreditApplications(
        from allocations: [(invoiceID: Int64, cashAmount: Double, creditAmount: Double, balance: Double)]
    ) -> [(creditID: Int64, invoiceID: Int64, amount: Double)]? {
        var remainingCredits = availableCredits.map { (id: $0.id, remaining: $0.remainingAmount) }
        var applications: [(creditID: Int64, invoiceID: Int64, amount: Double)] = []

        for allocation in allocations where allocation.creditAmount > 0.01 {
            var remainingInvoiceCredit = allocation.creditAmount
            for index in remainingCredits.indices where remainingInvoiceCredit > 0.01 {
                let available = remainingCredits[index].remaining
                guard available > 0.01 else { continue }
                let applied = min(available, remainingInvoiceCredit)
                applications.append((creditID: remainingCredits[index].id, invoiceID: allocation.invoiceID, amount: applied))
                remainingCredits[index].remaining -= applied
                remainingInvoiceCredit -= applied
            }
            if remainingInvoiceCredit > 0.01 {
                return nil
            }
        }

        return applications
    }

    private func defaultPaymentMethod() -> String {
        let saved = model.paymentWorkflowSettings.defaultPaymentMethodName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = paymentMethodOptions.first(where: { $0.caseInsensitiveCompare(saved) == .orderedSame }) {
            return match
        }
        return paymentMethodOptions.first ?? "Check"
    }

    private func defaultDepositAccountID() -> Int64 {
        let settings = model.paymentWorkflowSettings
        if settings.receivePaymentsIntoUndepositedFunds {
            return -1
        }
        if settings.defaultDepositAccountID != 0,
           depositAccountOptions.contains(where: { $0.id == settings.defaultDepositAccountID }) {
            return settings.defaultDepositAccountID
        }
        return depositAccountOptions.first?.id ?? -1
    }

    private func paymentMetric(_ label: String, _ value: Double, tint: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(paymentCurrency(value))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    private func paymentTableHeader(_ columns: [(String, CGFloat)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column.0)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink3)
                    .frame(width: column.1, alignment: column.1 >= 120 ? .trailing : .leading)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
    }

    private func paymentEmptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(AppTheme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.canvas)
            .cornerRadius(8)
    }

    private func paymentCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

struct CustomerCreditSheet: View {
    @EnvironmentObject private var model: AppViewModel

    var prefilledCustomerID: Int64 = 0
    var onSave: () -> Void

    @State private var selectedCustomerID: Int64 = 0
    @State private var creditDate = Date()
    @State private var amount = ""
    @State private var reference = ""
    @State private var creditType = "credit memo"
    @State private var memo = ""
    @State private var errorMessage = ""

    @Environment(\.dismiss) private var dismiss

    private let creditTypeOptions = ["credit memo", "credit", "adjustment"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Customer Credit")
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                Picker("Customer", selection: $selectedCustomerID) {
                    Text("- Select Customer -").tag(Int64(0))
                    ForEach(model.customers) { customer in
                        Text(customer.displayLabel + (customer.company.isEmpty ? "" : " - " + customer.company)).tag(customer.id)
                    }
                }

                LabeledContent("Credit Date") { SmartDateField(date: $creditDate) }

                HStack {
                    Text("Amount")
                    Spacer()
                    CalcStringField(text: $amount, placeholder: "0.00")
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                }

                Picker("Type", selection: $creditType) {
                    ForEach(creditTypeOptions, id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }

                TextField("Reference", text: $reference)
                TextField("Memo", text: $memo)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.bad)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Credit") { saveCredit() }
                    .buttonStyle(.renaissancePrimary)
            }
            .padding()
        }
        .frame(width: 460, height: 460)
        .onAppear {
            if selectedCustomerID == 0 {
                selectedCustomerID = prefilledCustomerID
            }
        }
        .accessibilityIdentifier("payments.creditSheet")
    }

    private func saveCredit() {
        let creditAmount = parsePaymentAmount(amount)
        guard selectedCustomerID != 0 else {
            errorMessage = "Choose a customer first."
            return
        }
        guard creditAmount > 0.01 else {
            errorMessage = "Enter a valid credit amount."
            return
        }

        do {
            _ = try model.db.insertCustomerCredit(
                customerID: selectedCustomerID,
                creditDate: DateFormatter.isoDate.string(from: creditDate),
                amount: creditAmount,
                reference: reference,
                creditType: creditType,
                memo: memo
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = "Could not save customer credit: \(error.localizedDescription)"
        }
    }
}
