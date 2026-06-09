import SwiftUI

struct SupportCompletionNoticeView: View {
    let notice: TechSupportCompletionNotice
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.dadSummaryTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.bodyText)
                    Text("Tech Support finished this update.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }

                Spacer()

                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.renaissanceSecondary)
            }

            Text(notice.dadSummaryBody)
                .foregroundStyle(AppTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            if notice.appWasRestarted {
                Label("Your windows were restored as closely as possible after the update.", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            if !notice.filesChanged.isEmpty {
                Text("What changed: \(notice.filesChanged.prefix(4).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .lineLimit(2)
            }
        }
        .padding(18)
        .frame(width: 430)
        .background(AppTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
    }
}
