import AppKit
import SwiftUI

let workspaceBootstrapWindowIdentifier = NSUserInterfaceItemIdentifier("RenaissanceWorkspaceBootstrapWindow")

struct WorkspaceBootstrapView: View {
    @State private var didHideBootstrapWindow = false
    @ObservedObject private var supportStore = TechSupportStore.shared

    var body: some View {
        Color.clear
            .background(
                WorkspaceBootstrapWindowAccessor { window in
                    guard let window else { return }
                    window.identifier = workspaceBootstrapWindowIdentifier
                    window.isExcludedFromWindowsMenu = true
                    if !didHideBootstrapWindow {
                        didHideBootstrapWindow = true
                        window.setContentSize(NSSize(width: 1, height: 1))
                    }
                    if window.isVisible {
                        window.orderOut(nil)
                    }
                }
            )
            .onAppear {
                WorkspaceWindowManager.shared.bootstrapLaunchWindows()
            }
            .task {
                while !Task.isCancelled {
                    supportStore.pollCompletionNotice()
                    if let notice = supportStore.pendingCompletionNotice {
                        WorkspaceWindowManager.shared.showSupportCompletionNotice(notice)
                    }
                    if let model = WorkspaceWindowManager.shared.model {
                        ClaudeAppControlStore.shared.pollAndApply(model: model, windowManager: WorkspaceWindowManager.shared)
                    }
                    WorkspaceWindowManager.shared.saveRestoreSnapshot()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
    }
}

private struct WorkspaceBootstrapWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}
