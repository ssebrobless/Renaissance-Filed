import SwiftUI

final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showDashboard()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    func showDashboard() {
        let controller = HarnessController.shared
        if let window {
            window.contentView = NSHostingView(rootView: HarnessDashboardView(controller: controller))
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 860, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Renaissance Harness"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: HarnessDashboardView(controller: controller))
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HarnessDashboardView: View {
    @ObservedObject var controller: HarnessController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Renaissance Harness")
                        .font(.largeTitle.bold())
                    Text("Use this app to approve permissions, inspect harness state, and run quick probes.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Probe") {
                    controller.runProbeManually()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isProcessing)
            }

            HStack(spacing: 12) {
                statusCard(
                    title: "Helper Status",
                    value: controller.statusText,
                    accent: controller.isProcessing ? .orange : .green
                )
                statusCard(
                    title: "Accessibility",
                    value: controller.accessibilityGranted ? "Granted" : "Needs approval",
                    accent: controller.accessibilityGranted ? .green : .orange
                )
                statusCard(
                    title: "Screen Recording",
                    value: controller.screenRecordingGranted ? "Granted" : "Needs approval",
                    accent: controller.screenRecordingGranted ? .green : .orange
                )
            }

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Approve the requested permissions for this helper, then leave it installed. Future test runs can reuse the same approved copy.")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Open Accessibility Settings") {
                            controller.openAccessibilitySettings()
                        }
                        Button("Request Accessibility Permission") {
                            controller.requestAccessibilityPermission()
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Open Screen Recording Settings") {
                            controller.openScreenRecordingSettings()
                        }
                        Button("Request Screen Recording Permission") {
                            controller.requestScreenRecordingPermission()
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Open Full Disk Access Settings") {
                            controller.openFullDiskAccessSettings()
                        }
                        Text("Your father still needs to manually enable Renaissance Harness and Terminal there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Tools") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Last Run", value: controller.lastRunSummary)
                    HStack(spacing: 10) {
                        Button("Open Artifacts Folder") {
                            controller.openArtifactsFolder()
                        }
                        Button("Refresh Status") {
                            controller.refreshPermissionState()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 460)
    }

    private func statusCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            RoundedRectangle(cornerRadius: 999)
                .fill(accent)
                .frame(width: 42, height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

@main
struct RenaissanceHarnessApp: App {
    @NSApplicationDelegateAdaptor(HarnessAppDelegate.self) private var appDelegate
    @StateObject private var controller = HarnessController.shared

    var body: some Scene {
        MenuBarExtra("Renaissance Harness", systemImage: "cursorarrow.rays") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Renaissance Harness")
                    .font(.headline)

                Divider()

                LabeledContent("Status", value: controller.statusText)
                LabeledContent("Last Run", value: controller.lastRunSummary)

                Divider()

                Button("Run Probe") {
                    controller.runProbeManually()
                }
                .disabled(controller.isProcessing)

                Button("Open Artifacts Folder") {
                    controller.openArtifactsFolder()
                }

                Button("Open Dashboard") {
                    appDelegate.showDashboard()
                }

                Button("Open Accessibility Settings") {
                    controller.openAccessibilitySettings()
                }

                Button("Request Accessibility Permission") {
                    controller.requestAccessibilityPermission()
                }

                Button("Open Screen Recording Settings") {
                    controller.openScreenRecordingSettings()
                }

                Button("Request Screen Recording Permission") {
                    controller.requestScreenRecordingPermission()
                }

                Button("Open Full Disk Access Settings") {
                    controller.openFullDiskAccessSettings()
                }

                Divider()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}
