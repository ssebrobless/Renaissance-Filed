import Foundation

struct DuplicateWarningSettings: Codable, Equatable {
    var warnOnDuplicateEstimateNumbers: Bool
    var warnOnDuplicateInvoiceNumbers: Bool

    static func load() -> DuplicateWarningSettings {
        let defaults = UserDefaults.standard
        return DuplicateWarningSettings(
            warnOnDuplicateEstimateNumbers: defaults.object(forKey: "duplicateWarnings.warnOnDuplicateEstimateNumbers") as? Bool ?? true,
            warnOnDuplicateInvoiceNumbers: defaults.object(forKey: "duplicateWarnings.warnOnDuplicateInvoiceNumbers") as? Bool ?? true
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(warnOnDuplicateEstimateNumbers, forKey: "duplicateWarnings.warnOnDuplicateEstimateNumbers")
        defaults.set(warnOnDuplicateInvoiceNumbers, forKey: "duplicateWarnings.warnOnDuplicateInvoiceNumbers")
    }
}

struct PaymentWorkflowSettings: Codable, Equatable {
    var autoApplyPaymentsToOldestOpenInvoices: Bool
    var autoApplyAvailableCredits: Bool
    var defaultPaymentMethodName: String
    var receivePaymentsIntoUndepositedFunds: Bool
    var defaultDepositAccountID: Int64

    static func load() -> PaymentWorkflowSettings {
        let defaults = UserDefaults.standard
        return PaymentWorkflowSettings(
            autoApplyPaymentsToOldestOpenInvoices: defaults.object(forKey: "paymentWorkflow.autoApplyPaymentsToOldestOpenInvoices") as? Bool ?? true,
            autoApplyAvailableCredits: defaults.object(forKey: "paymentWorkflow.autoApplyAvailableCredits") as? Bool ?? true,
            defaultPaymentMethodName: defaults.string(forKey: "paymentWorkflow.defaultPaymentMethodName") ?? "Check",
            receivePaymentsIntoUndepositedFunds: defaults.object(forKey: "paymentWorkflow.receivePaymentsIntoUndepositedFunds") as? Bool ?? true,
            defaultDepositAccountID: Int64(defaults.integer(forKey: "paymentWorkflow.defaultDepositAccountID"))
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(autoApplyPaymentsToOldestOpenInvoices, forKey: "paymentWorkflow.autoApplyPaymentsToOldestOpenInvoices")
        defaults.set(autoApplyAvailableCredits, forKey: "paymentWorkflow.autoApplyAvailableCredits")
        defaults.set(defaultPaymentMethodName, forKey: "paymentWorkflow.defaultPaymentMethodName")
        defaults.set(receivePaymentsIntoUndepositedFunds, forKey: "paymentWorkflow.receivePaymentsIntoUndepositedFunds")
        defaults.set(Int(defaultDepositAccountID), forKey: "paymentWorkflow.defaultDepositAccountID")
    }
}

struct CheckWorkflowSettings: Codable, Equatable {
    var defaultCodingMode: CheckCodingMode
    var showCategoryOnPrintedChecks: Bool
    var showMemoOnPrintedChecks: Bool
    var defaultBankAccountID: Int64

    static func load() -> CheckWorkflowSettings {
        let defaults = UserDefaults.standard
        let codingModeRaw = defaults.string(forKey: "checkWorkflow.defaultCodingMode") ?? CheckCodingMode.category.rawValue
        return CheckWorkflowSettings(
            defaultCodingMode: CheckCodingMode(rawValue: codingModeRaw) ?? .category,
            showCategoryOnPrintedChecks: defaults.object(forKey: "checkWorkflow.showCategoryOnPrintedChecks") as? Bool ?? true,
            showMemoOnPrintedChecks: defaults.object(forKey: "checkWorkflow.showMemoOnPrintedChecks") as? Bool ?? true,
            defaultBankAccountID: Int64(defaults.integer(forKey: "checkWorkflow.defaultBankAccountID"))
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(defaultCodingMode.rawValue, forKey: "checkWorkflow.defaultCodingMode")
        defaults.set(showCategoryOnPrintedChecks, forKey: "checkWorkflow.showCategoryOnPrintedChecks")
        defaults.set(showMemoOnPrintedChecks, forKey: "checkWorkflow.showMemoOnPrintedChecks")
        defaults.set(Int(defaultBankAccountID), forKey: "checkWorkflow.defaultBankAccountID")
    }
}
