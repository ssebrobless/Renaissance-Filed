import AppKit
import SwiftUI

struct InvoiceDetailSheet: View {
    @EnvironmentObject private var model: AppViewModel
    var onDismiss: () -> Void

    @State private var currentInvoice: NativeInvoiceRow
    @State private var lines: [InvoiceLineRow] = []
    @State private var payments: [PaymentDetailRow] = []
    @State private var creditApplications: [CreditApplicationDetailRow] = []
    @State private var showPayment = false
    @State private var showEdit = false
    @State private var showDuplicate = false
    @State private var showVoidConfirm = false
    @State private var didTriggerHarnessEmail = false
    @Environment(\.dismiss) private var dismiss

    init(invoice: NativeInvoiceRow, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _currentInvoice = State(initialValue: invoice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invoice \(currentInvoice.invoiceNumber)")
                        .font(.title2.bold())
                    Text(currentInvoice.customerDisplayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink3)
                    if let detail = currentInvoice.customerDisplayDetail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
                Spacer()
                InvoiceStatusBadge(status: currentInvoice.status)
                if currentInvoice.status != "void" {
                    Button("Edit Invoice") { showEdit = true }
                        .accessibilityIdentifier("invoice.detail.editButton")
                }
                Button("Duplicate") { showDuplicate = true }
                    .accessibilityIdentifier("invoice.detail.duplicateButton")
                Button("Done") { closeSheet() }
                    .padding(.leading, 8)
                    .accessibilityIdentifier("invoice.detail.doneButton")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Meta info row
                    HStack(spacing: 28) {
                        labeledField("Issue Date", value: currentInvoice.issueDate)
                        labeledField("Due Date", value: currentInvoice.dueDate)
                        labeledField("Total", value: fmtCurrency(currentInvoice.total))
                        labeledField("Paid", value: fmtCurrency(currentInvoice.paid))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Balance Due").font(.caption).foregroundStyle(AppTheme.ink3)
                            Text(fmtCurrency(currentInvoice.balance))
                                .font(.body.bold())
                                .foregroundStyle(currentInvoice.balance > 0 ? AppTheme.bad : AppTheme.ok)
                        }
                    }

                    if !currentInvoice.displayMemo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MEMO").font(.caption).foregroundStyle(AppTheme.ink3)
                            Text(currentInvoice.displayMemo)
                        }
                    }

                    if isHistoricalInvoicePlaceholderOnly(lines) {
                        historicalDetailGapNotice(
                            title: "Historical invoice detail is not fully backfilled yet.",
                            message: "This imported QuickBooks invoice already has the correct historical total and balance. The remaining gap is only the original line-by-line detail from QuickBooks."
                        )
                    }

                    // Line items table
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
                                    Text(fmtCurrency(line.rate))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 100, alignment: .trailing)
                                    Text(fmtCurrency(line.amount))
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 110, alignment: .trailing)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }

                        HStack {
                            Spacer()
                            Text("TOTAL: \(fmtCurrency(currentInvoice.total))")
                                .font(.headline)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface)
                    }
                    .background(AppTheme.canvas)
                    .cornerRadius(8)

                    // Payment history
                    if !payments.isEmpty || !creditApplications.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("PAYMENTS & CREDITS APPLIED")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink3)
                                .padding(.bottom, 6)

                            ForEach(payments) { p in
                                settlementRow(
                                    date: p.paymentDate,
                                    kind: p.method.capitalized,
                                    reference: p.reference.isEmpty ? (p.displayMemo.isEmpty ? "-" : p.displayMemo) : p.reference,
                                    amount: p.amount,
                                    tint: AppTheme.ok
                                )
                            }

                            ForEach(creditApplications) { credit in
                                settlementRow(
                                    date: credit.appliedDate,
                                    kind: credit.creditType.capitalized,
                                    reference: credit.reference.isEmpty ? (credit.displayMemo.isEmpty ? "-" : credit.displayMemo) : credit.reference,
                                    amount: credit.amount,
                                    tint: AppTheme.ok
                                )
                            }
                        }
                        .background(AppTheme.canvas)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                if currentInvoice.status != "void" {
                    Button("Void Invoice") { showVoidConfirm = true }
                        .foregroundStyle(AppTheme.bad)
                }
                Spacer()
                Button("Print / Save PDF") { printInvoice() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("invoice.detail.printButton")
                if currentInvoice.balance > 0 && currentInvoice.status != "void" {
                    Button("Receive Payment") { showPayment = true }
                        .buttonStyle(.renaissancePrimary)
                        .accessibilityIdentifier("invoice.detail.recordPaymentButton")
                }
                Button("Email QB File") { emailInvoice() }
                    .buttonStyle(.renaissanceSecondary)
                    .accessibilityIdentifier("invoice.detail.emailButton")
            }
            .padding()
        }
        .frame(width: 760, height: 600)
        .onAppear { loadData() }
        .onDisappear { onDismiss() }
        .accessibilityIdentifier("invoice.detail.\(currentInvoice.id)")
        .sheet(isPresented: $showPayment) {
            ReceivePaymentSheet(
                prefilledCustomerID: currentInvoice.customerID,
                prefilledInvoiceID: currentInvoice.id
            ) {
                showPayment = false
                loadData()
                refreshInvoice()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showEdit) {
            NewInvoiceSheet(invoice: currentInvoice) {
                showEdit = false
                loadData()
                refreshInvoice()
                onDismiss()
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showDuplicate) {
            NewInvoiceSheet(duplicateSource: currentInvoice) {
                showDuplicate = false
                model.refreshNativeInvoices()
                loadData()
                onDismiss()
            }
            .environmentObject(model)
        }
        .alert("Void Invoice?", isPresented: $showVoidConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Void", role: .destructive) { voidInvoice() }
        } message: {
            Text("This will mark the invoice as void. It cannot be undone.")
        }
    }

    private func loadData() {
        lines = (try? model.db.fetchInvoiceLines(invoiceID: currentInvoice.id)) ?? []
        payments = (try? model.db.fetchPaymentsForInvoice(invoiceID: currentInvoice.id)) ?? []
        creditApplications = (try? model.db.fetchCreditApplicationsForInvoice(invoiceID: currentInvoice.id)) ?? []
        scheduleHarnessEmailIfNeeded()
    }

    private func refreshInvoice() {
        if let updated = try? model.db.fetchInvoice(id: currentInvoice.id) {
            currentInvoice = updated
        }
    }

    private func closeSheet() {
        onDismiss()
        dismiss()
    }

    private func scheduleHarnessEmailIfNeeded() {
        guard !didTriggerHarnessEmail, model.consumePendingEmailInvoiceOnOpen() else { return }
        didTriggerHarnessEmail = true
        appendHarnessLog("invoice email scheduled for invoice \(currentInvoice.id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            appendHarnessLog("invoice email firing for invoice \(currentInvoice.id)")
            emailInvoice()
        }
    }

    private func voidInvoice() {
        do {
            try model.db.voidInvoice(id: currentInvoice.id)
            refreshInvoice()
            onDismiss()
        } catch {
            // error visible via statusMessage
        }
    }

    private func printInvoice() {
        let printView = InvoicePrintView(invoice: currentInvoice, lines: lines, payments: payments, companyInfo: model.companyInfo)
        PDFExportService.printView(jobTitle: "Invoice \(currentInvoice.invoiceNumber)", view: printView)
    }

    private func emailInvoice() {
        let printView = InvoicePrintView(invoice: currentInvoice, lines: lines, payments: payments, companyInfo: model.companyInfo)
        do {
            let iifURL = try QuickBooksIIFExportService.writeInvoiceIIF(
                invoice: currentInvoice,
                lines: lines
            )
            var attachments = [iifURL]
            if let pdfURL = try? PDFExportService.writePDF(
                fileName: "Invoice-\(currentInvoice.invoiceNumber).pdf",
                view: printView
            ) {
                attachments.append(pdfURL)
            }
            try FileShareService.emailFiles(
                fileURLs: attachments,
                subject: "Invoice \(currentInvoice.invoiceNumber) - QuickBooks IIF",
                recipientEmails: customerRecipientEmails(for: currentInvoice.customerID)
            )
        } catch {
            model.statusMessage = "Invoice email failed: \(error.localizedDescription)"
        }
    }

    private func customerRecipientEmails(for customerID: Int64) -> [String] {
        guard let customer = model.customers.first(where: { $0.id == customerID }) else {
            return []
        }
        return FileShareService.normalizedRecipientEmails(from: customer.email)
    }

    private func settlementRow(date: String, kind: String, reference: String, amount: Double, tint: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(date)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 100, alignment: .leading)
                Text(kind)
                    .frame(width: 110, alignment: .leading)
                Text(reference)
                    .foregroundStyle(AppTheme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(fmtCurrency(amount))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            Divider()
        }
    }

    private func labeledField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(AppTheme.ink3)
            Text(value).font(.body.bold())
        }
    }

    private func historicalDetailGapNotice(title: String, message: String) -> some View {
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

struct InvoiceStatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .cornerRadius(6)
    }

    private var statusColor: Color {
        switch status {
        case "paid": return .green
        case "partial": return .orange
        case "void": return .secondary
        default: return .red
        }
    }
}

private func fmtCurrency(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
