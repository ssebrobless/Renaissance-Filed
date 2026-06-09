import SwiftUI

struct EstimatePrintView: View {
    let estimate: EstimateRow
    let lines: [EstimateLineRow]
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
                    Text("Estimate")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Estimate #").foregroundStyle(.secondary)
                        Text(estimate.estimateNumber).bold()
                    }
                    HStack {
                        Text("Date").foregroundStyle(.secondary)
                        Text(estimate.issueDate)
                    }
                    HStack {
                        Text("Valid Until").foregroundStyle(.secondary)
                        Text(estimate.validUntil)
                    }
                    HStack {
                        Text("Status").foregroundStyle(.secondary)
                        Text(estimate.status.capitalized)
                    }
                }
            }
            .padding(.bottom, 24)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("CUSTOMER")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Text(estimate.customerDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = estimate.customerDisplayDetail {
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
                    Text(estimatePrintCurrency(line.rate))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                    Text(estimatePrintCurrency(line.amount))
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
                    Divider()
                    HStack(spacing: 16) {
                        Text("ESTIMATE TOTAL").fontWeight(.bold)
                        Text(estimatePrintCurrency(estimate.total))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                }
                .frame(width: 280)
            }
            .padding(.top, 12)

            if !estimate.displayMemo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                    Text(estimate.displayMemo)
                        .font(.system(size: 10))
                }
            }

            Spacer()

            Divider()
            Text("This estimate can be revised until it is converted into a final invoice.")
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

private func estimatePrintCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
}
