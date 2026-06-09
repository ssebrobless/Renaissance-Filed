import Combine
import Foundation

@MainActor
final class TechSupportStore: ObservableObject {
    static let shared = TechSupportStore()

    @Published private(set) var recentRequests: [TechSupportRequest] = []
    @Published var pendingCompletionNotice: TechSupportCompletionNotice?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var supportRootURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("RenaissanceLedger/TechSupport", isDirectory: true)
    }

    var outgoingQueueURL: URL {
        supportRootURL.appendingPathComponent("outgoing", isDirectory: true)
    }

    var completionQueueURL: URL {
        supportRootURL.appendingPathComponent("completion", isDirectory: true)
    }

    func submit(message: String, selectedTab: String, visibleWindowTitles: [String]) throws -> TechSupportRequest {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TechSupportStoreError.emptyMessage
        }

        try fileManager.createDirectory(at: outgoingQueueURL, withIntermediateDirectories: true)

        let request = TechSupportRequest(
            id: UUID(),
            createdAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            requestSource: "techSupport",
            userMessage: trimmed,
            selectedTab: selectedTab,
            visibleWindowTitles: visibleWindowTitles,
            status: .queued
        )

        let requestDir = outgoingQueueURL.appendingPathComponent(request.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: requestDir, withIntermediateDirectories: true)
        let data = try encoder.encode(request)
        try data.write(to: requestDir.appendingPathComponent("request.json"), options: .atomic)
        recentRequests.insert(request, at: 0)
        return request
    }

    func pollCompletionNotice() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: completionQueueURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let notices = files.filter { $0.pathExtension == "json" }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        guard let latest = notices.first,
              let data = try? Data(contentsOf: latest),
              let notice = try? decoder.decode(TechSupportCompletionNotice.self, from: data) else {
            return
        }
        pendingCompletionNotice = notice
    }

    func dismissCompletionNotice(_ notice: TechSupportCompletionNotice) {
        pendingCompletionNotice = nil
        let url = completionQueueURL.appendingPathComponent("\(notice.id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }
}

enum TechSupportStoreError: LocalizedError {
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Type a short description before sending Tech Support."
        }
    }
}
