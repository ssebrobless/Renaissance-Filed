import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SQLite3

struct HarnessCommand: Codable {
    var id: String
    var scenario: String
    var allowWrite: Bool
    var targetAppPath: String
    var arguments: [String: String]
    var requestedArtifacts: [String]
    var timeoutSeconds: Int
}

struct HarnessPermissions: Codable {
    var accessibility: Bool
    var screenRecording: Bool
}

struct HarnessWindowSnapshot: Codable {
    var ownerName: String
    var windowName: String
    var windowID: Int
    var layer: Int
    var alpha: Double
    var bounds: [String: Double]
}

struct HarnessAppState: Codable {
    var installed: Bool
    var displayName: String
    var bundleIdentifier: String
    var targetAppPath: String
    var running: Bool
    var processIDs: [Int32]
    var windows: [HarnessWindowSnapshot]
}

struct HarnessStep: Codable {
    var name: String
    var status: String
    var detail: String
    var timestamp: String
}

struct HarnessResult: Codable {
    var id: String
    var status: String
    var startedAt: String
    var finishedAt: String?
    var error: String?
    var permissions: HarnessPermissions
    var appState: HarnessAppState?
    var dbBackupPath: String?
    var artifacts: [String: String]
    var steps: [HarnessStep]
}

private struct HarnessDirectories {
    let root: URL
    let inbox: URL
    let runs: URL
    let state: URL
    let processing: URL

    static func make() -> HarnessDirectories {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = support.appendingPathComponent("RenaissanceHarness", isDirectory: true)
        return HarnessDirectories(
            root: root,
            inbox: root.appendingPathComponent("inbox", isDirectory: true),
            runs: root.appendingPathComponent("runs", isDirectory: true),
            state: root.appendingPathComponent("state", isDirectory: true),
            processing: root.appendingPathComponent("state/processing", isDirectory: true)
        )
    }

    func ensure() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: processing, withIntermediateDirectories: true, attributes: nil)
    }
}

private struct HarnessTargetApp {
    let appURL: URL
    let displayName: String
    let bundleIdentifier: String

    init(path: String) {
        let appURL = URL(fileURLWithPath: path)
        let bundle = Bundle(url: appURL)
        self.appURL = appURL
        self.displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        self.bundleIdentifier = bundle?.bundleIdentifier ?? ""
    }
}

private final class HarnessRun {
    let command: HarnessCommand
    let runDirectory: URL
    var result: HarnessResult

    init(command: HarnessCommand, runDirectory: URL, permissions: HarnessPermissions) {
        self.command = command
        self.runDirectory = runDirectory
        self.result = HarnessResult(
            id: command.id,
            status: "running",
            startedAt: Self.isoNow(),
            finishedAt: nil,
            error: nil,
            permissions: permissions,
            appState: nil,
            dbBackupPath: nil,
            artifacts: [:],
            steps: []
        )
    }

    func addStep(_ name: String, status: String, detail: String) {
        result.steps.append(
            HarnessStep(
                name: name,
                status: status,
                detail: detail,
                timestamp: Self.isoNow()
            )
        )
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum HarnessError: LocalizedError {
    case invalidCommand(String)
    case appMissing(String)
    case appLaunchFailed(String)
    case windowNotVisible(String)
    case missingPermission(String)
    case unsupportedWriteScenario(String)
    case missingRecord(String)
    case commandTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand(let value),
             .appMissing(let value),
             .appLaunchFailed(let value),
             .windowNotVisible(let value),
             .missingPermission(let value),
             .unsupportedWriteScenario(let value),
             .missingRecord(let value),
             .commandTimedOut(let value):
            return value
        }
    }
}

final class HarnessController: ObservableObject {
    static let shared = HarnessController()

    @Published var statusText = "Idle"
    @Published var lastRunSummary = "No runs yet"
    @Published var isProcessing = false
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false

    private let directories = HarnessDirectories.make()
    private var activeCommand: HarnessCommand?
    private var timer: Timer?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    init() {
        try? directories.ensure()
        recoverAbandonedProcessingCommands()
        refreshPermissionState()
        startWatching()
    }

    deinit {
        timer?.invalidate()
    }

    func openArtifactsFolder() {
        NSWorkspace.shared.open(directories.runs)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        statusText = granted ? "Accessibility granted" : "Accessibility prompt opened"
        refreshPermissionState()
    }

    func requestScreenRecordingPermission() {
        let granted = CGRequestScreenCaptureAccess()
        statusText = granted ? "Screen Recording granted" : "Screen Recording prompt opened"
        refreshPermissionState()
    }

    func refreshPermissionState() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func runProbeManually() {
        let command = HarnessCommand(
            id: UUID().uuidString.lowercased(),
            scenario: "probe",
            allowWrite: false,
            targetAppPath: "/Applications/Renaissance Filed.app",
            arguments: [:],
            requestedArtifacts: ["desktop"],
            timeoutSeconds: 20
        )
        Task {
            await self.execute(command: command, claimedCommandURL: nil)
        }
    }

    private func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.scanInbox()
        }
    }

    private func scanInbox() {
        guard !isProcessing else { return }
        guard let claimedCommandURL = claimNextCommand() else { return }

        isProcessing = true
        Task {
            await self.executeClaimedCommand(at: claimedCommandURL)
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }

    private func recoverAbandonedProcessingCommands() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directories.processing,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for claimedCommandURL in urls where claimedCommandURL.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: claimedCommandURL)
                let command = try decoder.decode(HarnessCommand.self, from: data)
                let runDirectory = directories.runs.appendingPathComponent(command.id, isDirectory: true)
                try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true, attributes: nil)

                let permissions = HarnessPermissions(
                    accessibility: AXIsProcessTrusted(),
                    screenRecording: CGPreflightScreenCaptureAccess()
                )
                let result = HarnessResult(
                    id: command.id,
                    status: "failed",
                    startedAt: isoNow(),
                    finishedAt: isoNow(),
                    error: "Recovered abandoned in-progress command after helper restart.",
                    permissions: permissions,
                    appState: nil,
                    dbBackupPath: nil,
                    artifacts: [:],
                    steps: [
                        HarnessStep(
                            name: "recover_abandoned_command",
                            status: "failed",
                            detail: "Helper restarted before this queued command finished.",
                            timestamp: isoNow()
                        )
                    ]
                )

                let commandURL = runDirectory.appendingPathComponent("command.json")
                if !FileManager.default.fileExists(atPath: commandURL.path) {
                    if let commandData = try? encoder.encode(command) {
                        try? commandData.write(to: commandURL, options: .atomic)
                    }
                }

                writeResult(result, to: runDirectory)
            } catch {
                // Best-effort cleanup for malformed or partial queue entries.
            }

            try? FileManager.default.removeItem(at: claimedCommandURL)
        }
    }

    private func claimNextCommand() -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directories.inbox,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let sourceURL = candidates.first else { return nil }
        let destinationURL = directories.processing.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            statusText = "Queue claim failed"
            lastRunSummary = error.localizedDescription
            return nil
        }
    }

    private func executeClaimedCommand(at claimedCommandURL: URL) async {
        do {
            let data = try Data(contentsOf: claimedCommandURL)
            let command = try decoder.decode(HarnessCommand.self, from: data)
            await execute(command: command, claimedCommandURL: claimedCommandURL)
        } catch {
            let fallback = HarnessCommand(
                id: UUID().uuidString.lowercased(),
                scenario: "invalid_command",
                allowWrite: false,
                targetAppPath: "/Applications/Renaissance Filed.app",
                arguments: [:],
                requestedArtifacts: [],
                timeoutSeconds: 15
            )
            await execute(command: fallback, claimedCommandURL: claimedCommandURL, forcedError: HarnessError.invalidCommand(error.localizedDescription))
        }
    }

    private func execute(command: HarnessCommand, claimedCommandURL: URL?, forcedError: Error? = nil) async {
        do {
            try directories.ensure()
        } catch {
            await MainActor.run {
                self.statusText = "Directory setup failed"
                self.lastRunSummary = error.localizedDescription
            }
            return
        }

        let runDirectory = directories.runs.appendingPathComponent(command.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true, attributes: nil)

        let commandURL = runDirectory.appendingPathComponent("command.json")
        if let commandData = try? encoder.encode(command) {
            try? commandData.write(to: commandURL, options: .atomic)
        }

        let permissions = HarnessPermissions(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
        await MainActor.run {
            self.accessibilityGranted = permissions.accessibility
            self.screenRecordingGranted = permissions.screenRecording
        }
        let run = HarnessRun(command: command, runDirectory: runDirectory, permissions: permissions)

        await MainActor.run {
            self.statusText = "Running \(command.scenario)"
            self.lastRunSummary = "Started \(command.id)"
        }

        defer {
            activeCommand = nil
            if let claimedCommandURL {
                try? FileManager.default.removeItem(at: claimedCommandURL)
            }
            writeResult(run.result, to: runDirectory)
            Task { @MainActor in
                self.statusText = run.result.status == "succeeded" ? "Idle" : "Attention Needed"
                self.lastRunSummary = "\(command.scenario): \(run.result.status)"
            }
        }

        if let forcedError {
            run.result.status = "failed"
            run.result.error = forcedError.localizedDescription
            run.addStep("decode_command", status: "failed", detail: forcedError.localizedDescription)
            run.result.finishedAt = isoNow()
            return
        }

        do {
            activeCommand = command
            try await executeScenario(run: run)
            run.result.status = "succeeded"
        } catch {
            run.result.status = "failed"
            run.result.error = error.localizedDescription
            run.addStep("scenario", status: "failed", detail: error.localizedDescription)
        }
        run.result.finishedAt = isoNow()
    }

    private func executeScenario(run: HarnessRun) async throws {
        switch run.command.scenario {
        case "request_permissions":
            try await runRequestPermissions(run)
        case "inspect_order_sheet_inbox":
            try await runInspectOrderSheetInbox(run)
        case "review_first_order_sheet":
            try await runReviewFirstOrderSheet(run)
        case "probe":
            try await runProbe(run)
        case "app_boot":
            try await runAppBoot(run)
        case "tab_walk":
            try await runTabWalk(run)
        case "tab_walk_full":
            try await runTabWalkFull(run)
        case "tab_walk_secondary":
            try await runTabWalkSecondary(run)
        case "prove_navigation_shell":
            try await runProveNavigationShell(run)
        case "prove_window_recovery":
            try await runProveWindowRecovery(run)
        case "customer_estimate_view":
            try await runCustomerEstimateView(run)
        case "customer_invoice_view":
            try await runCustomerInvoiceView(run)
        case "preview_estimate_typeahead":
            try await runPreviewEstimateTypeahead(run)
        case "preview_invoice_typeahead":
            try await runPreviewInvoiceTypeahead(run)
        case "preview_write_check_typeahead":
            try await runPreviewWriteCheckTypeahead(run)
        case "preview_estimate_invoice_progress":
            try await runPreviewEstimateInvoiceProgress(run)
        case "verify_invoice_manual_description":
            try await runVerifyInvoiceManualDescription(run)
        case "email_first_document":
            try await runEmailFirstDocument(run)
        case "email_estimate_pdf":
            try await runEmailEstimatePDF(run)
        case "email_invoice_pdf":
            try await runEmailInvoicePDF(run)
        case "approve_first_order_sheet":
            try await runApproveFirstOrderSheet(run)
        case "edit_existing_estimate", "edit_existing_invoice", "write_check_draft", "reopen_saved_check", "prove_money_in_spine", "prove_money_out_spine", "prove_job_costing", "prove_report_correctness", "prove_bank_reconciliation":
            try await runWriteScenarioSkeleton(run)
        default:
            throw HarnessError.invalidCommand("Unsupported scenario '\(run.command.scenario)'")
        }
    }

    private func runInspectOrderSheetInbox(_ run: HarnessRun) async throws {
        let inboxURL = recommendedOrderSheetInboxURL()
        run.addStep("resolve_order_sheet_inbox", status: "ok", detail: inboxURL.path)

        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true, attributes: nil)
        let urls = try FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let files = urls
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let rows = files.map { url -> String in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = formatter.string(fromByteCount: Int64(values?.fileSize ?? 0))
            let modified = values?.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
            return "\(url.lastPathComponent)\t\(size)\t\(modified)"
        }

        let reportURL = run.runDirectory.appendingPathComponent("order_sheet_inbox_report.txt")
        let report = ([
            "Inbox: \(inboxURL.path)",
            "File count: \(files.count)",
            ""
        ] + rows).joined(separator: "\n") + "\n"
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        run.result.artifacts["order_sheet_inbox_report"] = reportURL.path
        run.addStep("inspect_order_sheet_inbox", status: "ok", detail: "files=\(files.count)")
    }

    private func runReviewFirstOrderSheet(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let screenshotURL = run.runDirectory.appendingPathComponent("order_sheet_review.png")
        let initialStagedCount = try orderSheetStagingCount(for: run.command)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "estimates",
                "--harness-review-first-order-sheet",
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "3.0"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        let stagedCount = try waitForOrderSheetStagingCount(
            above: initialStagedCount,
            command: run.command,
            timeoutSeconds: 45
        )
        try assertOrderSheetStagingIsSandboxed(command: run.command)
        run.addStep(
            "verify_order_sheet_staging",
            status: "ok",
            detail: "staged_before=\(initialStagedCount) staged_after=\(stagedCount)"
        )
        try waitForFile(at: screenshotURL, timeoutSeconds: 12)
        run.result.artifacts["order_sheet_review"] = screenshotURL.path
        run.addStep("review_first_order_sheet", status: "ok", detail: screenshotURL.lastPathComponent)
    }

    private func runRequestPermissions(_ run: HarnessRun) async throws {
        if !run.result.permissions.accessibility {
            requestAccessibilityPermission()
            run.addStep("request_accessibility", status: "prompted", detail: "Accessibility prompt requested")
        } else {
            run.addStep("request_accessibility", status: "ok", detail: "Accessibility already granted")
        }

        if !run.result.permissions.screenRecording {
            requestScreenRecordingPermission()
            run.addStep("request_screen_recording", status: "prompted", detail: "Screen Recording prompt requested")
        } else {
            run.addStep("request_screen_recording", status: "ok", detail: "Screen Recording already granted")
        }

        run.result.permissions = HarnessPermissions(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )

        if !run.result.permissions.accessibility || !run.result.permissions.screenRecording {
            throw HarnessError.missingPermission(
                "Permission prompts were requested. Accept them on the Mac, then rerun probe."
            )
        }
    }

    private func runProbe(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        run.addStep("resolve_target", status: "ok", detail: target.appURL.path)
        let appState = captureAppState(for: target)
        run.result.appState = appState
        run.addStep("probe_app_state", status: appState.installed ? "ok" : "warning", detail: "running=\(appState.running) windows=\(appState.windows.count)")
        let screenshotURL = run.runDirectory.appendingPathComponent("desktop.png")
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "desktop", stepName: "capture_desktop")
    }

    private func runAppBoot(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        guard FileManager.default.fileExists(atPath: target.appURL.path) else {
            throw HarnessError.appMissing("Target app not found at \(target.appURL.path)")
        }
        _ = try await relaunchApp(
            target,
            arguments: ["--harness-show-main-window"] + argumentList(from: run.command.arguments)
        )
        let appState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        run.result.appState = appState
        run.addStep("launch_app", status: "ok", detail: "windows=\(appState.windows.count)")
        let screenshotURL = run.runDirectory.appendingPathComponent("app_boot.png")
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "app_boot", stepName: "capture_desktop")
    }

    private func runTabWalk(_ run: HarnessRun) async throws {
        let tabs = ["customers", "estimates", "invoices", "expenses", "bills", "reports", "documents"]
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        for (index, tab) in tabs.enumerated() {
            _ = try await relaunchApp(
                target,
                arguments: ["--harness-show-main-window", "--harness-tab", tab]
            )
            let appState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
            try? await Task.sleep(nanoseconds: 800_000_000)
            run.result.appState = appState
            let filename = String(format: "%02d_%@.png", index + 1, tab)
            let screenshotURL = run.runDirectory.appendingPathComponent(filename)
            captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "tab:\(tab)", stepName: "capture_\(tab)")
        }
    }

    // Deeper UI sweep: every main tab at two window sizes, with an AX overflow scan
    // to auto-flag clipped/cut-off controls. Run with a long -TimeoutSeconds (e.g. 600).
    private func runTabWalkFull(_ run: HarnessRun) async throws {
        let tabs = ["customers", "estimates", "invoices", "salesreceipts", "expenses", "bills", "reports", "documents"]
        let sizes: [(String, CGSize)] = [
            ("wide", CGSize(width: 1440, height: 900)),
            ("compact", CGSize(width: 1024, height: 680))
        ]
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        var overflowLines: [String] = []
        for (index, tab) in tabs.enumerated() {
            _ = try await relaunchApp(target, arguments: ["--harness-show-main-window", "--harness-tab", tab])
            let appState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
            try? await Task.sleep(nanoseconds: 700_000_000)
            run.result.appState = appState
            let pid = appState.processIDs.first ?? 0
            for (sizeName, size) in sizes {
                if pid != 0 {
                    resizeLargestWindow(pid: pid, to: size)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                let filename = String(format: "%02d_%@_%@.png", index + 1, tab, sizeName)
                let url = run.runDirectory.appendingPathComponent(filename)
                captureDesktopIfPermitted(run, to: url, artifactKey: "tabfull:\(tab):\(sizeName)", stepName: "capture_\(tab)_\(sizeName)")
                if pid != 0 {
                    overflowLines.append(contentsOf: overflowFindings(pid: pid, label: "\(tab)/\(sizeName)"))
                }
            }
        }
        let reportURL = run.runDirectory.appendingPathComponent("overflow_report.txt")
        let body = overflowLines.isEmpty
            ? "No clipped/overflowing elements detected across tabs at tested sizes.\n"
            : overflowLines.joined(separator: "\n") + "\n"
        try? body.write(to: reportURL, atomically: true, encoding: .utf8)
        run.result.artifacts["overflow_report"] = reportURL.path
        run.addStep("overflow_scan", status: overflowLines.isEmpty ? "ok" : "warning", detail: "flags=\(overflowLines.count)")
    }

    // Walks the secondary Navigator areas not covered by tab_walk/tab_walk_full
    // (Home/workspace, Mail, Payees/vendors, Lists, Sync, Import, History, Settings).
    // Per-tab resilient: a route that fails to open a window is recorded as a failed
    // step (possible dead end) without aborting the rest of the walk.
    // Note: Help Me and Tech Support are separate windows (not AppTab tabs), so they
    // are not reachable via --harness-tab and are intentionally out of scope here.
    private func runTabWalkSecondary(_ run: HarnessRun) async throws {
        let tabs = ["workspace", "mail", "vendors", "lists", "sync", "import", "history", "settings"]
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        var failures = 0
        for (index, tab) in tabs.enumerated() {
            do {
                _ = try await relaunchApp(
                    target,
                    arguments: ["--harness-show-main-window", "--harness-tab", tab]
                )
                let appState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
                try? await Task.sleep(nanoseconds: 800_000_000)
                run.result.appState = appState
                let filename = String(format: "%02d_%@.png", index + 1, tab)
                let screenshotURL = run.runDirectory.appendingPathComponent(filename)
                captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "tab:\(tab)", stepName: "capture_\(tab)")
                let windowCount = appState.windows.count
                run.addStep("open_\(tab)", status: windowCount > 0 ? "ok" : "warning", detail: "windows=\(windowCount)")
                if windowCount == 0 { failures += 1 }
            } catch {
                failures += 1
                run.addStep("open_\(tab)", status: "failed", detail: "\(error)")
            }
        }
        run.addStep("secondary_walk_summary", status: failures == 0 ? "ok" : "warning", detail: "failures=\(failures)/\(tabs.count)")
    }

    private func axWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return [] }
        return wins
    }

    private func axFrame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(), CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private func resizeLargestWindow(pid: pid_t, to size: CGSize) {
        let wins = axWindows(pid: pid)
        guard let win = wins.max(by: { (axFrame($0)?.width ?? 0) < (axFrame($1)?.width ?? 0) }) else { return }
        var s = size
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v)
        }
    }

    private func overflowFindings(pid: pid_t, label: String) -> [String] {
        let wins = axWindows(pid: pid)
        guard let win = wins.max(by: { (axFrame($0)?.width ?? 0) < (axFrame($1)?.width ?? 0) }),
              let wf = axFrame(win) else { return [] }
        var flags: [String] = []
        func walk(_ el: AXUIElement, depth: Int) {
            if depth > 12 { return }
            if let f = axFrame(el), f.width > 1, f.height > 1 {
                if f.maxX > wf.maxX + 2 || f.maxY > wf.maxY + 2 {
                    var roleRef: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
                    var valRef: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valRef)
                    let role = (roleRef as? String) ?? "?"
                    let val = (valRef as? String) ?? ""
                    flags.append("[\(label)] \(role) clipped frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) win=\(Int(wf.width))x\(Int(wf.height)) \(val.prefix(40))")
                }
            }
            var kidsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
               let kids = kidsRef as? [AXUIElement] {
                for k in kids { walk(k, depth: depth + 1) }
            }
        }
        walk(win, depth: 0)
        return flags
    }

    private func runProveNavigationShell(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-prove-navigation-shell"
            ]
        )

        let appState = try await waitForWorkspaceWindowSet(
            target,
            requiredTitles: [
                "Customer Center / Register",
                "Report Center",
                "Historical QB P&L",
                "Renaissance Navigator"
            ],
            timeoutSeconds: run.command.timeoutSeconds
        )
        run.result.appState = appState
        run.addStep(
            "verify_launch_windows",
            status: "ok",
            detail: appState.windows.map { $0.windowName.isEmpty ? $0.ownerName : $0.windowName }.joined(separator: " | ")
        )

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let launchURL = run.runDirectory.appendingPathComponent("navigation_shell_launch.png")
        captureDesktopIfPermitted(run, to: launchURL, artifactKey: "navigation_shell_launch", stepName: "capture_launch")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "reports",
                "--harness-report-tab", "jobprofitability",
                "--harness-snapshot-path", run.runDirectory.appendingPathComponent("navigation_reports_route.png").path,
                "--harness-snapshot-delay", "2.5"
            ]
        )
        let reportState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        run.result.appState = reportState
        run.addStep("verify_report_route", status: "ok", detail: "windows=\(reportState.windows.count)")
        let reportURL = run.runDirectory.appendingPathComponent("navigation_reports_route.png")
        try? waitForFile(at: reportURL, timeoutSeconds: 8)
        if FileManager.default.fileExists(atPath: reportURL.path) {
            run.result.artifacts["navigation_reports_route"] = reportURL.path
            run.addStep("capture_report_route", status: "ok", detail: reportURL.lastPathComponent)
        }
    }

    private func runProveWindowRecovery(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let summaryURL = run.runDirectory.appendingPathComponent("window_recovery_summary.json")
        let screenshotURL = run.runDirectory.appendingPathComponent("window_recovery_after.png")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-prove-window-recovery",
                "--harness-window-recovery-summary-path", summaryURL.path,
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "4.0"
            ]
        )

        let appState = try await waitForWorkspaceWindowSet(
            target,
            requiredTitles: [
                "Customer Center / Register",
                "Report Center",
                "Historical QB P&L",
                "Renaissance Navigator"
            ],
            timeoutSeconds: run.command.timeoutSeconds
        )
        run.result.appState = appState
        try waitForFile(at: summaryURL, timeoutSeconds: 24)
        let summaryData = try Data(contentsOf: summaryURL)
        guard let summaryJSON = try JSONSerialization.jsonObject(with: summaryData) as? [String: Any],
              summaryJSON["allPassed"] as? Bool == true else {
            let detail = String(data: summaryData, encoding: .utf8) ?? summaryURL.path
            throw HarnessError.commandTimedOut("Window recovery proof did not pass: \(detail)")
        }
        run.result.artifacts["window_recovery_summary"] = summaryURL.path
        run.addStep("verify_window_recovery", status: "ok", detail: summaryURL.lastPathComponent)

        try? await Task.sleep(nanoseconds: 500_000_000)
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "window_recovery_after", stepName: "capture_window_recovery")
    }

    private func runCustomerEstimateView(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let ids = try resolveCustomerEstimateIDs(arguments: run.command.arguments)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "customers",
                "--harness-open-customer", String(ids.customerID)
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let beforeURL = run.runDirectory.appendingPathComponent("customer_estimate_before.png")
        captureDesktopIfPermitted(run, to: beforeURL, artifactKey: "customer_estimate_before", stepName: "capture_before")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "estimates",
                "--harness-edit-estimate", String(ids.estimateID)
            ]
        )
        let appState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 800_000_000)
        run.result.appState = appState
        let afterURL = run.runDirectory.appendingPathComponent("customer_estimate_after.png")
        captureDesktopIfPermitted(run, to: afterURL, artifactKey: "customer_estimate_after", stepName: "capture_after")
    }

    private func runCustomerInvoiceView(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let ids = try resolveCustomerInvoiceIDs(arguments: run.command.arguments)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "customers",
                "--harness-open-customer", String(ids.customerID)
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let beforeURL = run.runDirectory.appendingPathComponent("customer_invoice_before.png")
        captureDesktopIfPermitted(run, to: beforeURL, artifactKey: "customer_invoice_before", stepName: "capture_before")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "invoices",
                "--harness-edit-invoice", String(ids.invoiceID)
            ]
        )
        let appState = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 800_000_000)
        run.result.appState = appState
        let afterURL = run.runDirectory.appendingPathComponent("customer_invoice_after.png")
        captureDesktopIfPermitted(run, to: afterURL, artifactKey: "customer_invoice_after", stepName: "capture_after")
    }

    private func runPreviewEstimateTypeahead(_ run: HarnessRun) async throws {
        let estimateID = try requireInt64Argument("editEstimateID", in: run.command.arguments)
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let screenshotURL = run.runDirectory.appendingPathComponent("estimate_typeahead.png")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "estimates",
                "--harness-edit-estimate", String(estimateID),
                "--harness-preview-estimate-item-query", "por",
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "3.0"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try waitForFile(at: screenshotURL, timeoutSeconds: 12)
        run.result.artifacts["estimate_typeahead"] = screenshotURL.path
        run.addStep("preview_estimate_typeahead", status: "ok", detail: screenshotURL.lastPathComponent)
    }

    private func runPreviewInvoiceTypeahead(_ run: HarnessRun) async throws {
        let invoiceID = try requireInt64Argument("editInvoiceID", in: run.command.arguments)
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let screenshotURL = run.runDirectory.appendingPathComponent("invoice_typeahead.png")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "invoices",
                "--harness-edit-invoice", String(invoiceID),
                "--harness-preview-invoice-item-query", "por",
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "3.0"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try waitForFile(at: screenshotURL, timeoutSeconds: 12)
        run.result.artifacts["invoice_typeahead"] = screenshotURL.path
        run.addStep("preview_invoice_typeahead", status: "ok", detail: screenshotURL.lastPathComponent)
    }

    private func runPreviewWriteCheckTypeahead(_ run: HarnessRun) async throws {
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let screenshotURL = run.runDirectory.appendingPathComponent("write_check_typeahead.png")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "expenses",
                "--harness-open-write-check",
                "--harness-preview-write-check-payee-query", "robe",
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "3.0"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try waitForFile(at: screenshotURL, timeoutSeconds: 12)
        run.result.artifacts["write_check_typeahead"] = screenshotURL.path
        run.addStep("preview_write_check_typeahead", status: "ok", detail: screenshotURL.lastPathComponent)
    }

    private func runPreviewEstimateInvoiceProgress(_ run: HarnessRun) async throws {
        let ids = try resolveCustomerEstimateIDs(arguments: run.command.arguments)
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let screenshotURL = run.runDirectory.appendingPathComponent("estimate_invoice_progress.png")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "estimates",
                "--harness-open-estimate", String(ids.estimateID),
                "--harness-preview-estimate-invoice-progress-chooser",
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "4.0"
            ]
        )
        try waitForFile(at: screenshotURL, timeoutSeconds: 16)
        run.result.artifacts["estimate_invoice_progress"] = screenshotURL.path
        run.addStep("preview_estimate_invoice_progress", status: "ok", detail: screenshotURL.lastPathComponent)
    }

    private func runVerifyInvoiceManualDescription(_ run: HarnessRun) async throws {
        let ids = try resolveCustomerInvoiceIDs(arguments: run.command.arguments)
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        let screenshotURL = run.runDirectory.appendingPathComponent("verify_invoice_manual_description.png")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "invoices",
                "--harness-edit-invoice", String(ids.invoiceID),
                "--harness-verify-invoice-manual-description",
                "--harness-snapshot-path", screenshotURL.path,
                "--harness-snapshot-delay", "4.0"
            ]
        )
        try waitForFile(at: screenshotURL, timeoutSeconds: 16)
        run.result.artifacts["verify_invoice_manual_description"] = screenshotURL.path
        run.addStep("verify_invoice_manual_description", status: "ok", detail: screenshotURL.lastPathComponent)
    }

    private func runEmailEstimatePDF(_ run: HarnessRun) async throws {
        let ids = try resolveCustomerEstimateIDs(arguments: run.command.arguments)
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        try terminateApplications(named: "Mail")
        try terminateApplications(named: "Microsoft Outlook")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "customers",
                "--harness-open-customer", String(ids.customerID),
                "--harness-open-estimate", String(ids.estimateID),
                "--harness-email-estimate-on-open"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        let launched = try waitForRunningApplication(namedAnyOf: ["Microsoft Outlook", "Mail"], timeoutSeconds: 12)
        run.addStep("email_estimate_pdf", status: "ok", detail: "\(launched.localizedName ?? "Mail app") launched pid=\(launched.processIdentifier)")

        let screenshotURL = run.runDirectory.appendingPathComponent("estimate_email_mail.png")
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "estimate_email_mail", stepName: "capture_estimate_email")
        cleanupEmailDraftSurfaces(run: run)
    }

    private func runEmailInvoicePDF(_ run: HarnessRun) async throws {
        let ids = try resolveCustomerInvoiceIDs(arguments: run.command.arguments)
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        try terminateApplications(named: "Mail")
        try terminateApplications(named: "Microsoft Outlook")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "customers",
                "--harness-open-customer", String(ids.customerID),
                "--harness-open-invoice", String(ids.invoiceID),
                "--harness-email-invoice-on-open"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        let launched = try waitForRunningApplication(namedAnyOf: ["Microsoft Outlook", "Mail"], timeoutSeconds: 12)
        run.addStep("email_invoice_pdf", status: "ok", detail: "\(launched.localizedName ?? "Mail app") launched pid=\(launched.processIdentifier)")

        let screenshotURL = run.runDirectory.appendingPathComponent("invoice_email_mail.png")
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "invoice_email_mail", stepName: "capture_invoice_email")
        cleanupEmailDraftSurfaces(run: run)
    }

    private func runEmailFirstDocument(_ run: HarnessRun) async throws {
        try ensureAccessibilityPermission(run)
        let documentID = try lookupFirstDocumentID()
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        try terminateApplications(named: "Mail")
        try terminateApplications(named: "Microsoft Outlook")

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "documents",
                "--harness-email-document", String(documentID)
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let launched = try waitForRunningApplication(namedAnyOf: ["Microsoft Outlook", "Mail"], timeoutSeconds: 12)
        run.addStep("email_first_document", status: "ok", detail: "documentID=\(documentID) \(launched.localizedName ?? "Mail app") launched pid=\(launched.processIdentifier)")

        let screenshotURL = run.runDirectory.appendingPathComponent("document_email_mail.png")
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "document_email_mail", stepName: "capture_document_email")
        cleanupEmailDraftSurfaces(run: run)
    }

    private func runWriteScenarioSkeleton(_ run: HarnessRun) async throws {
        guard run.command.allowWrite else {
            throw HarnessError.unsupportedWriteScenario("Scenario \(run.command.scenario) requires allowWrite=true")
        }
        guard sandboxSupportDirectory(for: run.command) != nil else {
            throw HarnessError.unsupportedWriteScenario(
                "Write scenario \(run.command.scenario) requires arguments.sandboxSupportDir so Dad's live ledger is not mutated."
            )
        }

        let backupURL = try backupLiveDatabase(for: run.command)
        run.result.dbBackupPath = backupURL.path
        run.addStep("backup_sandbox_db", status: "ok", detail: backupURL.lastPathComponent)

        guard run.result.permissions.accessibility else {
            throw HarnessError.unsupportedWriteScenario(
                "Accessibility permission is required before \(run.command.scenario) can run interactively."
            )
        }
        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        switch run.command.scenario {
        case "edit_existing_estimate":
            try await runEditExistingEstimate(run, target: target)
        case "edit_existing_invoice":
            try await runEditExistingInvoice(run, target: target)
        case "write_check_draft":
            try await runWriteCheckDraft(run, target: target)
        case "reopen_saved_check":
            try await runReopenSavedCheck(run, target: target)
        case "prove_money_in_spine":
            try await runProveMoneyInSpine(run, target: target)
        case "prove_money_out_spine":
            try await runProveMoneyOutSpine(run, target: target)
        case "prove_job_costing":
            try await runProveJobCosting(run, target: target)
        case "prove_report_correctness":
            try await runProveReportCorrectness(run, target: target)
        case "prove_bank_reconciliation":
            try await runProveBankReconciliation(run, target: target)
        default:
            throw HarnessError.unsupportedWriteScenario("Unsupported write scenario \(run.command.scenario)")
        }
    }

    private func runApproveFirstOrderSheet(_ run: HarnessRun) async throws {
        guard run.command.allowWrite else {
            throw HarnessError.unsupportedWriteScenario("Scenario \(run.command.scenario) requires allowWrite=true")
        }
        guard sandboxSupportDirectory(for: run.command) != nil else {
            throw HarnessError.unsupportedWriteScenario(
                "Write scenario \(run.command.scenario) requires arguments.sandboxSupportDir so Dad's live ledger is not mutated."
            )
        }

        let initialEstimateCount = try estimateCount(for: run.command)
        let initialConvertedCount = try convertedOrderSheetCount(for: run.command)
        let backupURL = try backupLiveDatabase(for: run.command)
        run.result.dbBackupPath = backupURL.path
        run.addStep("backup_sandbox_db", status: "ok", detail: backupURL.lastPathComponent)

        let target = HarnessTargetApp(path: normalizedTargetPath(for: run.command))
        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "estimates",
                "--harness-approve-first-order-sheet"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)

        let estimateCountAfter = try waitForEstimateCount(
            above: initialEstimateCount,
            command: run.command,
            timeoutSeconds: 30
        )
        let convertedCountAfter = try convertedOrderSheetCount(for: run.command)
        guard convertedCountAfter > initialConvertedCount else {
            throw HarnessError.commandTimedOut("Order sheet was not marked converted after approval")
        }
        run.addStep(
            "approve_first_order_sheet",
            status: "ok",
            detail: "estimates_before=\(initialEstimateCount) estimates_after=\(estimateCountAfter) converted_before=\(initialConvertedCount) converted_after=\(convertedCountAfter)"
        )

        let screenshotURL = run.runDirectory.appendingPathComponent("approve_first_order_sheet.png")
        captureDesktopIfPermitted(run, to: screenshotURL, artifactKey: "approve_first_order_sheet", stepName: "capture_after")
    }

    private func relaunchApp(_ target: HarnessTargetApp, arguments: [String]) async throws -> NSRunningApplication {
        try terminateRunningAppIfNeeded(target)
        try? await Task.sleep(nanoseconds: 900_000_000)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        try persistLedgerLaunchState(from: arguments)
        config.arguments = passthroughLaunchArguments(from: arguments)
        if let command = activeCommand, let supportDirectory = sandboxSupportDirectory(for: command) {
            var environment = ProcessInfo.processInfo.environment
            environment["RENAISSANCE_LEDGER_SUPPORT_DIR"] = supportDirectory.path
            environment["RENAISSANCE_LEDGER_DB_PATH"] = supportDirectory.appendingPathComponent("ledger.sqlite").path
            environment["RENAISSANCE_LEDGER_SANDBOX_MODE"] = "1"
            config.environment = environment
        } else if let supportDirectory = sandboxSupportDirectoryFromLaunchArguments(arguments) {
            var environment = ProcessInfo.processInfo.environment
            environment["RENAISSANCE_LEDGER_SUPPORT_DIR"] = supportDirectory.path
            environment["RENAISSANCE_LEDGER_DB_PATH"] = supportDirectory.appendingPathComponent("ledger.sqlite").path
            environment["RENAISSANCE_LEDGER_SANDBOX_MODE"] = "1"
            config.environment = environment
        }

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: target.appURL, configuration: config) { app, error in
                if let error {
                    continuation.resume(throwing: HarnessError.appLaunchFailed(error.localizedDescription))
                    return
                }
                guard let app else {
                    continuation.resume(throwing: HarnessError.appLaunchFailed("App launch returned no running application"))
                    return
                }
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                continuation.resume(returning: app)
            }
        }
    }

    private func terminateRunningAppIfNeeded(_ target: HarnessTargetApp) throws {
        let runningApps = runningApplications(for: target)
        for app in runningApps {
            if !app.isTerminated {
                _ = app.terminate()
                let deadline = Date().addingTimeInterval(6)
                while !app.isTerminated && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                }
                if !app.isTerminated {
                    _ = app.forceTerminate()
                }
            }
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if runningApplications(for: target).isEmpty {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func waitForVisibleWindow(_ target: HarnessTargetApp, timeoutSeconds: Int) async throws -> HarnessAppState {
        let deadline = Date().addingTimeInterval(TimeInterval(max(timeoutSeconds, 10)))
        while Date() < deadline {
            let appState = captureAppState(for: target)
            if appState.running && !appState.windows.isEmpty {
                return appState
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        throw HarnessError.windowNotVisible("No visible \(target.displayName) window was detected before timeout")
    }

    private func waitForWorkspaceWindowSet(
        _ target: HarnessTargetApp,
        requiredTitles: [String],
        timeoutSeconds: Int
    ) async throws -> HarnessAppState {
        let deadline = Date().addingTimeInterval(TimeInterval(max(timeoutSeconds, 10)))
        while Date() < deadline {
            let appState = captureAppState(for: target)
            let titles = Set(appState.windows.map(\.windowName).filter { !$0.isEmpty })
            if appState.running && requiredTitles.allSatisfy({ titles.contains($0) }) {
                return appState
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        throw HarnessError.windowNotVisible("Required workspace windows were not visible: \(requiredTitles.joined(separator: ", "))")
    }

    private func captureAppState(for target: HarnessTargetApp) -> HarnessAppState {
        let installed = FileManager.default.fileExists(atPath: target.appURL.path)
        let runningApps = runningApplications(for: target)
        let windows = captureWindows(for: target, runningApps: runningApps)
        return HarnessAppState(
            installed: installed,
            displayName: target.displayName,
            bundleIdentifier: target.bundleIdentifier,
            targetAppPath: target.appURL.path,
            running: !runningApps.isEmpty,
            processIDs: runningApps.map(\.processIdentifier),
            windows: windows
        )
    }

    private func runningApplications(for target: HarnessTargetApp) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            if !target.bundleIdentifier.isEmpty, app.bundleIdentifier == target.bundleIdentifier {
                return true
            }
            return app.bundleURL?.path == target.appURL.path
        }
    }

    private func captureWindows(for target: HarnessTargetApp, runningApps: [NSRunningApplication]) -> [HarnessWindowSnapshot] {
        let processIDs = Set(runningApps.map(\.processIdentifier))
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windowInfo.compactMap { item in
            let ownerPID = item[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let ownerName = item[kCGWindowOwnerName as String] as? String ?? ""
            guard processIDs.contains(ownerPID) || ownerName == target.displayName else {
                return nil
            }

            let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
            return HarnessWindowSnapshot(
                ownerName: ownerName,
                windowName: item[kCGWindowName as String] as? String ?? "",
                windowID: item[kCGWindowNumber as String] as? Int ?? 0,
                layer: item[kCGWindowLayer as String] as? Int ?? 0,
                alpha: item[kCGWindowAlpha as String] as? Double ?? 1,
                bounds: bounds.reduce(into: [:]) { partialResult, entry in
                    if let number = entry.value as? Double {
                        partialResult[entry.key] = number
                    } else if let number = entry.value as? NSNumber {
                        partialResult[entry.key] = number.doubleValue
                    }
                }
            )
        }
    }

    private func captureDesktop(to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessError.commandTimedOut("Desktop screenshot capture failed")
        }
    }

    private func captureDesktopIfPermitted(_ run: HarnessRun, to url: URL, artifactKey: String, stepName: String) {
        guard run.result.permissions.screenRecording else {
            run.addStep(
                "permission_screen_recording",
                status: "warning",
                detail: "Screen Recording is not granted. Visual artifact capture was skipped."
            )
            return
        }
        do {
            try captureDesktop(to: url)
            run.result.artifacts[artifactKey] = url.path
            run.addStep(stepName, status: "ok", detail: url.lastPathComponent)
        } catch {
            run.addStep(stepName, status: "failed", detail: error.localizedDescription)
        }
    }

    private func recommendedOrderSheetInboxURL() -> URL {
        if let command = activeCommand,
           let supportDirectory = sandboxSupportDirectory(for: command) {
            return supportDirectory.appendingPathComponent("inbox", isDirectory: true)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloudRoot = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
        return iCloudRoot
            .appendingPathComponent("Renaissance Filed", isDirectory: true)
            .appendingPathComponent("Order Sheet Inbox", isDirectory: true)
    }

    private func ensureAccessibilityPermission(_ run: HarnessRun) throws {
        guard run.result.permissions.accessibility else {
            run.addStep(
                "permission_accessibility",
                status: "failed",
                detail: "Grant Accessibility to Renaissance Harness.app before interactive flows."
            )
            throw HarnessError.missingPermission(
                "Accessibility permission is required for interactive flows. Open Renaissance Harness > Open Accessibility Settings."
            )
        }
    }

    private func runEditExistingEstimate(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        try ensureAccessibilityPermission(run)
        let ids = try resolveCustomerEstimateIDs(arguments: run.command.arguments)
        let originalMemo = try lookupEstimateMemo(estimateID: ids.estimateID)
        let newMemo = "Harness edit \(run.command.id.prefix(8))"

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "estimates",
                "--harness-edit-estimate", String(ids.estimateID),
                "--harness-update-estimate-memo", String(ids.estimateID), newMemo
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        run.addStep("edit_estimate", status: "ok", detail: "Updated estimate \(ids.estimateID) memo through sandbox app hook")

        let memoAfterSave = try lookupEstimateMemo(estimateID: ids.estimateID)
        guard memoAfterSave == newMemo else {
            throw HarnessError.commandTimedOut("Estimate memo did not persist after save")
        }
        run.addStep("verify_estimate_save", status: "ok", detail: "Memo persisted")

        let screenshotURL = run.runDirectory.appendingPathComponent("edit_existing_estimate_after.png")
        if run.result.permissions.screenRecording {
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["edit_existing_estimate_after"] = screenshotURL.path
            run.addStep("capture_after", status: "ok", detail: screenshotURL.lastPathComponent)
        }

        try updateEstimateMemo(estimateID: ids.estimateID, memo: originalMemo)
        run.addStep("restore_estimate", status: "ok", detail: "Restored original memo")
    }

    private func runEditExistingInvoice(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        try ensureAccessibilityPermission(run)
        let ids = try resolveCustomerInvoiceIDs(arguments: run.command.arguments)
        let originalMemo = try lookupInvoiceMemo(invoiceID: ids.invoiceID)
        let newMemo = "Harness invoice \(run.command.id.prefix(8))"

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "invoices",
                "--harness-edit-invoice", String(ids.invoiceID),
                "--harness-update-invoice-memo", String(ids.invoiceID), newMemo
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        run.addStep("edit_invoice", status: "ok", detail: "Updated invoice \(ids.invoiceID) memo through sandbox app hook")

        let memoAfterSave = try lookupInvoiceMemo(invoiceID: ids.invoiceID)
        guard memoAfterSave == newMemo else {
            throw HarnessError.commandTimedOut("Invoice memo did not persist after save")
        }
        run.addStep("verify_invoice_save", status: "ok", detail: "Memo persisted")

        let screenshotURL = run.runDirectory.appendingPathComponent("edit_existing_invoice_after.png")
        if run.result.permissions.screenRecording {
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["edit_existing_invoice_after"] = screenshotURL.path
            run.addStep("capture_after", status: "ok", detail: screenshotURL.lastPathComponent)
        }

        try updateInvoiceMemo(invoiceID: ids.invoiceID, memo: originalMemo)
        run.addStep("restore_invoice", status: "ok", detail: "Restored original memo")
    }

    private func runWriteCheckDraft(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        try ensureAccessibilityPermission(run)
        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "expenses",
                "--harness-open-write-check"
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        run.addStep("open_write_check", status: "ok", detail: "Requested Write Check flow through harness launch state")

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("write_check_draft.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["write_check_draft"] = screenshotURL.path
            run.addStep("capture_write_check", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func runReopenSavedCheck(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        try ensureAccessibilityPermission(run)
        let expenseID = try lookupFirstExpenseIDWithCheck()
        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "expenses",
                "--harness-open-expense", String(expenseID)
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        _ = try waitForElement(identifier: "writeCheck.sheet", timeoutSeconds: 8)
        run.addStep("open_saved_check", status: "ok", detail: "Opened saved check expense \(expenseID)")

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("reopen_saved_check.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["reopen_saved_check"] = screenshotURL.path
            run.addStep("capture_saved_check", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func runProveMoneyInSpine(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        let token = "SANDBOX-\(String(run.command.id.prefix(12)))"
        let before = try moneyInSpineTableCounts()
        run.addStep("money_in_before", status: "ok", detail: before)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "bills",
                "--harness-prove-money-in-spine", token
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)

        let summary = try waitForMoneyInProofSummary(
            token: token,
            timeoutSeconds: min(max(run.command.timeoutSeconds, 20), 60)
        )
        try assertMoneyInProof(summary: summary)
        run.addStep("prove_money_in_spine", status: "ok", detail: summary.joined(separator: " ; "))

        let after = try moneyInSpineTableCounts()
        run.addStep("money_in_after", status: "ok", detail: after)

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("prove_money_in_spine.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["prove_money_in_spine"] = screenshotURL.path
            run.addStep("capture_money_in", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func runProveMoneyOutSpine(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        let token = "SANDBOX-\(String(run.command.id.prefix(12)))"
        let before = try moneyOutSpineTableCounts()
        run.addStep("money_out_before", status: "ok", detail: before)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "bills",
                "--harness-prove-money-out-spine", token
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)

        let summary = try waitForMoneyOutProofSummary(
            token: token,
            timeoutSeconds: min(max(run.command.timeoutSeconds, 20), 60)
        )
        try assertMoneyOutProof(summary: summary)
        run.addStep("prove_money_out_spine", status: "ok", detail: summary.joined(separator: " ; "))

        let after = try moneyOutSpineTableCounts()
        run.addStep("money_out_after", status: "ok", detail: after)

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("prove_money_out_spine.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["prove_money_out_spine"] = screenshotURL.path
            run.addStep("capture_money_out", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func runProveJobCosting(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        let token = "SANDBOX-\(String(run.command.id.prefix(12)))"
        let before = try jobCostingTableCounts()
        run.addStep("job_costing_before", status: "ok", detail: before)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "reports",
                "--harness-prove-job-costing", token
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)

        let summary = try waitForJobCostingProofSummary(
            token: token,
            timeoutSeconds: min(max(run.command.timeoutSeconds, 20), 60)
        )
        try assertJobCostingProof(summary: summary)
        run.addStep("prove_job_costing", status: "ok", detail: summary.joined(separator: " ; "))

        let after = try jobCostingTableCounts()
        run.addStep("job_costing_after", status: "ok", detail: after)

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("prove_job_costing.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["prove_job_costing"] = screenshotURL.path
            run.addStep("capture_job_costing", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func runProveReportCorrectness(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        let token = "SANDBOX-\(String(run.command.id.prefix(12)))"
        let before = try reportCorrectnessTableCounts()
        run.addStep("report_correctness_before", status: "ok", detail: before)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "reports",
                "--harness-report-tab", "operational",
                "--harness-prove-report-correctness", token
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)

        let summary = try waitForReportCorrectnessProofSummary(
            token: token,
            timeoutSeconds: min(max(run.command.timeoutSeconds, 20), 60)
        )
        try assertReportCorrectnessProof(summary: summary)
        run.addStep("prove_report_correctness", status: "ok", detail: summary.joined(separator: " ; "))

        let after = try reportCorrectnessTableCounts()
        run.addStep("report_correctness_after", status: "ok", detail: after)

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("prove_report_correctness.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["prove_report_correctness"] = screenshotURL.path
            run.addStep("capture_report_correctness", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func runProveBankReconciliation(_ run: HarnessRun, target: HarnessTargetApp) async throws {
        let token = "SANDBOX-\(String(run.command.id.prefix(12)))"
        let before = try bankReconciliationTableCounts()
        run.addStep("bank_reconciliation_before", status: "ok", detail: before)

        _ = try await relaunchApp(
            target,
            arguments: [
                "--harness-show-main-window",
                "--harness-tab", "reports",
                "--harness-report-tab", "reconciliation",
                "--harness-prove-bank-reconciliation", token
            ]
        )
        _ = try await waitForVisibleWindow(target, timeoutSeconds: run.command.timeoutSeconds)

        let summary = try waitForBankReconciliationProofSummary(
            token: token,
            timeoutSeconds: min(max(run.command.timeoutSeconds, 20), 60)
        )
        try assertBankReconciliationProof(summary: summary)
        run.addStep("prove_bank_reconciliation", status: "ok", detail: summary.joined(separator: " ; "))

        let after = try bankReconciliationTableCounts()
        run.addStep("bank_reconciliation_after", status: "ok", detail: after)

        if run.result.permissions.screenRecording {
            let screenshotURL = run.runDirectory.appendingPathComponent("prove_bank_reconciliation.png")
            try captureDesktop(to: screenshotURL)
            run.result.artifacts["prove_bank_reconciliation"] = screenshotURL.path
            run.addStep("capture_bank_reconciliation", status: "ok", detail: screenshotURL.lastPathComponent)
        }
    }

    private func bankReconciliationTableCounts() throws -> String {
        let dbURL = ledgerDatabaseURL()
        let sql = """
        SELECT 'gl_accounts=' || (SELECT COUNT(*) FROM gl_accounts)
            || ' expenses=' || (SELECT COUNT(*) FROM expenses)
            || ' deposit_records=' || (SELECT COUNT(*) FROM deposit_records)
            || ' reconciliations=' || (SELECT COUNT(*) FROM reconciliations);
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForBankReconciliationProofSummary(token: String, timeoutSeconds: Int) throws -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let summary = try fetchBankReconciliationProofSummary(token: token)
            if summary.count == 3 {
                return summary
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for sandbox bank-reconciliation proof rows")
    }

    private func fetchBankReconciliationProofSummary(token: String) throws -> [String] {
        let dbURL = ledgerDatabaseURL()
        let accountName = sqliteQuoted("SANDBOX Bank \(token)")
        // HAVING COUNT(*) > 0 so each aggregate row is emitted only once the
        // app has seeded + committed the proof (otherwise the count never grows).
        let sql = """
        SELECT 'recon|' || COUNT(*) || '|' || printf('%.2f', COALESCE(MAX(r.ending_balance), 0))
            || '|' || COALESCE(MAX(r.status), '') || '|' || printf('%.2f', COALESCE(MAX(r.cleared_total), 0))
        FROM reconciliations r
        JOIN gl_accounts a ON a.id = r.account_id
        WHERE a.name = \(accountName)
        HAVING COUNT(*) > 0;

        SELECT 'checks|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(e.amount), 0))
        FROM expenses e
        JOIN gl_accounts a ON a.id = e.payment_account_id
        WHERE a.name = \(accountName)
          AND e.cleared = 1
          AND e.reconciliation_id IS NOT NULL
        HAVING COUNT(*) > 0;

        SELECT 'deposit|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(d.total_amount), 0))
        FROM deposit_records d
        JOIN gl_accounts a ON a.id = d.account_id
        WHERE a.name = \(accountName)
          AND d.cleared = 1
          AND d.reconciliation_id IS NOT NULL
        HAVING COUNT(*) > 0;
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func assertBankReconciliationProof(summary: [String]) throws {
        let rows = Dictionary(uniqueKeysWithValues: summary.compactMap { row -> (String, [String])? in
            let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { return nil }
            return (key, parts)
        })

        guard let recon = rows["recon"], recon.count == 5,
              recon[1] == "1",
              recon[2] == "250.00",
              recon[3] == "reconciled",
              recon[4] == "250.00" else {
            throw HarnessError.commandTimedOut("Bank reconciliation proof header was not committed correctly: \(summary)")
        }

        guard let checks = rows["checks"], checks.count == 3,
              checks[1] == "2",
              checks[2] == "150.00" else {
            throw HarnessError.commandTimedOut("Bank reconciliation proof did not clear both checks: \(summary)")
        }

        guard let deposit = rows["deposit"], deposit.count == 3,
              deposit[1] == "1",
              deposit[2] == "400.00" else {
            throw HarnessError.commandTimedOut("Bank reconciliation proof did not clear the deposit: \(summary)")
        }
    }

    private func performEstimateEdit(newMemo: String) throws {
        let editWindow = try waitForElement(identifier: "estimate.editSheet", timeoutSeconds: 8)
        try fillTextFieldValue(identifier: "estimate.memoField", with: newMemo, in: editWindow)
        try pressButton(identifier: "estimate.saveButton", in: editWindow)
    }

    private func performInvoiceEdit(newMemo: String) throws {
        let editWindow = try waitForElement(identifier: "invoice.editSheet", timeoutSeconds: 8)
        try fillTextFieldValue(identifier: "invoice.memoField", with: newMemo, in: editWindow)
        try pressButton(identifier: "invoice.saveButton", in: editWindow)
    }

    private func requireFrontmostTargetApp() throws -> AXUIElement {
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            let name = $0.localizedName ?? ""
            return name.contains("Renaissance Filed") || name.contains("Renaissance Ledger")
        }
        guard let app = runningApps.first else {
            throw HarnessError.appLaunchFailed("Renaissance Filed is not running")
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func requireMainWindow(of app: AXUIElement) throws -> AXUIElement {
        if let windowRef = try? copyAttribute(app, attribute: kAXFocusedWindowAttribute) {
            let window = unsafeBitCast(windowRef, to: AXUIElement.self)
            return window
        }
        let windows = (try? copyAttribute(app, attribute: kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let window = windows.first else {
            throw HarnessError.windowNotVisible("No main window was found through Accessibility")
        }
        return window
    }

    private func requireWindowContaining(identifier prefix: String, in app: AXUIElement) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let windows = (try? copyAttribute(app, attribute: kAXWindowsAttribute) as? [AXUIElement]) ?? []
            for window in windows {
                let element = try? findElement(matchingIdentifierPrefix: prefix, under: window)
                if element != nil {
                    return window
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw HarnessError.windowNotVisible("No window containing accessibility identifier prefix \(prefix) was found")
    }

    private func waitForElement(identifier: String, timeoutSeconds: Int) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            guard let app = try? requireFrontmostTargetApp() else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                continue
            }
            let windows = (try? copyAttribute(app, attribute: kAXWindowsAttribute) as? [AXUIElement]) ?? []
            for window in windows {
                if let element = try? findElement(matchingIdentifier: identifier, under: window) {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for accessibility element \(identifier)")
    }

    private func pressButton(identifier: String, in root: AXUIElement) throws {
        guard let button = try findElement(matchingIdentifier: identifier, under: root) else {
            throw HarnessError.commandTimedOut("Could not find button \(identifier)")
        }
        try performPress(on: button)
    }

    private func performPress(on element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw HarnessError.commandTimedOut("Press action failed with AX error \(result.rawValue)")
        }
    }

    private func fillTextFieldValue(identifier: String, with value: String, in root: AXUIElement) throws {
        guard let field = try findElement(matchingIdentifier: identifier, under: root) else {
            throw HarnessError.commandTimedOut("Could not find text field \(identifier)")
        }
        let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, value as CFTypeRef)
        guard result == .success else {
            throw HarnessError.commandTimedOut("Setting text field value failed with AX error \(result.rawValue)")
        }
    }

    private func enterInteractiveText(_ value: String, into identifier: String, in root: AXUIElement) throws {
        guard let field = try findElement(matchingIdentifier: identifier, under: root) else {
            throw HarnessError.commandTimedOut("Could not find text field \(identifier)")
        }
        try focusElement(field)
        _ = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFTypeRef)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try typeText(value)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private func focusTextField(identifier: String, in root: AXUIElement) throws {
        guard let field = try findElement(matchingIdentifier: identifier, under: root) else {
            throw HarnessError.commandTimedOut("Could not find text field \(identifier)")
        }
        try focusElement(field)
    }

    private func readTextFieldValue(identifier: String, in root: AXUIElement) throws -> String {
        guard let field = try findElement(matchingIdentifier: identifier, under: root) else {
            throw HarnessError.commandTimedOut("Could not find text field \(identifier)")
        }
        let rawValue = try copyAttribute(field, attribute: kAXValueAttribute)
        return rawValue as? String ?? ""
    }

    private func waitForTextFieldValue(
        identifier: String,
        in root: AXUIElement,
        timeoutSeconds: Int,
        matcher: (String) -> Bool
    ) throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let value = (try? readTextFieldValue(identifier: identifier, in: root)) ?? ""
            if matcher(value) {
                return value
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for text field \(identifier) to reach the expected value")
    }

    private func focusElement(_ element: AXUIElement) throws {
        let focusResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard focusResult == .success || focusResult == .attributeUnsupported else {
            throw HarnessError.commandTimedOut("Focusing accessibility element failed with AX error \(focusResult.rawValue)")
        }
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    private func typeText(_ value: String) throws {
        for scalar in value.unicodeScalars {
            guard
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw HarnessError.commandTimedOut("Could not create keyboard events for typing")
            }

            var utf16Units = Array(String(scalar).utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
            keyUp.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
    }

    private func waitForFile(at url: URL, timeoutSeconds: Int) throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for file \(url.lastPathComponent)")
    }

    private func findElement(matchingIdentifier identifier: String, under root: AXUIElement) throws -> AXUIElement? {
        try findElements(role: nil, matchingIdentifierPrefix: identifier, exactMatch: true, under: root).first
    }

    private func findElement(matchingIdentifierPrefix prefix: String, under root: AXUIElement) throws -> AXUIElement? {
        try findElements(role: nil, matchingIdentifierPrefix: prefix, exactMatch: false, under: root).first
    }

    private func findElements(
        role: String?,
        matchingIdentifierPrefix prefix: String?,
        exactMatch: Bool = false,
        under root: AXUIElement
    ) throws -> [AXUIElement] {
        var results: [AXUIElement] = []
        try traverseAccessibilityTree(root) { element in
            if let role, let value = try copyAttribute(element, attribute: kAXRoleAttribute) as? String, value != role {
                return
            }

            if let prefix {
                let identifier = (try? copyAttribute(element, attribute: kAXIdentifierAttribute) as? String) ?? nil
                let matches = exactMatch ? (identifier == prefix) : (identifier?.hasPrefix(prefix) == true)
                if matches {
                    results.append(element)
                }
            } else {
                results.append(element)
            }
        }
        return results
    }

    private func dumpAccessibilityTree(_ root: AXUIElement, to url: URL) throws {
        var lines: [String] = []
        try appendAccessibilityLines(for: root, depth: 0, into: &lines)
        let payload = lines.joined(separator: "\n")
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendAccessibilityLines(for element: AXUIElement, depth: Int, into lines: inout [String]) throws {
        let indent = String(repeating: "  ", count: depth)
        let role = (try? copyAttribute(element, attribute: kAXRoleAttribute) as? String) ?? "?"
        let subrole = (try? copyAttribute(element, attribute: kAXSubroleAttribute) as? String) ?? ""
        let identifier = (try? copyAttribute(element, attribute: kAXIdentifierAttribute) as? String) ?? ""
        let title = (try? copyAttribute(element, attribute: kAXTitleAttribute) as? String) ?? ""
        let description = (try? copyAttribute(element, attribute: kAXDescriptionAttribute) as? String) ?? ""
        let help = (try? copyAttribute(element, attribute: kAXHelpAttribute) as? String) ?? ""
        let value = (try? copyAttribute(element, attribute: kAXValueAttribute)) .flatMap { stringifyAccessibilityValue($0) } ?? ""

        let parts = [
            "role=\(role)",
            subrole.isEmpty ? nil : "subrole=\(subrole)",
            identifier.isEmpty ? nil : "id=\(identifier)",
            title.isEmpty ? nil : "title=\(title)",
            description.isEmpty ? nil : "desc=\(description)",
            help.isEmpty ? nil : "help=\(help)",
            value.isEmpty ? nil : "value=\(value)"
        ].compactMap { $0 }

        lines.append("\(indent)- \(parts.joined(separator: " | "))")

        let children = try copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children {
            try appendAccessibilityLines(for: child, depth: depth + 1, into: &lines)
        }
    }

    private func stringifyAccessibilityValue(_ value: AnyObject) -> String {
        if let text = value as? String {
            return text
        }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return "<AXUIElement>"
        }
        return String(describing: value)
    }

    private func traverseAccessibilityTree(_ root: AXUIElement, visit: (AXUIElement) throws -> Void) throws {
        try visit(root)
        let children = try copyAttribute(root, attribute: kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children {
            try traverseAccessibilityTree(child, visit: visit)
        }
    }

    private func copyAttribute(_ element: AXUIElement, attribute: String) throws -> AnyObject? {
        var lastResult: AXError = .success
        for attempt in 0..<8 {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if result == .success {
                return value
            }
            if result == .noValue || result == .attributeUnsupported {
                return nil
            }
            lastResult = result
            if result == .cannotComplete && attempt < 7 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                continue
            }
        }
        throw HarnessError.commandTimedOut("AX copy attribute \(attribute) failed with \(lastResult.rawValue)")
    }

    private func lookupEstimateMemo(estimateID: Int64) throws -> String {
        try fetchScalarText(sql: "SELECT COALESCE(memo, '') FROM estimates WHERE id = ?", id: estimateID)
    }

    private func updateEstimateMemo(estimateID: Int64, memo: String) throws {
        try updateScalarText(sql: "UPDATE estimates SET memo = ?, updated_at = datetime('now') WHERE id = ?", value: memo, id: estimateID)
    }

    private func lookupInvoiceMemo(invoiceID: Int64) throws -> String {
        try fetchScalarText(sql: "SELECT COALESCE(memo, '') FROM native_invoices WHERE id = ?", id: invoiceID)
    }

    private func updateInvoiceMemo(invoiceID: Int64, memo: String) throws {
        try updateScalarText(sql: "UPDATE native_invoices SET memo = ?, updated_at = datetime('now') WHERE id = ?", value: memo, id: invoiceID)
    }

    private func lookupInvoiceLineCount(invoiceID: Int64) throws -> Int {
        try fetchScalarInt(sql: "SELECT COUNT(*) FROM invoice_lines WHERE invoice_id = ?", id: invoiceID)
    }

    private func lookupVerificationServiceItemNames() throws -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(ledgerDatabaseURL().path, &db) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not open ledger database")
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT name
        FROM service_items
        WHERE TRIM(COALESCE(name, '')) <> ''
        ORDER BY
            CASE
                WHEN name = 'BristowLabor1' THEN 0
                WHEN name = 'BristowLabor2' THEN 1
                ELSE 2
            END,
            LENGTH(name),
            name
        LIMIT 2;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not prepare service-item verification query")
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let rawName = sqlite3_column_text(statement, 0) {
                names.append(String(cString: rawName))
            }
        }
        return names
    }

    private func fetchScalarText(sql: String, id: Int64) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open(ledgerDatabaseURL().path, &db) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not open ledger database")
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not prepare lookup statement")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HarnessError.missingRecord("Requested row was not found")
        }
        return String(cString: sqlite3_column_text(statement, 0))
    }

    private func fetchScalarInt(sql: String, id: Int64) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(ledgerDatabaseURL().path, &db) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not open ledger database")
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not prepare lookup statement")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HarnessError.missingRecord("Requested row was not found")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func updateScalarText(sql: String, value: String, id: Int64) throws {
        var db: OpaquePointer?
        guard sqlite3_open(ledgerDatabaseURL().path, &db) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not open ledger database")
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HarnessError.commandTimedOut("Could not prepare update statement")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw HarnessError.commandTimedOut("Update statement did not complete")
        }
    }

    private func resolveCustomerEstimateIDs(arguments: [String: String]) throws -> (customerID: Int64, estimateID: Int64) {
        if let customerID = Int64(arguments["customerID"] ?? ""),
           let estimateID = Int64(arguments["estimateID"] ?? "") {
            return (customerID, estimateID)
        }

        let dbURL = ledgerDatabaseURL()
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT customer_id || '|' || id FROM estimates ORDER BY issue_date DESC, id DESC LIMIT 1;"]
        )
        let values = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
        guard values.count == 2, let customerID = Int64(values[0]), let estimateID = Int64(values[1]) else {
            throw HarnessError.missingRecord("No estimate row was found in the live database")
        }
        return (customerID, estimateID)
    }

    private func requireInt64Argument(_ key: String, in arguments: [String: String]) throws -> Int64 {
        guard let rawValue = arguments[key], let value = Int64(rawValue) else {
            throw HarnessError.invalidCommand("Missing or invalid \(key)")
        }
        return value
    }

    private func resolveCustomerInvoiceIDs(arguments: [String: String]) throws -> (customerID: Int64, invoiceID: Int64) {
        if let customerID = Int64(arguments["customerID"] ?? ""),
           let invoiceID = Int64(arguments["invoiceID"] ?? "") {
            return (customerID, invoiceID)
        }

        let dbURL = ledgerDatabaseURL()
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT customer_id || '|' || id FROM native_invoices ORDER BY issue_date DESC, id DESC LIMIT 1;"]
        )
        let values = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
        guard values.count == 2, let customerID = Int64(values[0]), let invoiceID = Int64(values[1]) else {
            throw HarnessError.missingRecord("No invoice row was found in the live database")
        }
        return (customerID, invoiceID)
    }

    private func lookupFirstDocumentID() throws -> Int64 {
        let dbURL = ledgerDatabaseURL()
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT id FROM documents ORDER BY id DESC LIMIT 1;"]
        )
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let documentID = Int64(value) else {
            throw HarnessError.missingRecord("No document row was found in the live database")
        }
        return documentID
    }

    private func lookupFirstExpenseIDWithCheck() throws -> Int64 {
        let dbURL = ledgerDatabaseURL()
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT id FROM expenses WHERE TRIM(COALESCE(check_number, '')) <> '' ORDER BY expense_date DESC, id DESC LIMIT 1;"]
        )
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expenseID = Int64(value) else {
            throw HarnessError.missingRecord("No saved check expense row was found in the sandbox database")
        }
        return expenseID
    }

    private func orderSheetStagingDatabaseURL(for command: HarnessCommand? = nil) -> URL {
        let command = command ?? activeCommand
        if let command, let supportDirectory = sandboxSupportDirectory(for: command) {
            return supportDirectory.appendingPathComponent("order-sheet-staging.sqlite")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("RenaissanceLedger/order-sheet-staging.sqlite")
    }

    private func orderSheetStagingCount(for command: HarnessCommand? = nil) throws -> Int {
        let dbURL = orderSheetStagingDatabaseURL(for: command)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return 0
        }
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT COUNT(*) FROM order_sheets;"]
        )
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func convertedOrderSheetCount(for command: HarnessCommand? = nil) throws -> Int {
        let dbURL = orderSheetStagingDatabaseURL(for: command)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return 0
        }
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT COUNT(*) FROM order_sheets WHERE status = 'converted' AND COALESCE(linked_estimate_id, 0) <> 0;"]
        )
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func estimateCount(for command: HarnessCommand? = nil) throws -> Int {
        let dbURL = ledgerDatabaseURL(for: command)
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [dbURL.path, "SELECT COUNT(*) FROM estimates;"]
        )
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func moneyInSpineTableCounts() throws -> String {
        let dbURL = ledgerDatabaseURL()
        let sql = """
        SELECT 'customers=' || (SELECT COUNT(*) FROM customers)
            || ' jobs=' || (SELECT COUNT(*) FROM jobs)
            || ' estimates=' || (SELECT COUNT(*) FROM estimates)
            || ' invoices=' || (SELECT COUNT(*) FROM native_invoices)
            || ' payments=' || (SELECT COUNT(*) FROM payments_received)
            || ' applications=' || (SELECT COUNT(*) FROM payment_applications)
            || ' deposits=' || (SELECT COUNT(*) FROM deposit_records)
            || ' deposit_lines=' || (SELECT COUNT(*) FROM deposit_record_lines);
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func moneyOutSpineTableCounts() throws -> String {
        let dbURL = ledgerDatabaseURL()
        let sql = """
        SELECT 'vendors=' || (SELECT COUNT(*) FROM vendors)
            || ' bills=' || (SELECT COUNT(*) FROM bills)
            || ' bill_payments=' || (SELECT COUNT(*) FROM bill_payments)
            || ' expenses=' || (SELECT COUNT(*) FROM expenses);
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func jobCostingTableCounts() throws -> String {
        let dbURL = ledgerDatabaseURL()
        let sql = """
        SELECT 'customers=' || (SELECT COUNT(*) FROM customers)
            || ' jobs=' || (SELECT COUNT(*) FROM jobs)
            || ' estimates=' || (SELECT COUNT(*) FROM estimates)
            || ' invoices=' || (SELECT COUNT(*) FROM native_invoices)
            || ' payments=' || (SELECT COUNT(*) FROM payments_received)
            || ' bills=' || (SELECT COUNT(*) FROM bills)
            || ' bill_payments=' || (SELECT COUNT(*) FROM bill_payments)
            || ' expenses=' || (SELECT COUNT(*) FROM expenses);
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reportCorrectnessTableCounts() throws -> String {
        let dbURL = ledgerDatabaseURL()
        let sql = """
        SELECT 'customers=' || (SELECT COUNT(*) FROM customers)
            || ' jobs=' || (SELECT COUNT(*) FROM jobs)
            || ' estimates=' || (SELECT COUNT(*) FROM estimates)
            || ' invoices=' || (SELECT COUNT(*) FROM native_invoices)
            || ' payments=' || (SELECT COUNT(*) FROM payments_received)
            || ' expenses=' || (SELECT COUNT(*) FROM expenses);
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForMoneyInProofSummary(token: String, timeoutSeconds: Int) throws -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let summary = try fetchMoneyInProofSummary(token: token)
            if summary.count == 10 {
                return summary
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for sandbox money-in proof rows")
    }

    private func fetchMoneyInProofSummary(token: String) throws -> [String] {
        let dbURL = ledgerDatabaseURL()
        let invoiceNumber = sqliteQuoted("SANDBOX-INV-\(token)")
        let estimateNumber = sqliteQuoted("SANDBOX-EST-\(token)")
        let customerName = sqliteQuoted("SANDBOX Money-In \(token)")
        let paymentReference = sqliteQuoted("SANDBOX-PAY-\(token)")
        let depositReference = sqliteQuoted("SANDBOX-DEP-\(token)")
        let sql = """
        SELECT 'estimate|' || e.id || '|' || e.customer_id || '|' || COALESCE(e.job_id, 0) || '|' || printf('%.2f', e.total) || '|' || e.status
        FROM estimates e
        WHERE e.estimate_number = \(estimateNumber);

        SELECT 'progress|' || COUNT(DISTINCT eil.invoice_id) || '|' || printf('%.2f', COALESCE(SUM(ni.total), 0)) || '|' || printf('%.2f', e.total - COALESCE(SUM(ni.total), 0))
        FROM estimates e
        LEFT JOIN estimate_invoice_links eil ON eil.estimate_id = e.id
        LEFT JOIN native_invoices ni ON ni.id = eil.invoice_id
        WHERE e.estimate_number = \(estimateNumber)
        GROUP BY e.id, e.total;

        SELECT 'invoice|' || id || '|' || printf('%.2f', total) || '|' || printf('%.2f', paid) || '|' || status || '|' || (
            SELECT COUNT(*) FROM invoice_lines WHERE invoice_id = native_invoices.id
        )
        FROM native_invoices
        WHERE invoice_number = \(invoiceNumber);

        SELECT 'payment|' || id || '|' || invoice_id || '|' || printf('%.2f', amount) || '|' || COALESCE(deposit_account_id, 0)
        FROM payments_received
        WHERE reference = \(paymentReference);

        SELECT 'application|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(applied_amount), 0))
        FROM payment_applications
        WHERE payment_id = (SELECT id FROM payments_received WHERE reference = \(paymentReference))
          AND invoice_id = (SELECT id FROM native_invoices WHERE invoice_number = \(invoiceNumber));

        SELECT 'deposit|' || d.id || '|' || printf('%.2f', d.total_amount) || '|' || printf('%.2f', drl.amount) || '|' || p.deposit_account_id
        FROM deposit_records d
        JOIN deposit_record_lines drl ON drl.deposit_id = d.id
        JOIN payments_received p ON p.id = drl.payment_id
        WHERE d.reference = \(depositReference);

        SELECT 'undeposited|' || COUNT(*)
        FROM payments_received p
        LEFT JOIN deposit_record_lines drl ON drl.payment_id = p.id
        WHERE p.reference = \(paymentReference)
          AND COALESCE(p.deposit_account_id, 0) = 0
          AND drl.id IS NULL;

        WITH statement_rows AS (
            SELECT date,
                   sort_order,
                   reference,
                   SUM(amount) OVER (
                       ORDER BY date, sort_order, reference
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                   ) AS balance
            FROM (
                SELECT issue_date AS date, 0 AS sort_order, estimate_number AS reference, 0.0 AS amount
                FROM estimates
                WHERE estimate_number = \(estimateNumber)
                UNION ALL
                SELECT issue_date AS date, 1 AS sort_order, invoice_number AS reference, total AS amount
                FROM native_invoices
                WHERE invoice_number = \(invoiceNumber)
                UNION ALL
                SELECT payment_date AS date, 3 AS sort_order, reference, -amount AS amount
                FROM payments_received
                WHERE reference = \(paymentReference)
            )
        )
        SELECT 'statement|' || (SELECT COUNT(*) FROM statement_rows) || '|' || printf('%.2f', COALESCE((
            SELECT balance
            FROM statement_rows
            ORDER BY date DESC, sort_order DESC, reference DESC
            LIMIT 1
        ), 0));

        SELECT 'ar|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(ni.total - ni.paid), 0))
        FROM native_invoices ni
        JOIN customers c ON c.id = ni.customer_id
        WHERE c.name = \(customerName)
          AND ni.status NOT IN ('paid', 'void')
          AND (ni.total - ni.paid) > 0.01;

        SELECT 'depositHistory|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(total_amount), 0))
        FROM deposit_records
        WHERE reference = \(depositReference);
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func assertMoneyInProof(summary: [String]) throws {
        let rows = Dictionary(uniqueKeysWithValues: summary.compactMap { row -> (String, [String])? in
            let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { return nil }
            return (key, parts)
        })

        guard let estimate = rows["estimate"], estimate.count == 6,
              estimate[3] != "0",
              estimate[4] == "246.90",
              estimate[5] == "accepted" else {
            throw HarnessError.commandTimedOut("Money-in proof estimate/job was not created correctly: \(summary)")
        }

        guard let progress = rows["progress"], progress.count == 4,
              progress[1] == "1",
              progress[2] == "123.45",
              progress[3] == "123.45" else {
            throw HarnessError.commandTimedOut("Money-in proof estimate progress did not show one 50 percent invoice: \(summary)")
        }

        guard let invoice = rows["invoice"], invoice.count == 6,
              invoice[3] == "123.45",
              invoice[4] == "paid",
              invoice[5] == "1" else {
            throw HarnessError.commandTimedOut("Money-in proof invoice did not become a paid one-line invoice: \(summary)")
        }

        guard let payment = rows["payment"], payment.count == 5,
              payment[3] == "123.45",
              payment[4] != "0" else {
            throw HarnessError.commandTimedOut("Money-in proof payment was not deposited into a bank account: \(summary)")
        }

        guard let application = rows["application"], application.count == 3,
              application[1] == "1",
              application[2] == "123.45" else {
            throw HarnessError.commandTimedOut("Money-in proof payment application did not match the invoice: \(summary)")
        }

        guard let deposit = rows["deposit"], deposit.count == 5,
              deposit[2] == "123.45",
              deposit[3] == "123.45",
              deposit[4] == payment[4] else {
            throw HarnessError.commandTimedOut("Money-in proof deposit did not match the payment: \(summary)")
        }

        guard let undeposited = rows["undeposited"], undeposited.count == 2,
              undeposited[1] == "0" else {
            throw HarnessError.commandTimedOut("Money-in proof payment was still listed as undeposited: \(summary)")
        }

        guard let statement = rows["statement"], statement.count == 3,
              statement[1] == "3",
              statement[2] == "0.00" else {
            throw HarnessError.commandTimedOut("Money-in proof customer statement did not net to zero after payment: \(summary)")
        }

        guard let ar = rows["ar"], ar.count == 3,
              ar[1] == "0",
              ar[2] == "0.00" else {
            throw HarnessError.commandTimedOut("Money-in proof A/R aging still had an open balance: \(summary)")
        }

        guard let depositHistory = rows["depositHistory"], depositHistory.count == 3,
              depositHistory[1] == "1",
              depositHistory[2] == "123.45" else {
            throw HarnessError.commandTimedOut("Money-in proof deposit history did not show the recorded deposit: \(summary)")
        }
    }

    private func waitForMoneyOutProofSummary(token: String, timeoutSeconds: Int) throws -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let summary = try fetchMoneyOutProofSummary(token: token)
            if summary.count == 6 {
                return summary
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for sandbox money-out proof rows")
    }

    private func fetchMoneyOutProofSummary(token: String) throws -> [String] {
        let dbURL = ledgerDatabaseURL()
        let vendorName = sqliteQuoted("SANDBOX Payee \(token)")
        let billMemo = sqliteQuoted("SANDBOX A/P bill proof \(token)")
        let payBillsMemo = sqliteQuoted("SANDBOX pay bills proof \(token)")
        let immediateMemo = sqliteQuoted("SANDBOX immediate check proof \(token)")
        let checkSuffix = String(token.suffix(4))
        let billCheckNumber = sqliteQuoted("91\(checkSuffix)")
        let immediateCheckNumber = sqliteQuoted("92\(checkSuffix)")
        let year = Calendar.current.component(.year, from: Date())
        let sql = """
        SELECT 'vendor|' || id || '|' || name
        FROM vendors
        WHERE name = \(vendorName);

        SELECT 'bill|' || b.id || '|' || printf('%.2f', b.amount) || '|' || b.status || '|' || b.check_number
        FROM bills b
        JOIN vendors v ON v.id = b.vendor_id
        WHERE v.name = \(vendorName)
          AND b.memo = \(billMemo);

        SELECT 'billPayment|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(bp.amount), 0)) || '|' || COALESCE(MAX(bp.check_number), '')
        FROM bill_payments bp
        JOIN bills b ON b.id = bp.bill_id
        JOIN vendors v ON v.id = b.vendor_id
        WHERE v.name = \(vendorName)
          AND bp.memo = \(payBillsMemo);

        SELECT 'billRegister|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(amount), 0)) || '|' || COALESCE(MAX(check_number), '')
        FROM expenses
        WHERE memo = \(payBillsMemo)
          AND check_number = \(billCheckNumber);

        SELECT 'immediateExpense|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(amount), 0)) || '|' || COALESCE(MAX(check_number), '')
        FROM expenses
        WHERE memo = \(immediateMemo)
          AND check_number = \(immediateCheckNumber);

        SELECT 'payeeSpend|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(e.amount), 0))
        FROM expenses e
        JOIN vendors v ON v.id = e.vendor_id
        WHERE v.name = \(vendorName)
          AND substr(e.expense_date, 1, 4) = '\(year)';
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func assertMoneyOutProof(summary: [String]) throws {
        let rows = Dictionary(uniqueKeysWithValues: summary.compactMap { row -> (String, [String])? in
            let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { return nil }
            return (key, parts)
        })

        guard let vendor = rows["vendor"], vendor.count == 3,
              vendor[2].hasPrefix("SANDBOX Payee ") else {
            throw HarnessError.commandTimedOut("Money-out proof vendor was not created correctly: \(summary)")
        }

        guard let bill = rows["bill"], bill.count == 5,
              bill[2] == "210.25",
              bill[3] == "paid",
              !bill[4].isEmpty else {
            throw HarnessError.commandTimedOut("Money-out proof bill was not marked paid with a check number: \(summary)")
        }

        guard let billPayment = rows["billPayment"], billPayment.count == 4,
              billPayment[1] == "1",
              billPayment[2] == "210.25",
              billPayment[3] == bill[4] else {
            throw HarnessError.commandTimedOut("Money-out proof bill payment did not match the paid bill: \(summary)")
        }

        guard let billRegister = rows["billRegister"], billRegister.count == 4,
              billRegister[1] == "1",
              billRegister[2] == "210.25",
              billRegister[3] == bill[4] else {
            throw HarnessError.commandTimedOut("Money-out proof bill payment did not create a matching register expense: \(summary)")
        }

        guard let immediateExpense = rows["immediateExpense"], immediateExpense.count == 4,
              immediateExpense[1] == "1",
              immediateExpense[2] == "44.75",
              !immediateExpense[3].isEmpty,
              immediateExpense[3] != bill[4] else {
            throw HarnessError.commandTimedOut("Money-out proof immediate check was not a distinct expense/check: \(summary)")
        }

        guard let payeeSpend = rows["payeeSpend"], payeeSpend.count == 3,
              payeeSpend[1] == "2",
              payeeSpend[2] == "255.00" else {
            throw HarnessError.commandTimedOut("Money-out proof payee spend did not include bill payment plus immediate check: \(summary)")
        }
    }

    private func waitForJobCostingProofSummary(token: String, timeoutSeconds: Int) throws -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let summary = try fetchJobCostingProofSummary(token: token)
            if summary.count == 7 {
                return summary
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for sandbox job costing proof rows")
    }

    private func fetchJobCostingProofSummary(token: String) throws -> [String] {
        let dbURL = ledgerDatabaseURL()
        let customerName = sqliteQuoted("SANDBOX Job Customer \(token)")
        let jobName = sqliteQuoted("SANDBOX Costing Job \(token)")
        let paidBillMemo = sqliteQuoted("SANDBOX paid job bill \(token)")
        let paidBillPaymentMemo = sqliteQuoted("SANDBOX paid job bill payment \(token)")
        let unpaidBillMemo = sqliteQuoted("SANDBOX unpaid job bill \(token)")
        let immediateExpenseMemo = sqliteQuoted("SANDBOX immediate job expense \(token)")
        let sql = """
        SELECT 'job|' || j.id || '|' || j.customer_id || '|' || j.name || '|' || j.status || '|' || COALESCE(j.is_active, 1)
        FROM jobs j
        JOIN customers c ON c.id = j.customer_id
        WHERE c.name = \(customerName)
          AND j.name = \(jobName);

        SELECT 'revenue|' || COUNT(e.id) || '|' || printf('%.2f', COALESCE(SUM(e.total), 0))
        FROM estimates e
        JOIN jobs j ON j.id = e.job_id
        JOIN customers c ON c.id = j.customer_id
        WHERE c.name = \(customerName)
          AND j.name = \(jobName);

        SELECT 'invoice|' || COUNT(ni.id) || '|' || printf('%.2f', COALESCE(SUM(ni.total), 0)) || '|' || printf('%.2f', COALESCE(SUM(ni.total - ni.paid), 0))
        FROM native_invoices ni
        JOIN jobs j ON j.id = ni.job_id
        JOIN customers c ON c.id = j.customer_id
        WHERE c.name = \(customerName)
          AND j.name = \(jobName);

        SELECT 'paidBill|' || COUNT(b.id) || '|' || printf('%.2f', COALESCE(SUM(b.amount), 0)) || '|' || COALESCE(MAX(b.status), '')
        FROM bills b
        JOIN jobs j ON j.id = b.job_id
        JOIN customers c ON c.id = j.customer_id
        WHERE c.name = \(customerName)
          AND j.name = \(jobName)
          AND b.memo = \(paidBillMemo);

        SELECT 'billPaymentExpense|' || COUNT(e.id) || '|' || printf('%.2f', COALESCE(SUM(e.amount), 0))
        FROM expenses e
        JOIN jobs j ON j.id = e.job_id
        JOIN customers c ON c.id = j.customer_id
        WHERE c.name = \(customerName)
          AND j.name = \(jobName)
          AND e.memo = \(paidBillPaymentMemo);

        SELECT 'unpaidAndImmediate|' || (
            SELECT COUNT(*)
            FROM bills b
            JOIN jobs j ON j.id = b.job_id
            JOIN customers c ON c.id = j.customer_id
            WHERE c.name = \(customerName)
              AND j.name = \(jobName)
              AND b.memo = \(unpaidBillMemo)
              AND b.status = 'unpaid'
        ) || '|' || printf('%.2f', COALESCE((
            SELECT SUM(b.amount)
            FROM bills b
            JOIN jobs j ON j.id = b.job_id
            JOIN customers c ON c.id = j.customer_id
            WHERE c.name = \(customerName)
              AND j.name = \(jobName)
              AND b.memo = \(unpaidBillMemo)
              AND b.status = 'unpaid'
        ), 0)) || '|' || (
            SELECT COUNT(*)
            FROM expenses e
            JOIN jobs j ON j.id = e.job_id
            JOIN customers c ON c.id = j.customer_id
            WHERE c.name = \(customerName)
              AND j.name = \(jobName)
              AND e.memo = \(immediateExpenseMemo)
        ) || '|' || printf('%.2f', COALESCE((
            SELECT SUM(e.amount)
            FROM expenses e
            JOIN jobs j ON j.id = e.job_id
            JOIN customers c ON c.id = j.customer_id
            WHERE c.name = \(customerName)
              AND j.name = \(jobName)
              AND e.memo = \(immediateExpenseMemo)
        ), 0));

        SELECT 'profitability|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(estimate_total), 0)) || '|' || printf('%.2f', COALESCE(SUM(invoice_total), 0)) || '|' || printf('%.2f', COALESCE(SUM(open_balance), 0)) || '|' || printf('%.2f', COALESCE(SUM(expense_total), 0)) || '|' || printf('%.2f', COALESCE(SUM(invoice_total - expense_total), 0))
        FROM (
            WITH estimate_totals AS (
                SELECT job_id, COALESCE(SUM(total), 0) AS estimate_total
                FROM estimates
                GROUP BY job_id
            ),
            invoice_totals AS (
                SELECT job_id,
                       COALESCE(SUM(total), 0) AS invoice_total,
                       COALESCE(SUM(CASE WHEN status != 'void' THEN MAX(total - paid, 0) ELSE 0 END), 0) AS open_balance
                FROM native_invoices
                GROUP BY job_id
            ),
            expense_totals AS (
                SELECT job_id, COALESCE(SUM(amount), 0) AS expense_total
                FROM (
                    SELECT job_id, amount FROM expenses
                    UNION ALL
                    SELECT job_id, amount FROM bills WHERE status = 'unpaid'
                )
                GROUP BY job_id
            )
            SELECT j.id,
                   COALESCE(et.estimate_total, 0) AS estimate_total,
                   COALESCE(it.invoice_total, 0) AS invoice_total,
                   COALESCE(it.open_balance, 0) AS open_balance,
                   COALESCE(ext.expense_total, 0) AS expense_total
            FROM jobs j
            JOIN customers c ON c.id = j.customer_id
            LEFT JOIN estimate_totals et ON et.job_id = j.id
            LEFT JOIN invoice_totals it ON it.job_id = j.id
            LEFT JOIN expense_totals ext ON ext.job_id = j.id
            WHERE c.name = \(customerName)
              AND j.name = \(jobName)
        );
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func assertJobCostingProof(summary: [String]) throws {
        let rows = Dictionary(uniqueKeysWithValues: summary.compactMap { row -> (String, [String])? in
            let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { return nil }
            return (key, parts)
        })

        guard let job = rows["job"], job.count == 6,
              job[3].hasPrefix("SANDBOX Costing Job "),
              job[4] == "active",
              job[5] == "1" else {
            throw HarnessError.commandTimedOut("Job costing proof job was not active and reachable: \(summary)")
        }

        guard let revenue = rows["revenue"], revenue.count == 3,
              revenue[1] == "1",
              revenue[2] == "500.00" else {
            throw HarnessError.commandTimedOut("Job costing proof estimate revenue did not match: \(summary)")
        }

        guard let invoice = rows["invoice"], invoice.count == 4,
              invoice[1] == "1",
              invoice[2] == "300.00",
              invoice[3] == "200.00" else {
            throw HarnessError.commandTimedOut("Job costing proof invoice/open balance did not match: \(summary)")
        }

        guard let paidBill = rows["paidBill"], paidBill.count == 4,
              paidBill[1] == "1",
              paidBill[2] == "120.00",
              paidBill[3] == "paid" else {
            throw HarnessError.commandTimedOut("Job costing proof paid bill did not close through Pay Bills: \(summary)")
        }

        guard let billPaymentExpense = rows["billPaymentExpense"], billPaymentExpense.count == 3,
              billPaymentExpense[1] == "1",
              billPaymentExpense[2] == "120.00" else {
            throw HarnessError.commandTimedOut("Job costing proof paid bill did not become a job cost expense: \(summary)")
        }

        guard let unpaidAndImmediate = rows["unpaidAndImmediate"], unpaidAndImmediate.count == 5,
              unpaidAndImmediate[1] == "1",
              unpaidAndImmediate[2] == "80.00",
              unpaidAndImmediate[3] == "1",
              unpaidAndImmediate[4] == "50.00" else {
            throw HarnessError.commandTimedOut("Job costing proof unpaid bill or immediate expense did not attach to job: \(summary)")
        }

        guard let profitability = rows["profitability"], profitability.count == 7,
              profitability[1] == "1",
              profitability[2] == "500.00",
              profitability[3] == "300.00",
              profitability[4] == "200.00",
              profitability[5] == "250.00",
              profitability[6] == "50.00" else {
            throw HarnessError.commandTimedOut("Job profitability totals did not match controlled job: \(summary)")
        }
    }

    private func waitForReportCorrectnessProofSummary(token: String, timeoutSeconds: Int) throws -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let summary = try fetchReportCorrectnessProofSummary(token: token)
            if summary.count == 7 {
                return summary
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for sandbox report correctness proof rows")
    }

    private func fetchReportCorrectnessProofSummary(token: String) throws -> [String] {
        let dbURL = ledgerDatabaseURL()
        let customerName = sqliteQuoted("SANDBOX Report Customer \(token)")
        let vendorName = sqliteQuoted("SANDBOX Report Vendor \(token)")
        let jobName = sqliteQuoted("SANDBOX Report Job \(token)")
        let reportDate = sqliteQuoted("2099-01-15")
        let sql = """
        SELECT 'sources|' || (
            SELECT COUNT(DISTINCT report_year) FROM historical_pl_lines
        ) || '|historicalQB|liveOperational|hybridReview';

        SELECT 'operationalPL|' || printf('%.2f', COALESCE((
            SELECT SUM(p.amount)
            FROM payments_received p
            JOIN customers c ON c.id = p.customer_id
            WHERE c.name = \(customerName)
              AND p.payment_date = \(reportDate)
        ), 0)) || '|' || printf('%.2f', COALESCE((
            SELECT SUM(e.amount)
            FROM expenses e
            JOIN vendors v ON v.id = e.vendor_id
            WHERE v.name = \(vendorName)
              AND e.expense_date = \(reportDate)
        ), 0));

        SELECT 'ar|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(ni.total - ni.paid), 0))
        FROM native_invoices ni
        JOIN customers c ON c.id = ni.customer_id
        WHERE c.name = \(customerName)
          AND ni.status NOT IN ('paid', 'void')
          AND (ni.total - ni.paid) > 0.01;

        SELECT 'statement|' || COUNT(*) || '|' || printf('%.2f', COALESCE((
            SELECT SUM(amount)
            FROM (
                SELECT total AS amount
                FROM native_invoices ni
                JOIN customers c ON c.id = ni.customer_id
                WHERE c.name = \(customerName)
                UNION ALL
                SELECT -p.amount AS amount
                FROM payments_received p
                JOIN customers c ON c.id = p.customer_id
                WHERE c.name = \(customerName)
            )
        ), 0))
        FROM (
            SELECT 1
            FROM native_invoices ni
            JOIN customers c ON c.id = ni.customer_id
            WHERE c.name = \(customerName)
            UNION ALL
            SELECT 1
            FROM payments_received p
            JOIN customers c ON c.id = p.customer_id
            WHERE c.name = \(customerName)
        );

        SELECT 'jobProfit|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(estimate_total), 0)) || '|' || printf('%.2f', COALESCE(SUM(invoice_total), 0)) || '|' || printf('%.2f', COALESCE(SUM(open_balance), 0)) || '|' || printf('%.2f', COALESCE(SUM(expense_total), 0)) || '|' || printf('%.2f', COALESCE(SUM(invoice_total - expense_total), 0))
        FROM (
            WITH estimate_totals AS (
                SELECT job_id, COALESCE(SUM(total), 0) AS estimate_total
                FROM estimates
                GROUP BY job_id
            ),
            invoice_totals AS (
                SELECT job_id,
                       COALESCE(SUM(total), 0) AS invoice_total,
                       COALESCE(SUM(CASE WHEN status != 'void' THEN MAX(total - paid, 0) ELSE 0 END), 0) AS open_balance
                FROM native_invoices
                GROUP BY job_id
            ),
            expense_totals AS (
                SELECT job_id, COALESCE(SUM(amount), 0) AS expense_total
                FROM expenses
                GROUP BY job_id
            )
            SELECT j.id,
                   COALESCE(et.estimate_total, 0) AS estimate_total,
                   COALESCE(it.invoice_total, 0) AS invoice_total,
                   COALESCE(it.open_balance, 0) AS open_balance,
                   COALESCE(ext.expense_total, 0) AS expense_total
            FROM jobs j
            JOIN customers c ON c.id = j.customer_id
            LEFT JOIN estimate_totals et ON et.job_id = j.id
            LEFT JOIN invoice_totals it ON it.job_id = j.id
            LEFT JOIN expense_totals ext ON ext.job_id = j.id
            WHERE c.name = \(customerName)
              AND j.name = \(jobName)
        );

        SELECT 'payeeSpend|' || COUNT(*) || '|' || printf('%.2f', COALESCE(SUM(e.amount), 0))
        FROM expenses e
        JOIN vendors v ON v.id = e.vendor_id
        WHERE v.name = \(vendorName)
          AND e.expense_date = \(reportDate);

        SELECT 'historicalAvailability|' || (
            SELECT COUNT(*) FROM historical_pl_lines
        ) || '|' || (
            SELECT COUNT(*) FROM historical_trial_balance_lines
        ) || '|' || (
            SELECT COUNT(*) FROM historical_sales_by_item_lines
        );
        """
        return try runProcess("/usr/bin/sqlite3", arguments: [dbURL.path, sql])
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func assertReportCorrectnessProof(summary: [String]) throws {
        let rows = Dictionary(uniqueKeysWithValues: summary.compactMap { row -> (String, [String])? in
            let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { return nil }
            return (key, parts)
        })

        guard let sources = rows["sources"], sources.count == 5,
              (Int(sources[1]) ?? 0) > 0,
              sources[2] == "historicalQB",
              sources[3] == "liveOperational",
              sources[4] == "hybridReview" else {
            throw HarnessError.commandTimedOut("Report source classification proof failed: \(summary)")
        }

        guard let operationalPL = rows["operationalPL"], operationalPL.count == 3,
              operationalPL[1] == "150.00",
              operationalPL[2] == "40.00" else {
            throw HarnessError.commandTimedOut("Operational report movement did not match controlled payment/expense: \(summary)")
        }

        guard let ar = rows["ar"], ar.count == 3,
              ar[1] == "1",
              ar[2] == "75.00" else {
            throw HarnessError.commandTimedOut("A/R report did not show the controlled open invoice balance: \(summary)")
        }

        guard let statement = rows["statement"], statement.count == 3,
              statement[1] == "2",
              statement[2] == "75.00" else {
            throw HarnessError.commandTimedOut("Customer statement did not end at the controlled open balance: \(summary)")
        }

        guard let jobProfit = rows["jobProfit"], jobProfit.count == 7,
              jobProfit[1] == "1",
              jobProfit[2] == "300.00",
              jobProfit[3] == "225.00",
              jobProfit[4] == "75.00",
              jobProfit[5] == "40.00",
              jobProfit[6] == "185.00" else {
            throw HarnessError.commandTimedOut("Job Profitability report did not match controlled report scenario: \(summary)")
        }

        guard let payeeSpend = rows["payeeSpend"], payeeSpend.count == 3,
              payeeSpend[1] == "1",
              payeeSpend[2] == "40.00" else {
            throw HarnessError.commandTimedOut("Payee Spend report did not match controlled expense: \(summary)")
        }

        guard let historicalAvailability = rows["historicalAvailability"], historicalAvailability.count == 4,
              (Int(historicalAvailability[1]) ?? 0) > 0,
              (Int(historicalAvailability[2]) ?? 0) > 0,
              (Int(historicalAvailability[3]) ?? 0) > 0 else {
            throw HarnessError.commandTimedOut("Historical report source tables were not available: \(summary)")
        }
    }

    private func sqliteQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func waitForEstimateCount(
        above initialCount: Int,
        command: HarnessCommand,
        timeoutSeconds: Int
    ) throws -> Int {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let count = (try? estimateCount(for: command)) ?? 0
            if count > initialCount {
                return count
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for order sheet approval to create an estimate")
    }

    private func waitForOrderSheetStagingCount(
        above initialCount: Int,
        command: HarnessCommand,
        timeoutSeconds: Int
    ) throws -> Int {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let count = (try? orderSheetStagingCount(for: command)) ?? 0
            if count > initialCount {
                return count
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for order sheet inbox import to stage a new row")
    }

    private func assertOrderSheetStagingIsSandboxed(command: HarnessCommand) throws {
        guard let supportDirectory = sandboxSupportDirectory(for: command) else {
            return
        }
        let dbURL = orderSheetStagingDatabaseURL(for: command)
        let output = try runProcess(
            "/usr/bin/sqlite3",
            arguments: [
                dbURL.path,
                "SELECT stored_path FROM order_sheets ORDER BY id DESC LIMIT 5;"
            ]
        )
        let paths = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            throw HarnessError.missingRecord("No order sheet staged paths were found")
        }
        let sandboxPath = supportDirectory.path
        guard paths.allSatisfy({ $0.hasPrefix(sandboxPath) }) else {
            throw HarnessError.unsupportedWriteScenario("Order sheet staging path escaped sandbox: \(paths.joined(separator: ", "))")
        }
    }

    private func backupLiveDatabase(for command: HarnessCommand) throws -> URL {
        let dbURL = ledgerDatabaseURL(for: command)
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        let backupDirectory = directories.runs.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: nil)

        let backupURL = backupDirectory.appendingPathComponent("ledger.\(stamp).sqlite")
        try FileManager.default.copyItem(at: dbURL, to: backupURL)

        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                let destination = URL(fileURLWithPath: backupURL.path + suffix)
                try? FileManager.default.copyItem(at: sidecar, to: destination)
            }
        }

        return backupURL
    }

    private func terminateApplications(named name: String) throws {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.localizedName == name }
        for app in apps {
            if !app.isTerminated {
                _ = app.terminate()
                let deadline = Date().addingTimeInterval(5)
                while !app.isTerminated && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
                if !app.isTerminated {
                    _ = app.forceTerminate()
                }
            }
        }
    }

    private func cleanupEmailDraftSurfaces(run: HarnessRun) {
        if isApplicationRunning(named: "Mail") {
            let script = """
            tell application "Mail"
                try
                    repeat with draftMessage in outgoing messages
                        close draftMessage saving no
                    end repeat
                end try
            end tell
            """
            do {
                _ = try runProcess("/usr/bin/osascript", arguments: ["-e", script])
                run.addStep("cleanup_mail_drafts", status: "ok", detail: "Closed Mail compose drafts without saving")
            } catch {
                run.addStep("cleanup_mail_drafts", status: "warning", detail: error.localizedDescription)
            }
        }

        if isApplicationRunning(named: "Microsoft Outlook") {
            let script = """
            tell application "Microsoft Outlook"
                try
                    repeat with draftWindow in windows
                        close draftWindow saving no
                    end repeat
                end try
            end tell
            """
            do {
                _ = try runProcess("/usr/bin/osascript", arguments: ["-e", script])
                run.addStep("cleanup_outlook_drafts", status: "ok", detail: "Closed Outlook compose windows without saving")
            } catch {
                run.addStep("cleanup_outlook_drafts", status: "warning", detail: error.localizedDescription)
            }
        }

        try? terminateApplications(named: "Mail")
        try? terminateApplications(named: "Microsoft Outlook")
    }

    private func isApplicationRunning(named name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == name && !$0.isTerminated }
    }

    private func waitForRunningApplication(named name: String, timeoutSeconds: Int) throws -> NSRunningApplication {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name && !$0.isTerminated }) {
                return app
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for \(name) to launch")
    }

    private func waitForRunningApplication(namedAnyOf names: [String], timeoutSeconds: Int) throws -> NSRunningApplication {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                names.contains($0.localizedName ?? "") && !$0.isTerminated
            }) {
                return app
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        throw HarnessError.commandTimedOut("Timed out waiting for one of \(names.joined(separator: ", ")) to launch")
    }

    private func normalizedTargetPath(for command: HarnessCommand) -> String {
        command.targetAppPath.isEmpty ? "/Applications/Renaissance Filed.app" : command.targetAppPath
    }

    private func argumentList(from map: [String: String]) -> [String] {
        var arguments: [String] = []
        if let tab = map["tab"], !tab.isEmpty {
            arguments += ["--harness-tab", tab]
        }
        if let reportTab = map["reportTab"], !reportTab.isEmpty {
            arguments += ["--harness-report-tab", reportTab]
        }
        if let reportYear = map["reportYear"], !reportYear.isEmpty {
            arguments += ["--harness-report-year", reportYear]
        }
        if let reportPeriod = map["reportPeriod"], !reportPeriod.isEmpty {
            arguments += ["--harness-report-period", reportPeriod]
        }
        if let customerID = map["customerID"], !customerID.isEmpty {
            arguments += ["--harness-open-customer", customerID]
        }
        if let estimateID = map["estimateID"], !estimateID.isEmpty {
            arguments += ["--harness-open-estimate", estimateID]
        }
        if let invoiceID = map["invoiceID"], !invoiceID.isEmpty {
            arguments += ["--harness-open-invoice", invoiceID]
        }
        if let editEstimateID = map["editEstimateID"], !editEstimateID.isEmpty {
            arguments += ["--harness-edit-estimate", editEstimateID]
        }
        if let editInvoiceID = map["editInvoiceID"], !editInvoiceID.isEmpty {
            arguments += ["--harness-edit-invoice", editInvoiceID]
        }
        if map["openWriteCheck"] == "true" {
            arguments += ["--harness-open-write-check"]
        }
        if map["openCheckDesk"] == "true" {
            arguments += ["--harness-open-check-desk"]
        }
        if map["reviewFirstOrderSheet"] == "true" {
            arguments += ["--harness-review-first-order-sheet"]
        }
        if let previewEstimateItemQuery = map["previewEstimateItemQuery"], !previewEstimateItemQuery.isEmpty {
            arguments += ["--harness-preview-estimate-item-query", previewEstimateItemQuery]
        }
        if let previewInvoiceItemQuery = map["previewInvoiceItemQuery"], !previewInvoiceItemQuery.isEmpty {
            arguments += ["--harness-preview-invoice-item-query", previewInvoiceItemQuery]
        }
        if let previewWriteCheckPayeeQuery = map["previewWriteCheckPayeeQuery"], !previewWriteCheckPayeeQuery.isEmpty {
            arguments += ["--harness-preview-write-check-payee-query", previewWriteCheckPayeeQuery]
        }
        if map["emailEstimateOnOpen"] == "true" {
            arguments += ["--harness-email-estimate-on-open"]
        }
        if map["emailInvoiceOnOpen"] == "true" {
            arguments += ["--harness-email-invoice-on-open"]
        }
        if let moneyInProofToken = map["moneyInProofToken"], !moneyInProofToken.isEmpty {
            arguments += ["--harness-prove-money-in-spine", moneyInProofToken]
        }
        if let moneyOutProofToken = map["moneyOutProofToken"], !moneyOutProofToken.isEmpty {
            arguments += ["--harness-prove-money-out-spine", moneyOutProofToken]
        }
        if let jobCostingProofToken = map["jobCostingProofToken"], !jobCostingProofToken.isEmpty {
            arguments += ["--harness-prove-job-costing", jobCostingProofToken]
        }
        if let reportCorrectnessProofToken = map["reportCorrectnessProofToken"], !reportCorrectnessProofToken.isEmpty {
            arguments += ["--harness-prove-report-correctness", reportCorrectnessProofToken]
        }
        if let snapshotPath = map["snapshotPath"], !snapshotPath.isEmpty {
            arguments += ["--harness-snapshot-path", snapshotPath]
        }
        if let snapshotDelaySeconds = map["snapshotDelaySeconds"], !snapshotDelaySeconds.isEmpty {
            arguments += ["--harness-snapshot-delay", snapshotDelaySeconds]
        }
        return arguments
    }

    private func persistLedgerLaunchState(from arguments: [String]) throws {
        let stateURL = directories.state.appendingPathComponent("ledger-launch.json")
        try? FileManager.default.removeItem(at: stateURL)

        var selectedTab: String?
        var reportTab: String?
        var reportYear: Int?
        var reportPeriod: String?
        var customerID: Int64?
        var estimateID: Int64?
        var invoiceID: Int64?
        var editEstimateID: Int64?
        var editInvoiceID: Int64?
        var openExpenseID: Int64?
        var updateEstimateMemoID: Int64?
        var updateEstimateMemoValue: String?
        var updateInvoiceMemoID: Int64?
        var updateInvoiceMemoValue: String?
        var emailDocumentID: Int64?
        var approveFirstOrderSheet = false
        var openWriteCheck = false
        var openCheckDesk = false
        var reviewFirstOrderSheet = false
        var previewEstimateItemQuery: String?
        var previewInvoiceItemQuery: String?
        var previewWriteCheckPayeeQuery: String?
        var emailEstimateOnOpen = false
        var emailInvoiceOnOpen = false
        var moneyInProofToken: String?
        var moneyOutProofToken: String?
        var jobCostingProofToken: String?
        var reportCorrectnessProofToken: String?
        var navigationShellProof = false
        var windowRecoveryProof = false
        var windowRecoverySummaryPath: String?
        var snapshotPath: String?
        var snapshotDelaySeconds: Double?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--harness-tab":
                if index + 1 < arguments.count {
                    selectedTab = arguments[index + 1]
                    index += 1
                }
            case "--harness-report-tab":
                if index + 1 < arguments.count {
                    reportTab = arguments[index + 1]
                    index += 1
                }
            case "--harness-report-year":
                if index + 1 < arguments.count {
                    reportYear = Int(arguments[index + 1])
                    index += 1
                }
            case "--harness-report-period":
                if index + 1 < arguments.count {
                    reportPeriod = arguments[index + 1]
                    index += 1
                }
            case "--harness-open-customer":
                if index + 1 < arguments.count {
                    customerID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-open-estimate":
                if index + 1 < arguments.count {
                    estimateID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-open-invoice":
                if index + 1 < arguments.count {
                    invoiceID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-edit-estimate":
                if index + 1 < arguments.count {
                    editEstimateID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-edit-invoice":
                if index + 1 < arguments.count {
                    editInvoiceID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-open-expense":
                if index + 1 < arguments.count {
                    openExpenseID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-update-estimate-memo":
                if index + 2 < arguments.count {
                    updateEstimateMemoID = Int64(arguments[index + 1])
                    updateEstimateMemoValue = arguments[index + 2]
                    index += 2
                }
            case "--harness-update-invoice-memo":
                if index + 2 < arguments.count {
                    updateInvoiceMemoID = Int64(arguments[index + 1])
                    updateInvoiceMemoValue = arguments[index + 2]
                    index += 2
                }
            case "--harness-email-document":
                if index + 1 < arguments.count {
                    emailDocumentID = Int64(arguments[index + 1])
                    index += 1
                }
            case "--harness-approve-first-order-sheet":
                approveFirstOrderSheet = true
            case "--harness-open-write-check":
                openWriteCheck = true
            case "--harness-open-check-desk":
                openCheckDesk = true
            case "--harness-review-first-order-sheet":
                reviewFirstOrderSheet = true
            case "--harness-preview-estimate-item-query":
                if index + 1 < arguments.count {
                    previewEstimateItemQuery = arguments[index + 1]
                    index += 1
                }
            case "--harness-preview-invoice-item-query":
                if index + 1 < arguments.count {
                    previewInvoiceItemQuery = arguments[index + 1]
                    index += 1
                }
            case "--harness-preview-write-check-payee-query":
                if index + 1 < arguments.count {
                    previewWriteCheckPayeeQuery = arguments[index + 1]
                    index += 1
                }
            case "--harness-email-estimate-on-open":
                emailEstimateOnOpen = true
            case "--harness-email-invoice-on-open":
                emailInvoiceOnOpen = true
            case "--harness-prove-money-in-spine":
                if index + 1 < arguments.count {
                    moneyInProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-money-out-spine":
                if index + 1 < arguments.count {
                    moneyOutProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-job-costing":
                if index + 1 < arguments.count {
                    jobCostingProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-report-correctness":
                if index + 1 < arguments.count {
                    reportCorrectnessProofToken = arguments[index + 1]
                    index += 1
                }
            case "--harness-prove-navigation-shell":
                navigationShellProof = true
            case "--harness-prove-window-recovery":
                windowRecoveryProof = true
            case "--harness-window-recovery-summary-path":
                if index + 1 < arguments.count {
                    windowRecoverySummaryPath = arguments[index + 1]
                    index += 1
                }
            case "--harness-snapshot-path":
                if index + 1 < arguments.count {
                    snapshotPath = arguments[index + 1]
                    index += 1
                }
            case "--harness-snapshot-delay":
                if index + 1 < arguments.count {
                    snapshotDelaySeconds = Double(arguments[index + 1])
                    index += 1
                }
            default:
                break
            }
            index += 1
        }

        guard selectedTab != nil
            || reportTab != nil
            || reportYear != nil
            || reportPeriod != nil
            || customerID != nil
            || estimateID != nil
            || invoiceID != nil
            || editEstimateID != nil
            || editInvoiceID != nil
            || openExpenseID != nil
            || updateEstimateMemoID != nil
            || updateInvoiceMemoID != nil
            || emailDocumentID != nil
            || approveFirstOrderSheet
            || openWriteCheck
            || openCheckDesk
            || reviewFirstOrderSheet
            || previewEstimateItemQuery != nil
            || previewInvoiceItemQuery != nil
            || previewWriteCheckPayeeQuery != nil
            || emailEstimateOnOpen
            || emailInvoiceOnOpen
            || moneyInProofToken != nil
            || moneyOutProofToken != nil
            || jobCostingProofToken != nil
            || reportCorrectnessProofToken != nil
            || navigationShellProof
            || windowRecoveryProof
            || snapshotPath != nil
        else {
            return
        }

        let payload: [String: Any?] = [
            "selectedTab": selectedTab,
            "reportTab": reportTab,
            "reportYear": reportYear,
            "reportPeriod": reportPeriod,
            "customerID": customerID,
            "estimateID": estimateID,
            "invoiceID": invoiceID,
            "editEstimateID": editEstimateID,
            "editInvoiceID": editInvoiceID,
            "openExpenseID": openExpenseID,
            "updateEstimateMemoID": updateEstimateMemoID,
            "updateEstimateMemoValue": updateEstimateMemoValue,
            "updateInvoiceMemoID": updateInvoiceMemoID,
            "updateInvoiceMemoValue": updateInvoiceMemoValue,
            "emailDocumentID": emailDocumentID,
            "approveFirstOrderSheet": approveFirstOrderSheet ? true : nil,
            "openWriteCheck": openWriteCheck ? true : nil,
            "openCheckDesk": openCheckDesk ? true : nil,
            "reviewFirstOrderSheet": reviewFirstOrderSheet ? true : nil,
            "previewEstimateItemQuery": previewEstimateItemQuery,
            "previewInvoiceItemQuery": previewInvoiceItemQuery,
            "previewWriteCheckPayeeQuery": previewWriteCheckPayeeQuery,
            "emailEstimateOnOpen": emailEstimateOnOpen ? true : nil,
            "emailInvoiceOnOpen": emailInvoiceOnOpen ? true : nil,
            "moneyInProofToken": moneyInProofToken,
            "moneyOutProofToken": moneyOutProofToken,
            "jobCostingProofToken": jobCostingProofToken,
            "reportCorrectnessProofToken": reportCorrectnessProofToken,
            "navigationShellProof": navigationShellProof ? true : nil,
            "windowRecoveryProof": windowRecoveryProof ? true : nil,
            "windowRecoverySummaryPath": windowRecoverySummaryPath,
            "snapshotPath": snapshotPath,
            "snapshotDelaySeconds": snapshotDelaySeconds
        ]

        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func passthroughLaunchArguments(from arguments: [String]) -> [String] {
        var filtered: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--harness-tab", "--harness-report-tab", "--harness-report-year", "--harness-report-period", "--harness-open-customer", "--harness-open-estimate", "--harness-open-invoice", "--harness-edit-estimate", "--harness-edit-invoice", "--harness-open-expense", "--harness-email-document", "--harness-prove-money-in-spine", "--harness-prove-money-out-spine", "--harness-prove-job-costing", "--harness-prove-report-correctness", "--harness-window-recovery-summary-path", "--harness-snapshot-path", "--harness-snapshot-delay":
                index += 1
            case "--harness-update-estimate-memo", "--harness-update-invoice-memo":
                index += 2
            case "--harness-open-write-check", "--harness-review-first-order-sheet", "--harness-approve-first-order-sheet", "--harness-prove-navigation-shell", "--harness-prove-window-recovery":
                break
            default:
                filtered.append(argument)
            }
            index += 1
        }
        return filtered
    }

    private func ledgerDatabaseURL(for command: HarnessCommand? = nil) -> URL {
        let command = command ?? activeCommand
        if let command, let supportDirectory = sandboxSupportDirectory(for: command) {
            return supportDirectory.appendingPathComponent("ledger.sqlite")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("RenaissanceLedger/ledger.sqlite")
    }

    private func sandboxSupportDirectory(for command: HarnessCommand) -> URL? {
        guard let value = command.arguments["sandboxSupportDir"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func sandboxSupportDirectoryFromLaunchArguments(_ arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--harness-sandbox-support-dir"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func runProcess(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw HarnessError.commandTimedOut(errorOutput.isEmpty ? "Process \(executable) failed" : errorOutput)
        }
        return output
    }

    private func writeResult(_ result: HarnessResult, to runDirectory: URL) {
        let resultURL = runDirectory.appendingPathComponent("result.json")
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: resultURL, options: .atomic)
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
