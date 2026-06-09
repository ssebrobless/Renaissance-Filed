import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct OrderSheetInboxSettings: Hashable {
    private enum Keys {
        static let enabled = "orderSheetInboxEnabled"
        static let folderPath = "orderSheetInboxFolderPath"
        static let scanIntervalSeconds = "orderSheetInboxScanIntervalSeconds"
        static let deleteAfterStage = "orderSheetInboxDeleteAfterStage"
    }

    static let minimumScanInterval: TimeInterval = 2
    static let defaultScanInterval: TimeInterval = 3

    var isEnabled: Bool
    var folderPath: String
    var scanIntervalSeconds: TimeInterval
    var deleteAfterStage: Bool

    var folderURL: URL {
        if let sandboxURL = Self.sandboxFolderURL() {
            return sandboxURL
        }
        if folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.recommendedFolderURL()
        }
        return URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    static func load(defaults: UserDefaults = .standard) -> OrderSheetInboxSettings {
        if let sandboxURL = sandboxFolderURL() {
            let settings = OrderSheetInboxSettings(
                isEnabled: true,
                folderPath: sandboxURL.path,
                scanIntervalSeconds: defaultScanInterval,
                deleteAfterStage: true
            )
            try? ensureDirectory(at: settings.folderURL)
            return settings
        }

        let recommended = recommendedFolderURL()
        let path = defaults.string(forKey: Keys.folderPath) ?? recommended.path
        let enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let storedInterval = defaults.object(forKey: Keys.scanIntervalSeconds) as? Double
        let interval = max(minimumScanInterval, storedInterval ?? defaultScanInterval)
        let deleteAfterStage = defaults.object(forKey: Keys.deleteAfterStage) as? Bool ?? true

        let settings = OrderSheetInboxSettings(
            isEnabled: enabled,
            folderPath: path,
            scanIntervalSeconds: interval,
            deleteAfterStage: deleteAfterStage
        )

        try? ensureDirectory(at: settings.folderURL)
        settings.save(defaults: defaults)
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.enabled)
        defaults.set(folderURL.path, forKey: Keys.folderPath)
        defaults.set(max(Self.minimumScanInterval, scanIntervalSeconds), forKey: Keys.scanIntervalSeconds)
        defaults.set(deleteAfterStage, forKey: Keys.deleteAfterStage)
    }

    static func recommendedFolderURL(fileManager: FileManager = .default) -> URL {
        if let sandboxURL = sandboxFolderURL() {
            return sandboxURL
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let iCloudRoot = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)

        if fileManager.fileExists(atPath: iCloudRoot.path) {
            return iCloudRoot
                .appendingPathComponent("Renaissance Filed", isDirectory: true)
                .appendingPathComponent("Order Sheet Inbox", isDirectory: true)
        }

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Documents", isDirectory: true)
        return documents
            .appendingPathComponent("Renaissance Filed", isDirectory: true)
            .appendingPathComponent("Order Sheet Inbox", isDirectory: true)
    }

    static func ensureRecommendedFolderExists() throws -> URL {
        let url = recommendedFolderURL()
        try ensureDirectory(at: url)
        return url
    }

    private static func sandboxFolderURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RENAISSANCE_LEDGER_SANDBOX_MODE"] == "1",
              let supportDir = environment["RENAISSANCE_LEDGER_SUPPORT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !supportDir.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: supportDir, isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
    }

    static func chooseFolder(startingAt startingURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Inbox"
        panel.message = "Choose the folder the Mac should watch for phone-shared order sheets."
        panel.directoryURL = startingURL
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

struct OrderSheetInboxScanResult {
    var importedCount = 0
    var restagedCount = 0
    var duplicateCount = 0
    var skippedCount = 0

    var hasActivity: Bool {
        importedCount > 0 || restagedCount > 0 || duplicateCount > 0 || skippedCount > 0
    }

    func statusMessage(manual: Bool) -> String {
        if importedCount == 0 && duplicateCount == 0 && skippedCount == 0 {
            return manual ? "No new phone order sheets were found." : ""
        }

        var parts: [String] = []
        if importedCount > 0 {
            parts.append("staged \(importedCount) new phone order sheet\(importedCount == 1 ? "" : "s")")
        }
        if restagedCount > 0 {
            parts.append("reopened \(restagedCount) previously dismissed sheet\(restagedCount == 1 ? "" : "s")")
        }
        if duplicateCount > 0 {
            parts.append("ignored \(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s")")
        }
        if skippedCount > 0 {
            parts.append("skipped \(skippedCount) file\(skippedCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "" : "Auto-import " + parts.joined(separator: ", ") + "."
    }
}

enum OrderSheetInboxMonitor {
    static let supportedContentTypes: [UTType] = [.png, .jpeg, .heic, .heif, .pdf]
    private static let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "pdf"])

    static func scan(
        settings: OrderSheetInboxSettings,
        store: OrderSheetStagingStore = .newWorker()
    ) throws -> OrderSheetInboxScanResult {
        guard settings.isEnabled else { return OrderSheetInboxScanResult() }

        let fileManager = FileManager.default
        let inboxURL = settings.folderURL
        try OrderSheetInboxSettings.ensureDirectory(at: inboxURL)

        let urls = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var result = OrderSheetInboxScanResult()
        let candidates = urls
            .filter { isSupportedFile($0) }
            .filter { isStableEnoughToImport($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for url in candidates {
            do {
                switch try store.importOrderSheet(imageURL: url) {
                case .imported:
                    result.importedCount += 1
                    try finalizeSourceFile(at: url, settings: settings)
                case .restaged:
                    result.restagedCount += 1
                    try finalizeSourceFile(at: url, settings: settings)
                case .duplicate:
                    result.duplicateCount += 1
                    try finalizeSourceFile(at: url, settings: settings)
                }
            } catch {
                result.skippedCount += 1
            }
        }

        return result
    }

    static func deleteMatchingSourceFiles(for row: OrderSheetRow, settings: OrderSheetInboxSettings) throws {
        guard settings.isEnabled else { return }

        let fileManager = FileManager.default
        let inboxURL = settings.folderURL
        guard fileManager.fileExists(atPath: inboxURL.path) else { return }

        let urls = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls where isSupportedFile(url) {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }

            if url.lastPathComponent != row.originalFilename {
                continue
            }

            guard let data = try? Data(contentsOf: url) else { continue }
            let candidateSHA = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard candidateSHA == row.sha256 else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private static func isSupportedFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    private static func isStableEnoughToImport(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
              values.isRegularFile == true
        else {
            return false
        }

        guard (values.fileSize ?? 0) > 0 else { return false }
        if let modified = values.contentModificationDate,
           Date().timeIntervalSince(modified) < 2 {
            return false
        }
        return true
    }

    private static func finalizeSourceFile(at sourceURL: URL, settings: OrderSheetInboxSettings) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sourceURL.path) {
            if settings.deleteAfterStage {
                try fileManager.removeItem(at: sourceURL)
            }
        }
    }
}
