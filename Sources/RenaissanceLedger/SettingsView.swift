import AppKit
import SwiftUI

private enum AppearanceColorTarget {
    case primary
    case accent1
    case accent2
    case text1
    case text2
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @ObservedObject private var appearance = AppAppearanceSettings.shared
    @State private var lastBackupDate: String = ""
    @State private var backupMessage = ""
    @State private var backupIsError = false
    @State private var orderSheetInboxEnabled = false
    @State private var orderSheetInboxFolderPath = ""
    @State private var orderSheetDeleteAfterStage = true
    @State private var orderSheetInboxMessage = ""
    @State private var orderSheetInboxIsError = false
    @State private var orderSheetTestingModeEnabled = true
    @State private var orderSheetRequireApprovalConfirmation = true
    @State private var orderSheetApprovalMessage = ""
    @State private var mailReviewPreferredProvider: MailProviderKind = .appleMail
    @State private var mailReviewEnabled = true
    @State private var mailReviewAutoRefresh = true
    @State private var mailReviewIncludeCustomerEmails = true
    @State private var mailReviewVIPEmails = ""
    @State private var mailReviewVIPDomains = ""
    @State private var mailReviewScanLikelyJunk = true
    @State private var mailReviewAutoTrashStrongJunk = false
    @State private var mailReviewJunkEmails = ""
    @State private var mailReviewJunkDomains = ""
    @State private var mailReviewJunkKeywords = ""
    @State private var mailReviewMaxOtherUnread = 20
    @State private var mailReviewMessage = ""
    @State private var mailReviewIsError = false
    @State private var warnOnDuplicateEstimateNumbers = true
    @State private var warnOnDuplicateInvoiceNumbers = true
    @State private var duplicateWarningMessage = ""
    @State private var paymentWorkflowAutoApplyPayments = true
    @State private var paymentWorkflowAutoApplyCredits = true
    @State private var paymentWorkflowDefaultMethod = "Check"
    @State private var paymentWorkflowUseUndepositedFunds = true
    @State private var paymentWorkflowDefaultDepositAccountID: Int64 = 0
    @State private var paymentWorkflowMessage = ""
    @State private var checkWorkflowDefaultCodingMode: CheckCodingMode = .category
    @State private var checkWorkflowShowCategoryOnPrintedChecks = true
    @State private var checkWorkflowShowMemoOnPrintedChecks = true
    @State private var checkWorkflowDefaultBankAccountID: Int64 = 0
    @State private var checkWorkflowMessage = ""
    @State private var memorizedTemplates: [MemorizedTransactionRow] = []
    @State private var memorizedTemplateMessage = ""
    @State private var memorizedTemplateIsError = false
    @State private var expandedAppearanceColor: AppearanceColorTarget?

    // Company info form state
    @State private var companyName = ""
    @State private var companyPhone = ""
    @State private var companyAddress1 = ""
    @State private var companyCityStateZip = ""
    @State private var companyEmail = ""
    @State private var companyLicense = ""
    @State private var companyPaymentTerms = ""
    @State private var companyInvoiceFooter = ""
    @State private var companySaveMessage = ""

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings & Backup")
                .font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Appearance", systemImage: "paintpalette")
                            .font(.headline)

                        Spacer()

                        Button("Reset Appearance") {
                            closeAppearanceColorPanel()
                            appearance.resetToDefaults()
                        }
                        .buttonStyle(.renaissanceSecondary)
                    }

                    Text("Use these controls to tune readability and the brown / gold / beige theme without changing business data.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Universal Font Size")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(appearance.fontScale * 100))%")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(AppTheme.ink3)
                        }

                        Slider(value: $appearance.fontScale, in: 1.0...1.65, step: 0.05) {
                            Text("Universal Font Size")
                        }
                        .labelsHidden()

                        Text("Text uses at least \(Int(appearance.minimumFontSize)) pt where the app can control it, and SwiftUI text styles scale up with this setting.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }
                    .padding(10)
                    .background(AppTheme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    appearanceColorControl(
                        title: "Primary Background",
                        subtitle: "Main dark brown surfaces and window backgrounds.",
                        color: $appearance.primary,
                        target: .primary
                    )
                    appearanceColorControl(
                        title: "Accent Color 1",
                        subtitle: "Primary gold for buttons, selections, and important actions.",
                        color: $appearance.accent1,
                        target: .accent1
                    )
                    appearanceColorControl(
                        title: "Accent Color 2",
                        subtitle: "Secondary gold highlight used for pressed states and emphasis.",
                        color: $appearance.accent2,
                        target: .accent2
                    )
                    appearanceColorControl(
                        title: "Text Color 1",
                        subtitle: "Primary readable text.",
                        color: $appearance.text1,
                        target: .text1
                    )
                    appearanceColorControl(
                        title: "Text Color 2",
                        subtitle: "Subtext, helper text, table headers, and secondary labels.",
                        color: $appearance.text2,
                        target: .text2
                    )
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Backup section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Database Backup", systemImage: "externaldrive")
                        .font(.headline)

                    Text("Backs up ledger.sqlite to ~/Documents/Renaissance Filed Backups/ with today's date.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    if !lastBackupDate.isEmpty {
                        Label("Last backup: \(lastBackupDate)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.ok)
                            .font(.subheadline)
                    }

                    Button("Export Backup Now") {
                        exportBackup()
                    }
                    .buttonStyle(.renaissancePrimary)

                    if !backupMessage.isEmpty {
                        Label(backupMessage, systemImage: backupIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(backupIsError ? AppTheme.bad : AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Time Machine reminder
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Time Machine", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("If Time Machine is enabled on this Mac, your data is automatically backed up continuously. This is the best protection against data loss.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // DB path
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Database Location", systemImage: "internaldrive")
                        .font(.headline)
                    Text("~/Library/Application Support/RenaissanceLedger/ledger.sqlite")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(AppTheme.ink3)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Phone Order Sheet Inbox", systemImage: "iphone.and.arrow.forward")
                        .font(.headline)

                    Text("Share order sheet photos or scanned PDFs from iPhone into this folder. The Mac will stage them automatically for review in Estimates, and nothing will touch the official ledger until it is approved.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Toggle("Watch inbox folder automatically", isOn: Binding(
                        get: { orderSheetInboxEnabled },
                        set: { newValue in
                            orderSheetInboxEnabled = newValue
                            persistOrderSheetInboxSettings()
                        }
                    ))

                    Toggle("Delete from iCloud inbox after staging", isOn: Binding(
                        get: { orderSheetDeleteAfterStage },
                        set: { newValue in
                            orderSheetDeleteAfterStage = newValue
                            persistOrderSheetInboxSettings()
                        }
                    ))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watched Folder")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        Text(orderSheetInboxFolderPath.isEmpty ? "Not configured" : orderSheetInboxFolderPath)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(AppTheme.ink3)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button("Use Recommended Inbox") {
                            useRecommendedOrderSheetInbox()
                        }
                        .buttonStyle(.renaissancePrimary)

                        Button("Choose Folder...") {
                            chooseOrderSheetInboxFolder()
                        }

                        Button("Open Folder") {
                            model.openOrderSheetInboxFolder()
                        }

                        Button("Scan Now") {
                            model.scanOrderSheetInboxNow()
                            orderSheetInboxMessage = "Scanning watched folder now."
                            orderSheetInboxIsError = false
                        }
                    }

                    Text(orderSheetDeleteAfterStage
                         ? "Files are removed from the inbox after they are safely copied into the app's private staging storage."
                         : "Files stay in the inbox after staging. Leave this off only if you want to keep the original iCloud copies.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)

                    if !orderSheetInboxMessage.isEmpty {
                        Label(orderSheetInboxMessage, systemImage: orderSheetInboxIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(orderSheetInboxIsError ? AppTheme.bad : AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Order Sheet Review Safety", systemImage: "checklist.checked")
                        .font(.headline)

                    Text("Use testing mode while reviewing imported order sheets so no draft can be pushed into the official estimate ledger by accident.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Toggle("Testing mode: block approval into official estimates", isOn: Binding(
                        get: { orderSheetTestingModeEnabled },
                        set: { newValue in
                            orderSheetTestingModeEnabled = newValue
                            persistOrderSheetApprovalSettings()
                        }
                    ))

                    Toggle("Require confirmation before creating an official estimate", isOn: Binding(
                        get: { orderSheetRequireApprovalConfirmation },
                        set: { newValue in
                            orderSheetRequireApprovalConfirmation = newValue
                            persistOrderSheetApprovalSettings()
                        }
                    ))

                    Text(orderSheetTestingModeEnabled
                         ? "Testing mode is on. Order sheet reviews and draft saves stay in staging only."
                         : "Testing mode is off. Approved order sheets can create official estimates after confirmation.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)

                    if !orderSheetApprovalMessage.isEmpty {
                        Label(orderSheetApprovalMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Morning Mail Review", systemImage: "envelope.badge")
                        .font(.headline)

                    Text("Prepare the app to scan unread mail on this Mac, use your selected email app, surface likely work senders first, and optionally auto-trash strong junk matches.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Picker("Preferred Email App", selection: Binding(
                        get: { mailReviewPreferredProvider },
                        set: { newValue in
                            mailReviewPreferredProvider = newValue
                            persistMailReviewSettings()
                        }
                    )) {
                        ForEach(MailProviderKind.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .frame(width: 220)

                    Toggle("Enable Morning Mail Review", isOn: Binding(
                        get: { mailReviewEnabled },
                        set: { newValue in
                            mailReviewEnabled = newValue
                            persistMailReviewSettings()
                        }
                    ))

                    Toggle("Refresh unread messages automatically when the app opens", isOn: Binding(
                        get: { mailReviewAutoRefresh },
                        set: { newValue in
                            mailReviewAutoRefresh = newValue
                            persistMailReviewSettings()
                        }
                    ))

                    Toggle("Treat customer email addresses as work-priority senders", isOn: Binding(
                        get: { mailReviewIncludeCustomerEmails },
                        set: { newValue in
                            mailReviewIncludeCustomerEmails = newValue
                            persistMailReviewSettings()
                        }
                    ))

                    Toggle("Flag likely junk / promotional unread mail", isOn: Binding(
                        get: { mailReviewScanLikelyJunk },
                        set: { newValue in
                            mailReviewScanLikelyJunk = newValue
                            persistMailReviewSettings()
                        }
                    ))

                    Toggle("Auto-trash strong junk matches on refresh", isOn: Binding(
                        get: { mailReviewAutoTrashStrongJunk },
                        set: { newValue in
                            mailReviewAutoTrashStrongJunk = newValue
                            persistMailReviewSettings()
                        }
                    ))

                    Text("Strong junk means explicit junk senders/domains or multi-signal spam-style mail. Weaker junk matches still stay visible for review.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("VIP Sender Emails")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        TextEditor(text: $mailReviewVIPEmails)
                            .font(.system(.subheadline, design: .monospaced))
                            .frame(minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline))
                            .onChange(of: mailReviewVIPEmails) { _ in
                                persistMailReviewSettings()
                            }
                        Text("Add one email per line, or separate with commas or semicolons.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("VIP Sender Domains")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        TextEditor(text: $mailReviewVIPDomains)
                            .font(.system(.subheadline, design: .monospaced))
                            .frame(minHeight: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline))
                            .onChange(of: mailReviewVIPDomains) { _ in
                                persistMailReviewSettings()
                            }
                        Text("Examples: builder.com, architect.net")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Known Junk Sender Emails")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        TextEditor(text: $mailReviewJunkEmails)
                            .font(.system(.subheadline, design: .monospaced))
                            .frame(minHeight: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline))
                            .onChange(of: mailReviewJunkEmails) { _ in
                                persistMailReviewSettings()
                            }
                        Text("Optional: specific junk sender addresses you always want flagged.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Known Junk Domains")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        TextEditor(text: $mailReviewJunkDomains)
                            .font(.system(.subheadline, design: .monospaced))
                            .frame(minHeight: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline))
                            .onChange(of: mailReviewJunkDomains) { _ in
                                persistMailReviewSettings()
                            }
                        Text("Optional: domains you always want treated as junk, like persistent promo senders.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Junk Subject Keywords")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                        TextEditor(text: $mailReviewJunkKeywords)
                            .font(.system(.subheadline, design: .monospaced))
                            .frame(minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.hairline))
                            .onChange(of: mailReviewJunkKeywords) { _ in
                                persistMailReviewSettings()
                            }
                        Text("Examples: unsubscribe, promo, newsletter, special offer, limited time.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }

                    Stepper(
                        "Show up to \(mailReviewMaxOtherUnread) non-priority unread messages",
                        value: $mailReviewMaxOtherUnread,
                        in: 5...100,
                        step: 5,
                        onEditingChanged: { _ in persistMailReviewSettings() }
                    )

                    HStack {
                        Button("Refresh Mail Now") {
                            model.refreshMailReview()
                            mailReviewMessage = "Mail refresh started."
                            mailReviewIsError = false
                        }
                        .buttonStyle(.renaissancePrimary)
                        .disabled(!mailReviewEnabled)

                        Text("The first refresh may prompt macOS to allow Renaissance Filed to access Mail.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink3)
                    }

                    if !mailReviewMessage.isEmpty {
                        Label(mailReviewMessage, systemImage: mailReviewIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(mailReviewIsError ? AppTheme.bad : AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Document Number Warnings", systemImage: "number.square")
                        .font(.headline)

                    Text("Warn before saving when an estimate or invoice number is already in use. The database still stays protected even if warnings are turned off.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Toggle("Warn about duplicate estimate numbers", isOn: Binding(
                        get: { warnOnDuplicateEstimateNumbers },
                        set: { newValue in
                            warnOnDuplicateEstimateNumbers = newValue
                            persistDuplicateWarningSettings()
                        }
                    ))

                    Toggle("Warn about duplicate invoice numbers", isOn: Binding(
                        get: { warnOnDuplicateInvoiceNumbers },
                        set: { newValue in
                            warnOnDuplicateInvoiceNumbers = newValue
                            persistDuplicateWarningSettings()
                        }
                    ))

                    if !duplicateWarningMessage.isEmpty {
                        Label(duplicateWarningMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Payment Workflow", systemImage: "dollarsign.circle")
                        .font(.headline)

                    Text("Control how Receive Payment behaves when opening customer invoices and available credits.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Toggle("Auto-apply payment amounts to the oldest open invoices", isOn: Binding(
                        get: { paymentWorkflowAutoApplyPayments },
                        set: { newValue in
                            paymentWorkflowAutoApplyPayments = newValue
                            persistPaymentWorkflowSettings()
                        }
                    ))

                    Toggle("Auto-apply available credits during Receive Payment", isOn: Binding(
                        get: { paymentWorkflowAutoApplyCredits },
                        set: { newValue in
                            paymentWorkflowAutoApplyCredits = newValue
                            persistPaymentWorkflowSettings()
                        }
                    ))

                    Picker("Default payment method", selection: Binding(
                        get: { paymentWorkflowDefaultMethod },
                        set: { newValue in
                            paymentWorkflowDefaultMethod = newValue
                            persistPaymentWorkflowSettings()
                        }
                    )) {
                        ForEach(paymentWorkflowMethodOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .frame(width: 240)

                    Toggle("Receive payments into Undeposited Funds by default", isOn: Binding(
                        get: { paymentWorkflowUseUndepositedFunds },
                        set: { newValue in
                            paymentWorkflowUseUndepositedFunds = newValue
                            persistPaymentWorkflowSettings()
                        }
                    ))

                    Picker("Default deposit account", selection: Binding(
                        get: { paymentWorkflowDefaultDepositAccountID },
                        set: { newValue in
                            paymentWorkflowDefaultDepositAccountID = newValue
                            persistPaymentWorkflowSettings()
                        }
                    )) {
                        Text("Choose at deposit time").tag(Int64(0))
                        ForEach(paymentWorkflowDepositAccountOptions, id: \.id) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    .frame(width: 280)
                    .disabled(paymentWorkflowUseUndepositedFunds)

                    if !paymentWorkflowMessage.isEmpty {
                        Label(paymentWorkflowMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Check Workflow", systemImage: "checkbook")
                        .font(.headline)

                    Text("Control how Write Check starts by default and what extra detail prints on the check and stub.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Picker("Default coding mode", selection: Binding(
                        get: { checkWorkflowDefaultCodingMode },
                        set: { newValue in
                            checkWorkflowDefaultCodingMode = newValue
                            persistCheckWorkflowSettings()
                        }
                    )) {
                        ForEach(CheckCodingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .frame(width: 220)

                    Picker("Default bank account", selection: Binding(
                        get: { checkWorkflowDefaultBankAccountID },
                        set: { newValue in
                            checkWorkflowDefaultBankAccountID = newValue
                            persistCheckWorkflowSettings()
                        }
                    )) {
                        Text("Choose in Write Check").tag(Int64(0))
                        ForEach(checkWorkflowBankAccountOptions, id: \.id) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    .frame(width: 280)

                    Toggle("Show category / posting account on printed checks", isOn: Binding(
                        get: { checkWorkflowShowCategoryOnPrintedChecks },
                        set: { newValue in
                            checkWorkflowShowCategoryOnPrintedChecks = newValue
                            persistCheckWorkflowSettings()
                        }
                    ))

                    Toggle("Show memo on printed checks", isOn: Binding(
                        get: { checkWorkflowShowMemoOnPrintedChecks },
                        set: { newValue in
                            checkWorkflowShowMemoOnPrintedChecks = newValue
                            persistCheckWorkflowSettings()
                        }
                    ))

                    if !checkWorkflowMessage.isEmpty {
                        Label(checkWorkflowMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Memorized & Repeating Work", systemImage: "calendar.badge.clock")
                            .font(.headline)

                        Spacer()

                        Button("Refresh") {
                            loadMemorizedTemplates()
                        }
                        .buttonStyle(.renaissanceSecondary)
                    }

                    Text("Templates can carry review dates, but the app never creates checks, invoices, estimates, or sales receipts automatically. Dad still chooses and reviews the template before anything is saved.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    if memorizedTemplates.isEmpty {
                        Text("No memorized templates yet. Use Memorize from Estimate, Invoice, Sales Receipt, or Write Check.")
                            .foregroundStyle(AppTheme.ink3)
                            .font(.caption)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(memorizedTemplates.prefix(8)) { template in
                                HStack(spacing: 10) {
                                    Image(systemName: template.isDueSoon ? "exclamationmark.circle.fill" : "clock")
                                        .foregroundStyle(template.isDueSoon ? AppTheme.accent : AppTheme.ink3)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(template.type.title) - \(template.reminderStatusText)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }

                                    Spacer()

                                    if !template.lastUsedAt.isEmpty {
                                        Text("Used \(template.lastUsedAt)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink3)
                                    }
                                }
                                .padding(8)
                                .background(AppTheme.cardFill)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    if !memorizedTemplateMessage.isEmpty {
                        Label(memorizedTemplateMessage, systemImage: memorizedTemplateIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(memorizedTemplateIsError ? AppTheme.bad : AppTheme.ok)
                            .font(.subheadline)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Company Info section
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Company Information", systemImage: "building.2")
                        .font(.headline)
                    Text("Printed on invoices and statements.")
                        .foregroundStyle(AppTheme.ink3)
                        .font(.subheadline)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Company Name").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("Your Company Name", text: $companyName)
                        }
                        GridRow {
                            Text("Phone").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("(555) 555-5555", text: $companyPhone)
                        }
                        GridRow {
                            Text("Address").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("123 Main St", text: $companyAddress1)
                        }
                        GridRow {
                            Text("City / State / ZIP").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("City, CA 90000", text: $companyCityStateZip)
                        }
                        GridRow {
                            Text("Email").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("info@example.com", text: $companyEmail)
                        }
                        GridRow {
                            Text("License #").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("CA Lic# 123456", text: $companyLicense)
                        }
                        GridRow {
                            Text("Payment Terms").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("Net 30", text: $companyPaymentTerms)
                        }
                        GridRow {
                            Text("Invoice Footer").gridColumnAlignment(.trailing).foregroundStyle(AppTheme.ink3)
                            TextField("Thank you for your business.", text: $companyInvoiceFooter)
                        }
                    }

                    HStack {
                        Button("Save Company Info") { saveCompanyInfo() }
                            .buttonStyle(.renaissancePrimary)
                        if !companySaveMessage.isEmpty {
                            Text(companySaveMessage).foregroundStyle(AppTheme.ok).font(.subheadline)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        } // ScrollView
        .onAppear {
            loadLastBackupDate()
            loadOrderSheetInboxSettings()
            loadOrderSheetApprovalSettings()
            loadMailReviewSettings()
            loadDuplicateWarningSettings()
            loadPaymentWorkflowSettings()
            loadCheckWorkflowSettings()
            loadMemorizedTemplates()
            loadCompanyInfo()
        }
        .onDisappear {
            closeAppearanceColorPanel()
        }
    }

    private func exportBackup() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            backupMessage = "Cannot find Documents folder."
            backupIsError = true
            return
        }
        let backupDir = docs.appendingPathComponent("Renaissance Filed Backups", isDirectory: true)
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            backupMessage = "Cannot create backup folder: \(error.localizedDescription)"
            backupIsError = true
            return
        }
        let today = DateFormatter.isoDate.string(from: Date())
        let dest = backupDir.appendingPathComponent("ledger-\(today).sqlite")
        do {
            try model.db.exportBackup(to: dest)
            backupMessage = "Backup saved: ledger-\(today).sqlite"
            backupIsError = false
            UserDefaults.standard.set(today, forKey: "lastBackupDate")
            lastBackupDate = today
        } catch {
            backupMessage = "Backup failed: \(error.localizedDescription)"
            backupIsError = true
        }
    }

    private func loadLastBackupDate() {
        lastBackupDate = UserDefaults.standard.string(forKey: "lastBackupDate") ?? ""
    }

    private func loadOrderSheetInboxSettings() {
        let settings = model.orderSheetInboxSettings
        orderSheetInboxEnabled = settings.isEnabled
        orderSheetInboxFolderPath = settings.folderURL.path
        orderSheetDeleteAfterStage = settings.deleteAfterStage
    }

    private func loadOrderSheetApprovalSettings() {
        let settings = model.orderSheetApprovalSettings
        orderSheetTestingModeEnabled = settings.testingModeEnabled
        orderSheetRequireApprovalConfirmation = settings.requireConfirmation
    }

    private func loadMailReviewSettings() {
        let settings = model.mailReviewSettings
        mailReviewPreferredProvider = settings.preferredProvider
        mailReviewEnabled = settings.isEnabled
        mailReviewAutoRefresh = settings.autoRefreshOnLaunch
        mailReviewIncludeCustomerEmails = settings.includeCustomerEmails
        mailReviewVIPEmails = settings.vipSenderEmails
        mailReviewVIPDomains = settings.vipSenderDomains
        mailReviewScanLikelyJunk = settings.scanLikelyJunk
        mailReviewAutoTrashStrongJunk = settings.autoTrashStrongJunk
        mailReviewJunkEmails = settings.junkSenderEmails
        mailReviewJunkDomains = settings.junkSenderDomains
        mailReviewJunkKeywords = settings.junkSubjectKeywords
        mailReviewMaxOtherUnread = settings.maxOtherUnread
    }

    private func persistOrderSheetInboxSettings() {
        let settings = OrderSheetInboxSettings(
            isEnabled: orderSheetInboxEnabled,
            folderPath: orderSheetInboxFolderPath,
            scanIntervalSeconds: model.orderSheetInboxSettings.scanIntervalSeconds,
            deleteAfterStage: orderSheetDeleteAfterStage
        )
        do {
            try model.saveOrderSheetInboxSettings(settings)
            loadOrderSheetInboxSettings()
            orderSheetInboxMessage = orderSheetInboxEnabled
                ? "Phone order sheet inbox saved and watching is on."
                : "Phone order sheet inbox saved and watching is off."
            orderSheetInboxIsError = false
        } catch {
            orderSheetInboxMessage = "Could not save order sheet inbox: \(error.localizedDescription)"
            orderSheetInboxIsError = true
        }
    }

    private func chooseOrderSheetInboxFolder() {
        guard let folderURL = model.chooseOrderSheetInboxFolder() else { return }
        orderSheetInboxFolderPath = folderURL.path
        orderSheetInboxEnabled = true
        persistOrderSheetInboxSettings()
    }

    private func useRecommendedOrderSheetInbox() {
        do {
            let url = try model.useRecommendedOrderSheetInboxFolder()
            loadOrderSheetInboxSettings()
            orderSheetInboxMessage = "Watching \(url.path) for phone-shared order sheets."
            orderSheetInboxIsError = false
        } catch {
            orderSheetInboxMessage = "Could not prepare the recommended inbox: \(error.localizedDescription)"
            orderSheetInboxIsError = true
        }
    }

    private func persistOrderSheetApprovalSettings() {
        let settings = OrderSheetApprovalSettings(
            testingModeEnabled: orderSheetTestingModeEnabled,
            requireConfirmation: orderSheetRequireApprovalConfirmation
        )
        model.saveOrderSheetApprovalSettings(settings)
        loadOrderSheetApprovalSettings()
        orderSheetApprovalMessage = orderSheetTestingModeEnabled
            ? "Order sheet testing mode is on."
            : "Order sheet testing mode is off."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            orderSheetApprovalMessage = ""
        }
    }

    private func persistMailReviewSettings() {
        let settings = MailReviewSettings(
            preferredProvider: mailReviewPreferredProvider,
            isEnabled: mailReviewEnabled,
            autoRefreshOnLaunch: mailReviewAutoRefresh,
            includeCustomerEmails: mailReviewIncludeCustomerEmails,
            vipSenderEmails: mailReviewVIPEmails,
            vipSenderDomains: mailReviewVIPDomains,
            scanLikelyJunk: mailReviewScanLikelyJunk,
            autoTrashStrongJunk: mailReviewAutoTrashStrongJunk,
            junkSenderEmails: mailReviewJunkEmails,
            junkSenderDomains: mailReviewJunkDomains,
            junkSubjectKeywords: mailReviewJunkKeywords,
            maxOtherUnread: mailReviewMaxOtherUnread
        )
        model.saveMailReviewSettings(settings)
        loadMailReviewSettings()
        mailReviewMessage = mailReviewEnabled
            ? "Morning Mail Review saved."
            : "Morning Mail Review turned off."
        mailReviewIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            mailReviewMessage = ""
        }
    }

    private func loadDuplicateWarningSettings() {
        let settings = model.duplicateWarningSettings
        warnOnDuplicateEstimateNumbers = settings.warnOnDuplicateEstimateNumbers
        warnOnDuplicateInvoiceNumbers = settings.warnOnDuplicateInvoiceNumbers
    }

    private func persistDuplicateWarningSettings() {
        let settings = DuplicateWarningSettings(
            warnOnDuplicateEstimateNumbers: warnOnDuplicateEstimateNumbers,
            warnOnDuplicateInvoiceNumbers: warnOnDuplicateInvoiceNumbers
        )
        model.saveDuplicateWarningSettings(settings)
        loadDuplicateWarningSettings()
        duplicateWarningMessage = "Duplicate-number warnings saved."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            duplicateWarningMessage = ""
        }
    }

    private var paymentWorkflowMethodOptions: [String] {
        var options: [String] = []
        let candidates = model.paymentMethods.map(\.name) + [
            paymentWorkflowDefaultMethod,
            "Check",
            "Cash",
            "Credit Card",
            "Bank Transfer",
            "Zelle",
            "Other"
        ]

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !options.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                options.append(trimmed)
            }
        }

        return options
    }

    private var paymentWorkflowDepositAccountOptions: [AccountRow] {
        model.accounts.filter {
            $0.type == "asset" && $0.name.caseInsensitiveCompare("Undeposited Funds") != .orderedSame
        }
    }

    private var checkWorkflowBankAccountOptions: [AccountRow] {
        model.accounts.filter { $0.type == "asset" }
    }

    private func loadPaymentWorkflowSettings() {
        let settings = model.paymentWorkflowSettings
        paymentWorkflowAutoApplyPayments = settings.autoApplyPaymentsToOldestOpenInvoices
        paymentWorkflowAutoApplyCredits = settings.autoApplyAvailableCredits
        paymentWorkflowDefaultMethod = settings.defaultPaymentMethodName
        paymentWorkflowUseUndepositedFunds = settings.receivePaymentsIntoUndepositedFunds
        paymentWorkflowDefaultDepositAccountID = settings.defaultDepositAccountID
    }

    private func persistPaymentWorkflowSettings() {
        let settings = PaymentWorkflowSettings(
            autoApplyPaymentsToOldestOpenInvoices: paymentWorkflowAutoApplyPayments,
            autoApplyAvailableCredits: paymentWorkflowAutoApplyCredits,
            defaultPaymentMethodName: paymentWorkflowDefaultMethod,
            receivePaymentsIntoUndepositedFunds: paymentWorkflowUseUndepositedFunds,
            defaultDepositAccountID: paymentWorkflowDefaultDepositAccountID
        )
        model.savePaymentWorkflowSettings(settings)
        loadPaymentWorkflowSettings()
        paymentWorkflowMessage = "Payment workflow preferences saved."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            paymentWorkflowMessage = ""
        }
    }

    private func loadCheckWorkflowSettings() {
        let settings = model.checkWorkflowSettings
        checkWorkflowDefaultCodingMode = settings.defaultCodingMode
        checkWorkflowShowCategoryOnPrintedChecks = settings.showCategoryOnPrintedChecks
        checkWorkflowShowMemoOnPrintedChecks = settings.showMemoOnPrintedChecks
        checkWorkflowDefaultBankAccountID = settings.defaultBankAccountID
    }

    private func persistCheckWorkflowSettings() {
        let settings = CheckWorkflowSettings(
            defaultCodingMode: checkWorkflowDefaultCodingMode,
            showCategoryOnPrintedChecks: checkWorkflowShowCategoryOnPrintedChecks,
            showMemoOnPrintedChecks: checkWorkflowShowMemoOnPrintedChecks,
            defaultBankAccountID: checkWorkflowDefaultBankAccountID
        )
        model.saveCheckWorkflowSettings(settings)
        loadCheckWorkflowSettings()
        checkWorkflowMessage = "Check workflow preferences saved."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            checkWorkflowMessage = ""
        }
    }

    private func loadMemorizedTemplates() {
        do {
            memorizedTemplates = try model.db.fetchMemorizedTransactions()
            memorizedTemplateMessage = ""
            memorizedTemplateIsError = false
        } catch {
            memorizedTemplateMessage = "Could not load memorized templates: \(error.localizedDescription)"
            memorizedTemplateIsError = true
        }
    }

    private func loadCompanyInfo() {
        let info = model.companyInfo
        companyName = info.name
        companyPhone = info.phone
        companyAddress1 = info.address1
        companyCityStateZip = info.cityStateZip
        companyEmail = info.email
        companyLicense = info.licenseNumber
        companyPaymentTerms = info.paymentTerms
        companyInvoiceFooter = info.invoiceFooter
    }

    private func saveCompanyInfo() {
        let info = CompanyInfo(
            name: companyName,
            phone: companyPhone,
            address1: companyAddress1,
            cityStateZip: companyCityStateZip,
            email: companyEmail,
            licenseNumber: companyLicense,
            paymentTerms: companyPaymentTerms,
            invoiceFooter: companyInvoiceFooter
        )
        model.saveCompanyInfo(info)
        companySaveMessage = "Saved!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            companySaveMessage = ""
        }
    }

    private func appearanceColorControl(
        title: String,
        subtitle: String,
        color: Binding<Color>,
        target: AppearanceColorTarget
    ) -> some View {
        let isExpanded = Binding<Bool>(
            get: { expandedAppearanceColor == target },
            set: { shouldExpand in
                if shouldExpand {
                    closeAppearanceColorPanel()
                    expandedAppearanceColor = target
                } else if expandedAppearanceColor == target {
                    closeAppearanceColorPanel()
                }
            }
        )
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ColorPicker("Choose \(title)", selection: color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(maxWidth: 420, alignment: .leading)
                Text("Click the color well to open the macOS color wheel and choose any color.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                Button("Close Color Wheel") {
                    closeAppearanceColorPanel()
                }
                .buttonStyle(.renaissanceSecondary)
                .controlSize(.small)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.wrappedValue)
                    .frame(width: 36, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.bodyText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }

                Spacer()
            }
        }
        .padding(10)
        .background(AppTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func closeAppearanceColorPanel() {
        AppAppearanceSettings.closeSharedColorPanel()
        expandedAppearanceColor = nil
    }
}
