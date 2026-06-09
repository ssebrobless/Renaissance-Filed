import SwiftUI

@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installWorkspaceMenu()
        WorkspaceWindowManager.shared.bootstrapLaunchWindows()
        guard ProcessInfo.processInfo.arguments.contains("--harness-show-main-window") else { return }
        presentHarnessWindows(retries: 10, delay: 0.4)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--harness-show-main-window") else { return }
        presentHarnessWindows(retries: 6, delay: 0.25)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WorkspaceWindowManager.shared.reopenWorkspaceWindowsIfNeeded()
        }
        return true
    }

    @objc private func showCenterWindow(_ sender: Any?) {
        WorkspaceWindowManager.shared.showCenterWindow()
    }

    @objc private func showReportCenterWindow(_ sender: Any?) {
        WorkspaceWindowManager.shared.showReportCenterWindow()
    }

    @objc private func showReportWindow(_ sender: Any?) {
        WorkspaceWindowManager.shared.showReportWindow()
    }

    @objc private func showNavigatorWindow(_ sender: Any?) {
        WorkspaceWindowManager.shared.showNavigatorWindow()
    }

    @objc private func showCheckDeskWindow(_ sender: Any?) {
        WorkspaceWindowManager.shared.showCheckDeskForNewCheck()
    }

    @objc private func showAskClaudeWindow(_ sender: Any?) {
        WorkspaceWindowManager.shared.showClaudeControlWindow()
    }

    private func installWorkspaceMenu() {
        guard let mainMenu = NSApp.mainMenu, mainMenu.item(withTitle: "Workspace") == nil else { return }

        let workspaceItem = NSMenuItem(title: "Workspace", action: nil, keyEquivalent: "")
        let workspaceMenu = NSMenu(title: "Workspace")

        let menuItems: [(String, Selector)] = [
            ("Show Customer Center / Register", #selector(showCenterWindow(_:))),
            ("Show Report Center", #selector(showReportCenterWindow(_:))),
            ("Pop Out Report Window", #selector(showReportWindow(_:))),
            ("Show Check Desk", #selector(showCheckDeskWindow(_:))),
            ("Show Navigator", #selector(showNavigatorWindow(_:))),
            ("Ask Claude to Enter…", #selector(showAskClaudeWindow(_:))),
        ]

        for (title, action) in menuItems {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            workspaceMenu.addItem(item)
        }

        workspaceItem.submenu = workspaceMenu
        let insertionIndex = mainMenu.items.firstIndex(where: { $0.title == "Window" }) ?? mainMenu.items.count
        mainMenu.insertItem(workspaceItem, at: insertionIndex)
    }
}

@main
struct RenaissanceLedgerApp: App {
    @NSApplicationDelegateAdaptor(HarnessAppDelegate.self) private var appDelegate
    @StateObject private var model: AppViewModel

    init() {
        let model = AppViewModel()
        _model = StateObject(wrappedValue: model)
        WorkspaceWindowManager.shared.configure(model: model)
    }

    var body: some Scene {
        WindowGroup("Renaissance Bootstrap") {
            WorkspaceBootstrapView()
                .environmentObject(model)
                .frame(width: 1, height: 1)
                .themedRoot()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Assistant") {
                Button("Ask Claude to Enter…") {
                    WorkspaceWindowManager.shared.showClaudeControlWindow()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .themedRoot()
        }
    }
}
