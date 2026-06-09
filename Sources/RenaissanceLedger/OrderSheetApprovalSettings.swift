import Foundation

struct OrderSheetApprovalSettings: Hashable {
    private enum Keys {
        static let testingModeEnabled = "orderSheetApprovalTestingModeEnabled"
        static let requireConfirmation = "orderSheetApprovalRequireConfirmation"
    }

    var testingModeEnabled: Bool
    var requireConfirmation: Bool

    static func load(defaults: UserDefaults = .standard) -> OrderSheetApprovalSettings {
        let testingModeEnabled = defaults.object(forKey: Keys.testingModeEnabled) as? Bool ?? true
        let requireConfirmation = defaults.object(forKey: Keys.requireConfirmation) as? Bool ?? true
        let settings = OrderSheetApprovalSettings(
            testingModeEnabled: testingModeEnabled,
            requireConfirmation: requireConfirmation
        )
        settings.save(defaults: defaults)
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(testingModeEnabled, forKey: Keys.testingModeEnabled)
        defaults.set(requireConfirmation, forKey: Keys.requireConfirmation)
    }
}
