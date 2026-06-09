import SwiftUI

struct SyncCenterView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Old QB Sync Center")
                        .font(.title2.bold())
                    Text("Prepare and review old-QuickBooks drift handling before the live old-Mac scan is turned on.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                Spacer()
                if let scannedAt = model.oldQBSyncSnapshot.lastScanAt {
                    Text("Last scan: \(scannedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                } else {
                    Text("Live scan pending old-Mac availability")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        syncStatCard("Pending Estimates", "\(model.oldQBSyncSnapshot.pendingEstimateCount)")
                        syncStatCard("Pending Invoices", "\(model.oldQBSyncSnapshot.pendingInvoiceCount)")
                        syncStatCard("Pending Checks", "\(model.oldQBSyncSnapshot.pendingCheckCount)")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Prepared Behavior", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                            Text("The app-side Sync Center is now staged. Once both Macs are on, this will scan old QuickBooks for semantic drift, auto-import safe estimate/invoice deltas, and flag checks or self-pay patterns for review instead of forcing them through blindly.")
                                .foregroundStyle(AppTheme.ink3)
                                .font(.subheadline)
                            Text(model.oldQBSyncSnapshot.lastResultSummary)
                                .font(.subheadline)
                        }
                        .padding(8)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Sync Rules", systemImage: "checklist")
                                .font(.headline)

                            Toggle("Auto-scan old QuickBooks when the app launches", isOn: Binding(
                                get: { model.oldQBSyncSettings.autoScanOnLaunch },
                                set: { newValue in
                                    var settings = model.oldQBSyncSettings
                                    settings.autoScanOnLaunch = newValue
                                    model.saveOldQBSyncSettings(settings)
                                }
                            ))

                            Toggle("Show sync alerts in the app when drift is found", isOn: Binding(
                                get: { model.oldQBSyncSettings.showSyncTabBadge },
                                set: { newValue in
                                    var settings = model.oldQBSyncSettings
                                    settings.showSyncTabBadge = newValue
                                    model.saveOldQBSyncSettings(settings)
                                }
                            ))

                            Toggle("Auto-import safe estimate and invoice drift", isOn: Binding(
                                get: { model.oldQBSyncSettings.importSafeEstimateAndInvoiceDrift },
                                set: { newValue in
                                    var settings = model.oldQBSyncSettings
                                    settings.importSafeEstimateAndInvoiceDrift = newValue
                                    model.saveOldQBSyncSettings(settings)
                                }
                            ))

                            Toggle("Require review for checks, self-pay, or cash-sensitive entries", isOn: Binding(
                                get: { model.oldQBSyncSettings.reviewChecksBeforeImport },
                                set: { newValue in
                                    var settings = model.oldQBSyncSettings
                                    settings.reviewChecksBeforeImport = newValue
                                    model.saveOldQBSyncSettings(settings)
                                }
                            ))
                        }
                        .padding(8)
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            model.noteOldQBSyncPreparedOffline()
        }
    }

    private func syncStatCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Text(value)
                .font(.title2.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
