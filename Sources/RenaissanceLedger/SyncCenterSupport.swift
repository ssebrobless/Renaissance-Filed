import Foundation

enum MailProviderKind: String, CaseIterable, Codable, Identifiable {
    case automatic
    case appleMail
    case outlook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic (Apple Mail first)"
        case .appleMail:
            return "Apple Mail"
        case .outlook:
            return "Microsoft Outlook"
        }
    }
}

struct OldQBSyncSettings: Codable, Hashable {
    var autoScanOnLaunch: Bool
    var showSyncTabBadge: Bool
    var importSafeEstimateAndInvoiceDrift: Bool
    var reviewChecksBeforeImport: Bool

    static func load() -> OldQBSyncSettings {
        let defaults = UserDefaults.standard
        return OldQBSyncSettings(
            autoScanOnLaunch: defaults.object(forKey: "oldQBSync.autoScanOnLaunch") as? Bool ?? true,
            showSyncTabBadge: defaults.object(forKey: "oldQBSync.showSyncTabBadge") as? Bool ?? true,
            importSafeEstimateAndInvoiceDrift: defaults.object(forKey: "oldQBSync.importSafeEstimateAndInvoiceDrift") as? Bool ?? true,
            reviewChecksBeforeImport: defaults.object(forKey: "oldQBSync.reviewChecksBeforeImport") as? Bool ?? true
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(autoScanOnLaunch, forKey: "oldQBSync.autoScanOnLaunch")
        defaults.set(showSyncTabBadge, forKey: "oldQBSync.showSyncTabBadge")
        defaults.set(importSafeEstimateAndInvoiceDrift, forKey: "oldQBSync.importSafeEstimateAndInvoiceDrift")
        defaults.set(reviewChecksBeforeImport, forKey: "oldQBSync.reviewChecksBeforeImport")
    }
}

struct OldQBSyncSnapshot: Hashable {
    var lastScanAt: Date? = nil
    var lastResultSummary: String = "Old QuickBooks sync center is ready for live Mac verification."
    var pendingEstimateCount = 0
    var pendingInvoiceCount = 0
    var pendingCheckCount = 0
    var lastImportedEstimateCount = 0
    var lastImportedInvoiceCount = 0
}
