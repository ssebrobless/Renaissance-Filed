import AppKit
import SwiftUI

struct TechSupportWindowView: View {
    @EnvironmentObject private var model: AppViewModel
    @ObservedObject private var supportStore = TechSupportStore.shared
    @State private var message = ""
    @State private var statusMessage = "Describe the problem in your own words."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tech Support")
                        .font(.title2.bold())
                    Text("Tell us what is confusing or broken. This sends a safe support request for Claude and Codex.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }

                Spacer()

                Button("Send") {
                    sendRequest()
                }
                .buttonStyle(.renaissancePrimary)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityIdentifier("techSupport.sendButton")
            }

            TextEditor(text: $message)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 170)
                .background(AppTheme.cardFill)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("techSupport.message")

            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(AppTheme.accent)
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(AppTheme.ink3)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("What happens next")
                    .font(.headline)
                supportStep("The app saves your message and the workspace you had open.")
                supportStep("Claude collects screenshots, app state, and read-only ledger checks.")
                supportStep("Codex uses that packet to repair the app and verify the build.")
                supportStep("No business data is changed just by sending this request.")
            }

            if !supportStore.recentRequests.isEmpty {
                recentRequests
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 460)
        .background(AppTheme.surface)
    }

    private var recentRequests: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Requests")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink3)

            ForEach(supportStore.recentRequests.prefix(3)) { request in
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.clock")
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(request.userMessage.prefix(90)))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("Request \(request.id.uuidString.prefix(8)) - \(request.status.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(AppTheme.cardFillSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func supportStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 2)
            Text(text)
                .foregroundStyle(AppTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sendRequest() {
        do {
            let request = try supportStore.submit(
                message: message,
                selectedTab: model.selectedTab.rawValue,
                visibleWindowTitles: visibleWindowTitles()
            )
            message = ""
            statusMessage = "Tech Support request sent. Request \(request.id.uuidString.prefix(8)) is waiting for review."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func visibleWindowTitles() -> [String] {
        NSApp.windows
            .filter { $0.isVisible }
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
