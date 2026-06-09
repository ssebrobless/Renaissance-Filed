import AppKit
import SwiftUI

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var centerMode: StartupCenterMode = .customers
    @Published var isCenterTrayExpanded = true
    @Published var selectedCustomerID: Int64?
    @Published var registerMode: StartupRegisterMode = .checkRegister
    @Published var selectedBankAccountID: Int64 = 0
    @Published var activeReportTab: ReportTab = .historicalPL
    @Published var requestedHistoricalYear: Int?
    @Published var isReportViewerExpanded = true
    @Published var customerSearch = "" {
        didSet {
            if !customerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isCenterTrayExpanded = true
            }
        }
    }
    @Published var customerSortMode: EntityListSortMode = .alphabeticalAsc
    @Published var customerInitialFilter = "All"
    @Published var customerDateFilterMode: EntityDateFilterMode = .allTime
    @Published var customerFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var customerToDate = Date()
    @Published var registerSearch = "" {
        didSet {
            if !registerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isCenterTrayExpanded = true
            }
        }
    }
    @Published private(set) var visibleWindows: Set<WorkspaceWindowKind> = [.center, .reportCenter]

    func markWindowVisible(_ kind: WorkspaceWindowKind, visible: Bool) {
        if visible {
            visibleWindows.insert(kind)
        } else {
            visibleWindows.remove(kind)
        }
    }

    func isWindowVisible(_ kind: WorkspaceWindowKind) -> Bool {
        visibleWindows.contains(kind)
    }

    var visibleWindowKinds: [WorkspaceWindowKind] {
        WorkspaceWindowKind.allCases.filter { visibleWindows.contains($0) }
    }

    func resetCustomerFilters() {
        customerSearch = ""
        customerSortMode = .alphabeticalAsc
        customerInitialFilter = "All"
        customerDateFilterMode = .allTime
        customerFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        customerToDate = Date()
    }
}

enum WorkspaceWindowKind: String, CaseIterable, Hashable {
    case center
    case reportCenter
    case report
    case customer
    case navigator
    case checkDesk
    case help
    case techSupport
    case claudeControl

    var frameAutosaveName: String {
        switch self {
        case .center:
            return "RenaissanceWorkspaceCenterWindow"
        case .reportCenter:
            return "RenaissanceWorkspaceReportCenterWindow"
        case .report:
            return "RenaissanceWorkspaceReportWindow"
        case .customer:
            return "RenaissanceWorkspaceCustomerWindow"
        case .navigator:
            return "RenaissanceWorkspaceNavigatorWindow"
        case .checkDesk:
            return "RenaissanceWorkspaceCheckDeskWindow"
        case .help:
            return "RenaissanceWorkspaceHelpWindow"
        case .techSupport:
            return "RenaissanceWorkspaceTechSupportWindow"
        case .claudeControl:
            return "RenaissanceWorkspaceClaudeControlWindow"
        }
    }

    var title: String {
        switch self {
        case .center:
            return "Customer Center / Register"
        case .reportCenter:
            return "Report Center"
        case .report:
            return "Historical QB P&L"
        case .customer:
            return "Customer Workspace"
        case .navigator:
            return "Renaissance Navigator"
        case .checkDesk:
            return "Check Desk"
        case .help:
            return "Help Me"
        case .techSupport:
            return "Tech Support"
        case .claudeControl:
            return "Claude App Control"
        }
    }
}

private struct WorkspaceWindowRecoveryProof: Codable {
    var generatedAt: String
    var entries: [WorkspaceWindowRecoveryEntry]
    var allPassed: Bool
}

private struct WorkspaceWindowRecoveryEntry: Codable {
    var kind: String
    var title: String
    var before: WorkspaceWindowFrame
    var afterMiniaturizeVisible: Bool
    var afterMiniaturizeMiniaturized: Bool
    var afterDeminiaturize: WorkspaceWindowFrame
    var afterCloseVisible: Bool
    var afterReopen: WorkspaceWindowFrame
    var restoredAfterCollapse: Bool
    var restoredAfterClose: Bool
}

private struct WorkspaceWindowFrame: Codable {
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

    func matches(_ other: WorkspaceWindowFrame, tolerance: Double = 2.0) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

private final class WorkspaceNativeWindowDelegate: NSObject, NSWindowDelegate {
    let kind: WorkspaceWindowKind
    let visibilityHandler: (WorkspaceWindowKind, Bool) -> Void

    init(kind: WorkspaceWindowKind, visibilityHandler: @escaping (WorkspaceWindowKind, Bool) -> Void) {
        self.kind = kind
        self.visibilityHandler = visibilityHandler
    }

    private func saveFrame(for window: NSWindow?) {
        guard let window else { return }
        window.saveFrame(usingName: kind.frameAutosaveName)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveFrame(for: sender)
        sender.orderOut(nil)
        visibilityHandler(kind, false)
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        saveFrame(for: notification.object as? NSWindow)
        visibilityHandler(kind, false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        visibilityHandler(kind, true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        visibilityHandler(kind, true)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(for: notification.object as? NSWindow)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame(for: notification.object as? NSWindow)
    }
}

@MainActor
final class WorkspaceWindowManager: ObservableObject {
    static let shared = WorkspaceWindowManager()

    let session = WorkspaceSession()
    let checkDesk = CheckDeskSession()
    private(set) var model: AppViewModel?
    private var windows: [WorkspaceWindowKind: NSWindow] = [:]
    private var delegates: [WorkspaceWindowKind: WorkspaceNativeWindowDelegate] = [:]
    private var supportCompletionWindow: NSWindow?
    private var suppressRestoreSnapshotSaves = false
    private var didBootstrapWindows = false

    private init() {}

    func configure(model: AppViewModel) {
        guard self.model !== model else { return }
        self.model = model
        if session.selectedCustomerID == nil {
            session.selectedCustomerID = model.customers.first?.id
        }
    }

    func bootstrapLaunchWindows() {
        guard let model else { return }
        guard !didBootstrapWindows else { return }
        didBootstrapWindows = true

        if shouldPreferNavigatorLaunch(for: model) {
            showNavigatorWindow()
            return
        }

        if shouldRestoreWorkspaceOnLaunch(), restoreSavedWorkspaceIfAvailable() {
            return
        }

        session.isReportViewerExpanded = false
        showCenterWindow()
        showReportCenterWindow()
        presentWindow(.navigator)

        if model.harnessLaunch.openCheckDesk {
            showCheckDeskForNewCheck()
        }

        arrangeLaunchWorkspaceWindows(includeCheckDesk: model.harnessLaunch.openCheckDesk)
        // Re-assert the clean launch layout on the next runloop tick so it wins over any
        // asynchronous content-driven repositioning (e.g. the Report Center size-sync),
        // which otherwise leaves the Report Center overlapping the Customer Center.
        let includeCheckDeskOnLaunch = model.harnessLaunch.openCheckDesk
        DispatchQueue.main.async { [weak self] in
            self?.arrangeLaunchWorkspaceWindows(includeCheckDesk: includeCheckDeskOnLaunch)
        }

        if model.harnessLaunch.navigationShellProof {
            session.centerMode = .customers
            session.isCenterTrayExpanded = true
            session.isReportViewerExpanded = true
            session.activeReportTab = .historicalPL
            showReportWindow()
            showNavigatorLauncher()
            arrangeLaunchWorkspaceWindows(includeReportWindow: true)
        }

        if model.harnessLaunch.windowRecoveryProof {
            session.centerMode = .customers
            session.isCenterTrayExpanded = true
            session.isReportViewerExpanded = true
            session.activeReportTab = .historicalPL
            showReportWindow()
            showNavigatorLauncher()
            arrangeLaunchWorkspaceWindows(includeReportWindow: true)
            scheduleHarnessWindowRecoveryProof(summaryPath: model.harnessLaunch.windowRecoverySummaryPath)
        }

        if let pendingReportTab = model.peekPendingReportTab(),
           let resolvedReportTab = AppViewModel.reportTab(from: pendingReportTab) {
            openReport(
                tab: resolvedReportTab,
                customerID: model.peekPendingReportCustomerID(),
                requestedHistoricalYear: model.peekPendingReportYear()
            )
            model.clearPendingReportRoute()
        }

        if let pendingCustomerID = model.peekPendingCustomerID(),
           model.customers.contains(where: { $0.id == pendingCustomerID }) {
            openCustomerWorkspace(customerID: pendingCustomerID)
            model.clearPendingCustomerID(pendingCustomerID)
        }
    }

    func reopenWorkspaceWindowsIfNeeded() {
        guard let model else { return }
        guard didBootstrapWindows else {
            bootstrapLaunchWindows()
            return
        }

        if windows.values.allSatisfy({ !$0.isVisible && !$0.isMiniaturized }) {
            if shouldPreferNavigatorLaunch(for: model) {
                showNavigatorWindow()
                return
            }
            showCenterWindow()
            showReportCenterWindow()
        }
    }

    func showCenterWindow() {
        presentWindow(.center)
    }

    func showReportCenterWindow() {
        presentWindow(.reportCenter)
        syncReportCenterWindowLayout()
    }

    func showReportWindow() {
        presentWindow(.report)
        if session.isWindowVisible(.reportCenter) {
            setReportViewerExpanded(false)
        }
    }

    func showCustomerWindow() {
        guard session.selectedCustomerID != nil else { return }
        presentWindow(.customer)
    }

    func showNavigatorWindow() {
        presentWindow(.navigator)
        syncNavigatorWindowLayout()
    }

    func showNavigatorLauncher() {
        model?.selectedTab = .workspace
        presentWindow(.navigator)
        syncNavigatorWindowLayout()
    }

    func showCheckDeskForNewCheck() {
        let defaultBankAccountName = model?.accounts.first { $0.type == "asset" && $0.name.localizedCaseInsensitiveContains("checking") }?.name
            ?? model?.accounts.first { $0.type == "asset" }?.name
            ?? "Checking Account"
        checkDesk.openNew(defaultBankAccountName: defaultBankAccountName)
        presentWindow(.checkDesk)
    }

    func showCheckDesk(for expense: ExpenseRow) {
        checkDesk.openExpense(expense)
        presentWindow(.checkDesk)
    }

    func showHelpWindow() {
        presentWindow(.help)
    }

    func showTechSupportWindow() {
        presentWindow(.techSupport)
    }

    func showClaudeControlWindow() {
        presentWindow(.claudeControl)
    }

    func saveRestoreSnapshot() {
        guard let model else { return }
        guard !suppressRestoreSnapshotSaves else { return }
        let visibleKinds = session.visibleWindowKinds
        let frames = Dictionary(
            uniqueKeysWithValues: visibleKinds.compactMap { kind -> (String, WorkspaceRestoreFrame)? in
                guard let frame = windows[kind]?.frame else { return nil }
                return (kind.rawValue, WorkspaceRestoreFrame(frame))
            }
        )

        let snapshot = WorkspaceRestoreSnapshot(
            savedAt: ISO8601DateFormatter().string(from: Date()),
            selectedTab: model.selectedTab.rawValue,
            centerMode: session.centerMode.rawValue,
            registerMode: session.registerMode.rawValue,
            activeReportTab: session.activeReportTab.rawValue,
            selectedCustomerID: session.selectedCustomerID,
            selectedBankAccountID: session.selectedBankAccountID,
            visibleWindows: visibleKinds.map(\.rawValue),
            windowFrames: frames
        )
        WorkspaceRestoreStore.shared.save(snapshot)
    }

    func showSupportCompletionNotice(_ notice: TechSupportCompletionNotice) {
        if supportCompletionWindow?.isVisible == true {
            return
        }

        let content = SupportCompletionNoticeView(notice: notice) { [weak self] in
            TechSupportStore.shared.dismissCompletionNotice(notice)
            self?.supportCompletionWindow?.orderOut(nil)
            self?.supportCompletionWindow = nil
        }
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tech Support Finished"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        supportCompletionWindow = window
    }

    private func arrangeLaunchWorkspaceWindows(includeCheckDesk: Bool = false, includeReportWindow: Bool = false) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1440, height: 900)
        let margin: CGFloat = 18
        let gap: CGFloat = 14
        let launcherFrame = NSRect(
            x: visibleFrame.minX + margin,
            y: visibleFrame.maxY - 214 - margin,
            width: 292,
            height: 214
        )

        // Match the collapsed Report Center width (see syncReportCenterWindowLayout's
        // 290 target) so that a later size-sync becomes a no-op and cannot right-anchor
        // the window off this left column on launch.
        let reportCenterWidth: CGFloat = 290
        let reportCenterHeight = min(max(visibleFrame.height - launcherFrame.height - (margin * 3) - gap, 420), 620)
        let reportCenterFrame = NSRect(
            x: visibleFrame.minX + margin,
            y: max(visibleFrame.minY + margin, launcherFrame.minY - gap - reportCenterHeight),
            width: reportCenterWidth,
            height: reportCenterHeight
        )

        let mainX = launcherFrame.maxX + gap
        let mainWidth = max(760, visibleFrame.width - (mainX - visibleFrame.minX) - margin)
        let centerHeight: CGFloat = includeCheckDesk ? 250 : min(330, max(285, visibleFrame.height * 0.28))
        let centerFrame = NSRect(
            x: mainX,
            y: visibleFrame.maxY - centerHeight - margin,
            width: mainWidth,
            height: centerHeight
        )

        setFrameIfWindowExists(.navigator, frame: launcherFrame, save: true)
        setFrameIfWindowExists(.reportCenter, frame: reportCenterFrame, save: true)
        setFrameIfWindowExists(.center, frame: centerFrame, save: true)

        if includeCheckDesk {
            let checkWidth = min(880, mainWidth)
            let checkHeight: CGFloat = 430
            let availableBelowCenter = max(0, centerFrame.minY - visibleFrame.minY - gap - margin)
            let checkY = availableBelowCenter >= checkHeight
                ? centerFrame.minY - gap - checkHeight
                : visibleFrame.minY + margin
            let checkFrame = NSRect(
                x: visibleFrame.maxX - checkWidth - margin,
                y: checkY,
                width: checkWidth,
                height: checkHeight
            )
            setFrameIfWindowExists(.checkDesk, frame: checkFrame, save: true)
        }

        if includeReportWindow {
            let reportWindowWidth = min(max(640, mainWidth * 0.48), 760)
            let reportWindowHeight: CGFloat = min(520, max(440, visibleFrame.height - centerHeight - (margin * 2) - gap))
            let reportFrame = NSRect(
                x: max(mainX, visibleFrame.maxX - reportWindowWidth - margin),
                y: max(visibleFrame.minY + margin, centerFrame.minY - gap - reportWindowHeight),
                width: reportWindowWidth,
                height: reportWindowHeight
            )
            setFrameIfWindowExists(.report, frame: reportFrame, save: true)
        }
    }

    private func setFrameIfWindowExists(_ kind: WorkspaceWindowKind, frame: NSRect, save: Bool) {
        guard let window = windows[kind] else { return }
        var adjustedFrame = frame.integral
        if let visibleFrame = NSScreen.main?.visibleFrame {
            adjustedFrame.size.width = min(adjustedFrame.width, visibleFrame.width - 24)
            adjustedFrame.size.height = min(adjustedFrame.height, visibleFrame.height - 24)
            adjustedFrame.origin.x = min(max(adjustedFrame.minX, visibleFrame.minX + 8), visibleFrame.maxX - adjustedFrame.width - 8)
            adjustedFrame.origin.y = min(max(adjustedFrame.minY, visibleFrame.minY + 8), visibleFrame.maxY - adjustedFrame.height - 8)
        }
        window.setFrame(adjustedFrame, display: true, animate: false)
        if save {
            window.saveFrame(usingName: kind.frameAutosaveName)
        }
    }

    func scheduleHarnessWindowRecoveryProof(summaryPath: String?) {
        guard let summaryPath, !summaryPath.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.runHarnessWindowRecoveryProof(summaryPath: summaryPath)
            }
        }
    }

    func openNavigatorRoute(_ tab: AppTab) {
        model?.selectedTab = tab
        presentWindow(.navigator)
        syncNavigatorWindowLayout()
    }

    func openCustomerWorkspace(customerID: Int64) {
        session.selectedCustomerID = customerID
        session.centerMode = .customers
        session.isCenterTrayExpanded = true
        updateCustomerWindowTitle()
        showCustomerWindow()
    }

    func openReport(tab: ReportTab, customerID: Int64? = nil, requestedHistoricalYear: Int? = nil) {
        if let customerID {
            session.selectedCustomerID = customerID
        }
        session.activeReportTab = tab
        session.requestedHistoricalYear = requestedHistoricalYear
        updateWindowTitle(for: .report, title: tab.rawValue)
        showReportCenterWindow()
        if session.isWindowVisible(.report) {
            setReportViewerExpanded(false)
            showReportWindow()
        } else {
            setReportViewerExpanded(true)
        }
    }

    func setCustomerWindowHidden() {
        guard let window = windows[.customer] else { return }
        window.orderOut(nil)
        session.markWindowVisible(.customer, visible: false)
    }

    func setReportViewerExpanded(_ expanded: Bool) {
        guard session.isReportViewerExpanded != expanded else {
            syncReportCenterWindowLayout()
            return
        }
        session.isReportViewerExpanded = expanded
        syncReportCenterWindowLayout()
    }

    private func presentWindow(_ kind: WorkspaceWindowKind) {
        guard let window = window(for: kind) else { return }
        window.title = resolvedTitle(for: kind)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        session.markWindowVisible(kind, visible: true)
        saveRestoreSnapshot()
    }

    private func shouldRestoreWorkspaceOnLaunch() -> Bool {
        !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--harness") })
    }

    private func restoreSavedWorkspaceIfAvailable() -> Bool {
        guard let model else { return false }
        guard let snapshot = WorkspaceRestoreStore.shared.load() else {
            saveRestoreSnapshot()
            return false
        }

        suppressRestoreSnapshotSaves = true
        defer {
            suppressRestoreSnapshotSaves = false
            saveRestoreSnapshot()
        }

        if let selectedTab = AppTab.resolve(snapshot.selectedTab) {
            model.selectedTab = selectedTab
        }
        if let centerMode = StartupCenterMode(rawValue: snapshot.centerMode) {
            session.centerMode = centerMode
        }
        if let registerMode = StartupRegisterMode(rawValue: snapshot.registerMode) {
            session.registerMode = registerMode
        }
        if let activeReportTab = ReportTab(rawValue: snapshot.activeReportTab) {
            session.activeReportTab = activeReportTab
        }
        if let selectedCustomerID = snapshot.selectedCustomerID,
           model.customers.contains(where: { $0.id == selectedCustomerID }) {
            session.selectedCustomerID = selectedCustomerID
        }
        session.selectedBankAccountID = snapshot.selectedBankAccountID

        let restoredKinds = snapshot.visibleWindows.compactMap(WorkspaceWindowKind.init(rawValue:))
        for kind in restoredKinds where kind != .customer || session.selectedCustomerID != nil {
            presentWindow(kind)
            if let restoreFrame = snapshot.windowFrames[kind.rawValue],
               let window = windows[kind] {
                window.setFrame(restoreFrame.rect, display: true)
                window.saveFrame(usingName: kind.frameAutosaveName)
            }
            syncLayoutIfNeeded(for: kind)
        }

        if restoredKinds.isEmpty {
            showCenterWindow()
            showReportCenterWindow()
            presentWindow(.navigator)
            arrangeLaunchWorkspaceWindows()
        }
        return true
    }

    private func runHarnessWindowRecoveryProof(summaryPath: String) async {
        let kinds: [WorkspaceWindowKind] = [.center, .reportCenter, .report, .navigator]
        var entries: [WorkspaceWindowRecoveryEntry] = []

        for kind in kinds {
            presentWindow(kind)
            syncLayoutIfNeeded(for: kind)
        }

        for kind in kinds {
            guard let window = window(for: kind) else { continue }
            presentWindow(kind)
            syncLayoutIfNeeded(for: kind)
            let before = WorkspaceWindowFrame(window.frame)

            window.saveFrame(usingName: kind.frameAutosaveName)
            window.performMiniaturize(nil)
            try? await Task.sleep(nanoseconds: 700_000_000)
            let afterMiniaturizeVisible = window.isVisible
            let afterMiniaturizeMiniaturized = window.isMiniaturized
            session.markWindowVisible(kind, visible: false)

            presentWindow(kind)
            syncLayoutIfNeeded(for: kind)
            try? await Task.sleep(nanoseconds: 250_000_000)
            let afterDeminiaturize = WorkspaceWindowFrame(window.frame)

            window.saveFrame(usingName: kind.frameAutosaveName)
            window.orderOut(nil)
            session.markWindowVisible(kind, visible: false)
            let afterCloseVisible = window.isVisible

            presentWindow(kind)
            syncLayoutIfNeeded(for: kind)
            try? await Task.sleep(nanoseconds: 250_000_000)
            let afterReopen = WorkspaceWindowFrame(window.frame)

            entries.append(
                WorkspaceWindowRecoveryEntry(
                    kind: kind.rawValue,
                    title: resolvedTitle(for: kind),
                    before: before,
                    afterMiniaturizeVisible: afterMiniaturizeVisible,
                    afterMiniaturizeMiniaturized: afterMiniaturizeMiniaturized,
                    afterDeminiaturize: afterDeminiaturize,
                    afterCloseVisible: afterCloseVisible,
                    afterReopen: afterReopen,
                    restoredAfterCollapse: before.matches(afterDeminiaturize),
                    restoredAfterClose: before.matches(afterReopen)
                )
            )
        }

        let proof = WorkspaceWindowRecoveryProof(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            entries: entries,
            allPassed: entries.allSatisfy {
                $0.afterMiniaturizeMiniaturized
                    && $0.restoredAfterCollapse
                    && $0.restoredAfterClose
                    && !$0.afterCloseVisible
            }
        )
        do {
            let url = URL(fileURLWithPath: summaryPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(proof)
            try data.write(to: url, options: .atomic)
            appendHarnessLog("window recovery proof wrote \(url.path)")
        } catch {
            appendHarnessLog("window recovery proof failed \(error.localizedDescription)")
        }
    }

    private func syncLayoutIfNeeded(for kind: WorkspaceWindowKind) {
        switch kind {
        case .reportCenter:
            syncReportCenterWindowLayout()
        case .navigator:
            syncNavigatorWindowLayout()
        default:
            break
        }
    }

    private func window(for kind: WorkspaceWindowKind) -> NSWindow? {
        if let window = windows[kind] {
            return window
        }
        guard let model else { return nil }

        let contentViewController = NSHostingController(
            rootView: rootView(for: kind)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(self)
                .environmentObject(checkDesk)
                .themedRoot()
        )

        let styleMask: NSWindow.StyleMask = kind == .checkDesk
            ? [.titled, .closable, .miniaturizable]
            : [.titled, .closable, .miniaturizable, .resizable]

        let window = NSWindow(
            contentRect: defaultFrame(for: kind),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.contentViewController = contentViewController
        window.title = resolvedTitle(for: kind)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(AppTheme.surface)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.tabbingMode = .disallowed
        window.minSize = minimumSize(for: kind)
        if kind == .checkDesk {
            window.maxSize = minimumSize(for: kind)
        }
        window.setFrameAutosaveName(kind.frameAutosaveName)
        _ = window.setFrameUsingName(kind.frameAutosaveName)

        let delegate = WorkspaceNativeWindowDelegate(kind: kind) { [weak self] kind, visible in
            Task { @MainActor in
                self?.session.markWindowVisible(kind, visible: visible)
            }
        }
        window.delegate = delegate
        delegates[kind] = delegate
        windows[kind] = window
        return window
    }

    private func syncReportCenterWindowLayout() {
        guard let window = windows[.reportCenter] else { return }

        let targetSize = session.isReportViewerExpanded
            ? CGSize(width: 1040, height: 620)
            : CGSize(width: 290, height: 560)
        let minSize = minimumSize(for: .reportCenter)

        let originalFrame = window.frame
        var frame = window.frame
        let newWidth: CGFloat
        let newHeight: CGFloat

        if session.isReportViewerExpanded {
            newWidth = max(frame.width, max(targetSize.width, minSize.width))
            newHeight = max(frame.height, max(targetSize.height, minSize.height))
        } else {
            newWidth = max(min(frame.width, targetSize.width), minSize.width)
            newHeight = max(frame.height, minSize.height)
        }
        let widthDelta = newWidth - frame.width
        let heightDelta = newHeight - frame.height

        frame.origin.x -= widthDelta
        frame.origin.y -= heightDelta
        frame.size.width = newWidth
        frame.size.height = newHeight

        if let visibleFrame = NSScreen.main?.visibleFrame {
            frame.size.width = min(frame.width, visibleFrame.width - 24)
            frame.size.height = min(frame.height, visibleFrame.height - 24)
            frame.origin.x = min(max(frame.minX, visibleFrame.minX + 8), visibleFrame.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.minY, visibleFrame.minY + 8), visibleFrame.maxY - frame.height - 8)
        }

        window.minSize = minSize
        if abs(frame.origin.x - originalFrame.origin.x) > 1
            || abs(frame.origin.y - originalFrame.origin.y) > 1
            || abs(frame.width - originalFrame.width) > 1
            || abs(frame.height - originalFrame.height) > 1 {
            window.setFrame(frame, display: true, animate: true)
        }
        window.saveFrame(usingName: WorkspaceWindowKind.reportCenter.frameAutosaveName)
    }

    private func syncNavigatorWindowLayout() {
        guard let window = windows[.navigator] else { return }

        let isLauncher = model?.selectedTab == .workspace
        let targetContentSize = isLauncher
            ? CGSize(width: 292, height: 186)
            : CGSize(width: 1260, height: 820)
        let minSize = minimumSize(for: .navigator)

        let currentContentSize = window.contentLayoutRect.size
        let widthDelta = targetContentSize.width - currentContentSize.width
        let heightDelta = targetContentSize.height - currentContentSize.height

        window.minSize = minSize
        if abs(widthDelta) > 1 || abs(heightDelta) > 1 {
            let topEdge = window.frame.maxY
            window.setContentSize(targetContentSize)
            var anchoredFrame = window.frame
            anchoredFrame.origin.y = topEdge - anchoredFrame.height
            window.setFrame(anchoredFrame, display: true, animate: !isLauncher)
        }
        window.saveFrame(usingName: WorkspaceWindowKind.navigator.frameAutosaveName)
    }

    private func updateWindowTitle(for kind: WorkspaceWindowKind, title: String) {
        windows[kind]?.title = title
    }

    private func updateCustomerWindowTitle() {
        updateWindowTitle(for: .customer, title: resolvedTitle(for: .customer))
    }

    private func shouldPreferNavigatorLaunch(for model: AppViewModel) -> Bool {
        let requestedTab = model.harnessLaunch.selectedTab
        return (requestedTab != nil && requestedTab != .workspace)
            || model.peekPendingEstimateID() != nil
            || model.peekPendingInvoiceID() != nil
            || model.peekPendingEditEstimateID() != nil
            || model.peekPendingEditInvoiceID() != nil
            || model.harnessLaunch.openWriteCheck
            || model.harnessLaunch.reviewFirstOrderSheet
            || model.harnessLaunch.previewEstimateItemQuery != nil
            || model.harnessLaunch.previewInvoiceItemQuery != nil
            || model.harnessLaunch.previewWriteCheckPayeeQuery != nil
            || model.harnessLaunch.previewEstimateInvoiceProgressChooser
            || model.harnessLaunch.verifyInvoiceManualDescription
            || model.harnessLaunch.emailEstimateOnOpen
            || model.harnessLaunch.emailInvoiceOnOpen
    }

    private func resolvedTitle(for kind: WorkspaceWindowKind) -> String {
        switch kind {
        case .report:
            return session.activeReportTab.rawValue
        case .customer:
            guard let model, let customerID = session.selectedCustomerID else {
                return WorkspaceWindowKind.customer.title
            }
            return model.customers.first(where: { $0.id == customerID })?.displayName ?? WorkspaceWindowKind.customer.title
        default:
            return kind.title
        }
    }

    private func minimumSize(for kind: WorkspaceWindowKind) -> CGSize {
        switch kind {
        case .center:
            return CGSize(width: 760, height: 250)
        case .reportCenter:
            return session.isReportViewerExpanded
                ? CGSize(width: 920, height: 520)
                : CGSize(width: 260, height: 420)
        case .report:
            return CGSize(width: 640, height: 480)
        case .customer:
            return CGSize(width: 820, height: 620)
        case .navigator:
            return model?.selectedTab == .workspace
                ? CGSize(width: 280, height: 176)
                // Tabbed content (app-nav rail 268 + customer list 240 + detail pane ~640
                // + padding) needs ~1210pt; keep the floor above that so columns never overlap.
                : CGSize(width: 1240, height: 700)
        case .checkDesk:
            return CGSize(width: 880, height: 430)
        case .help:
            return CGSize(width: 720, height: 560)
        case .techSupport:
            return CGSize(width: 560, height: 460)
        case .claudeControl:
            return CGSize(width: 560, height: 420)
        }
    }

    private func defaultFrame(for kind: WorkspaceWindowKind) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 120, y: 120, width: 1440, height: 900)

        switch kind {
        case .center:
            return NSRect(x: visibleFrame.minX + 24, y: visibleFrame.maxY - 340, width: 980, height: 300)
        case .reportCenter:
            if session.isReportViewerExpanded {
                return NSRect(x: visibleFrame.maxX - 1060, y: visibleFrame.maxY - 680, width: 1040, height: 620)
            }
            return NSRect(x: visibleFrame.maxX - 310, y: visibleFrame.maxY - 620, width: 290, height: 560)
        case .report:
            return NSRect(x: visibleFrame.maxX - 980, y: visibleFrame.maxY - 680, width: 660, height: 540)
        case .customer:
            return NSRect(x: visibleFrame.minX + 100, y: visibleFrame.maxY - 820, width: 940, height: 720)
        case .navigator:
            if model?.selectedTab == .workspace {
                return NSRect(x: visibleFrame.maxX - 310, y: visibleFrame.maxY - 826, width: 292, height: 186)
            }
            // Open the tabbed content near full screen width so the 3-column
            // screens (nav rail 268 + list 240 + detail) never start out cramped.
            let navWidth = min(1480, visibleFrame.width - 40)
            let navHeight = min(900, visibleFrame.height - 40)
            return NSRect(
                x: visibleFrame.minX + (visibleFrame.width - navWidth) / 2,
                y: visibleFrame.maxY - navHeight - 20,
                width: navWidth,
                height: navHeight
            )
        case .checkDesk:
            return NSRect(x: visibleFrame.minX + 90, y: visibleFrame.maxY - 550, width: 880, height: 430)
        case .help:
            return NSRect(x: visibleFrame.minX + 120, y: visibleFrame.maxY - 760, width: 860, height: 680)
        case .techSupport:
            return NSRect(x: visibleFrame.minX + 150, y: visibleFrame.maxY - 660, width: 640, height: 520)
        case .claudeControl:
            return NSRect(x: visibleFrame.minX + 180, y: visibleFrame.maxY - 640, width: 620, height: 500)
        }
    }
}
