import Foundation

enum PayeeReviewKind: String {
    case internalSelf = "Internal / Self"
    case vendor1099 = "1099 Vendor"
    case payee = "Recorded Payee"
}

struct PayeeReviewContext {
    let matchedVendor: VendorRow?
    let internalAnchorVendor: VendorRow?

    var isInternalSelf: Bool { (matchedVendor?.isInternalSelf ?? false) || internalAnchorVendor != nil }

    var kind: PayeeReviewKind {
        if isInternalSelf { return .internalSelf }
        if matchedVendor?.is1099 == true { return .vendor1099 }
        return .payee
    }

    var shortReason: String {
        if matchedVendor?.isInternalSelf == true {
            return "Explicitly marked as internal/self."
        }
        if let internalAnchorVendor {
            if matchedVendor?.id == internalAnchorVendor.id {
                return "Matches the company phone."
            }
            return "Matches an internal/self payee alias."
        }
        if matchedVendor?.is1099 == true {
            return "Marked as a 1099 subcontractor."
        }
        return "Recorded payee used in checks and expenses."
    }

    var longReason: String {
        if matchedVendor?.isInternalSelf == true {
            return "\(matchedVendor?.displayLabel ?? "This payee") is explicitly marked as an internal/self payee."
        }
        if let internalAnchorVendor {
            if matchedVendor?.id == internalAnchorVendor.id {
                return "\(internalAnchorVendor.displayLabel) shares the company phone, so it is treated as an internal/self payee for review purposes."
            }
            return "\(matchedVendor?.displayLabel ?? "This payee") matches the internal/self payee name pattern based on \(internalAnchorVendor.displayLabel)."
        }
        if matchedVendor?.is1099 == true {
            return "This payee is currently marked as a 1099 subcontractor."
        }
        return "This payee is present in recorded checks or expenses, but it is not currently marked as a 1099 subcontractor."
    }
}

func payeeReviewContext(for payeeName: String, vendors: [VendorRow], companyInfo: CompanyInfo) -> PayeeReviewContext {
    let payeeKey = normalizedPayeeReviewKey(payeeName)
    let matchedVendor = matchedVendorRow(for: payeeKey, vendors: vendors)
    let internalAnchor = internalAnchorVendor(for: payeeKey, vendors: vendors, companyInfo: companyInfo)
    return PayeeReviewContext(matchedVendor: matchedVendor, internalAnchorVendor: internalAnchor)
}

private func matchedVendorRow(for payeeKey: String, vendors: [VendorRow]) -> VendorRow? {
    guard !payeeKey.isEmpty else { return nil }
    if let exact = vendors.first(where: { normalizedPayeeReviewKey($0.name) == payeeKey }) {
        return exact
    }
    return vendors.first(where: {
        let vendorKey = normalizedPayeeReviewKey($0.name)
        return payeeKey.hasPrefix(vendorKey + " ")
    })
}

private func internalAnchorVendor(for payeeKey: String, vendors: [VendorRow], companyInfo: CompanyInfo) -> VendorRow? {
    guard !payeeKey.isEmpty else { return nil }
    let companyPhone = normalizedPhoneDigits(companyInfo.phone)
    guard !companyPhone.isEmpty else { return nil }

    let internalAnchors = vendors.filter { normalizedPhoneDigits($0.phone) == companyPhone }
    if internalAnchors.isEmpty { return nil }

    if let exact = internalAnchors.first(where: { normalizedPayeeReviewKey($0.name) == payeeKey }) {
        return exact
    }

    return internalAnchors.first(where: {
        let baseKey = normalizedPayeeReviewKey($0.name)
        return payeeKey.hasPrefix(baseKey + " ")
    })
}

private func normalizedPayeeReviewKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}

private func normalizedPhoneDigits(_ value: String) -> String {
    value.filter(\.isNumber)
}
