import AppKit
import Foundation

struct WorkspaceRestoreSnapshot: Codable, Hashable {
    var savedAt: String
    var selectedTab: String
    var centerMode: String
    var registerMode: String
    var activeReportTab: String
    var selectedCustomerID: Int64?
    var selectedBankAccountID: Int64
    var visibleWindows: [String]
    var windowFrames: [String: WorkspaceRestoreFrame]
}

struct WorkspaceRestoreFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ frame: NSRect) {
        x = Double(frame.origin.x)
        y = Double(frame.origin.y)
        width = Double(frame.size.width)
        height = Double(frame.size.height)
    }

    var rect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class WorkspaceRestoreStore {
    static let shared = WorkspaceRestoreStore()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var restoreDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("RenaissanceLedger/TechSupport/restore", isDirectory: true)
    }

    var latestSnapshotURL: URL {
        restoreDirectoryURL.appendingPathComponent("latest-workspace.json")
    }

    func save(_ snapshot: WorkspaceRestoreSnapshot) {
        do {
            try fileManager.createDirectory(at: restoreDirectoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: latestSnapshotURL, options: .atomic)
        } catch {
            NSLog("Workspace restore snapshot save failed: \(error.localizedDescription)")
        }
    }

    func load() -> WorkspaceRestoreSnapshot? {
        guard let data = try? Data(contentsOf: latestSnapshotURL) else { return nil }
        return try? decoder.decode(WorkspaceRestoreSnapshot.self, from: data)
    }
}
