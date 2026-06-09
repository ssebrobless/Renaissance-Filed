import SwiftUI

struct InvoicePrintView: View {
    let invoice: NativeInvoiceRow
    let lines: [InvoiceLineRow]
    let payments: [PaymentDetailRow]
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
                            .foregroundStyle(.secondary)
                    }
                    if !companyInfo.cityStateZip.isEmpty {
                        Text(companyInfo.cityStateZip)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if !companyInfo.phone.isEmpty {
                        Text(companyInfo.phone)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if !companyInfo.email.isEmpty {
                        Text(companyInfo.email)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if !companyInfo.licenseNumber.isEmpty {
                        Text("Lic# \(companyInfo.licenseNumber)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text("Invoice")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Invoice #").foregroundStyle(.secondary)
                        Text(invoice.invoiceNumber).bold()
                    }
                    HStack {
                        Text("Date").foregroundStyle(.secondary)
                        Text(invoice.issueDate)
                    }
                    HStack {
                        Text("Due Date").foregroundStyle(.secondary)
                        Text(invoice.dueDate)
                    }
                }
            }
            .padding(.bottom, 24)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("BILL TO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Text(invoice.customerDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = invoice.customerDisplayDetail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 0) {
                Text("Description")
                    .font(.system(size: 9, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 55, alignment: .trailing)
                Text("Rate")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 80, alignment: .trailing)
                Text("Amount")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(Color.gray.opacity(0.12))

            ForEach(lines) { line in
                HStack(spacing: 0) {
                    Text(line.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.2f", line.quantity))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 55, alignment: .trailing)
                    Text(printCurrency(line.rate))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                    Text(printCurrency(line.amount))
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
                        Text("Subtotal").foregroundStyle(.secondary)
                        Text(printCurrency(invoice.total))
                            .fontDesign(.monospaced)
                    }
                    if invoice.paid > 0 {
                        ForEach(payments) { payment in
                            HStack(spacing: 16) {
                                Text("Payment (\(payment.paymentDate))").foregroundStyle(.secondary)
                                Text("-" + printCurrency(payment.amount))
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(AppTheme.ok)
                            }
                        }
                    }
                    Divider()
                    HStack(spacing: 16) {
                        Text("BALANCE DUE").fontWeight(.bold)
                        Text(printCurrency(invoice.balance))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(invoice.balance > 0 ? AppTheme.bad : AppTheme.ok)
                    }
                }
                .frame(width: 280)
            }
            .padding(.top, 12)

            if !invoice.displayMemo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                    Text(invoice.displayMemo)
                        .font(.system(size: 10))
                }
            }

            if !companyInfo.paymentTerms.isEmpty {
                HStack {
                    Text("Payment Terms:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(companyInfo.paymentTerms).font(.system(size: 9))
                }
                .padding(.top, 12)
            }

            Spacer()

            Divider()
            Text(companyInfo.invoiceFooter.isEmpty ? "Thank you for your business." : companyInfo.invoiceFooter)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .font(.system(size: 11))
        .environment(\.colorScheme, .light)
    }
}

private func printCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
