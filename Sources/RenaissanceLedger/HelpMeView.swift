import SwiftUI

struct HelpMeTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let keywords: [String]
    let illustration: HelpIllustration
    let sections: [HelpMeSection]

    var searchableText: String {
        ([title, subtitle] + keywords + sections.flatMap { [$0.title] + $0.points }).joined(separator: " ").lowercased()
    }
}

struct HelpMeSection: Identifiable, Hashable {
    let id: String
    let title: String
    let points: [String]
}

enum HelpIllustration: Hashable {
    case launchDesk
    case navigation
    case customerRegister
    case reportCenter
    case customerWork
    case estimate
    case invoice
    case checkExpense
    case documents
    case checkStack
    case emailPrint
    case settings
}

enum HelpMeLibrary {
    static let topics: [HelpMeTopic] = [
        HelpMeTopic(
            id: "start",
            title: "Start Here",
            subtitle: "What opens when the app launches",
            symbol: "macwindow.on.rectangle",
            keywords: ["launch", "startup", "desktop", "windows", "home", "where do I start"],
            illustration: .launchDesk,
            sections: [
                HelpMeSection(id: "start-open", title: "What you see first", points: [
                    "The app opens like a work desk, not one giant screen.",
                    "Customer / Register is the main work window for customers and bank activity.",
                    "Report Center stays nearby so reports are always one click away.",
                    "Navigation is the small hotbar that opens estimates, invoices, expenses, documents, settings, and help."
                ]),
                HelpMeSection(id: "start-window", title: "If a window is closed", points: [
                    "Click Navigation, then Customer / Register or Report Center to reopen the startup windows.",
                    "Windows can be minimized or closed and will reopen in their saved position.",
                    "If you are unsure where you are, reopen Navigation and use Help Me."
                ])
            ]
        ),
        HelpMeTopic(
            id: "navigation",
            title: "Navigation",
            subtitle: "The small hotbar for moving around the app",
            symbol: "square.grid.3x3",
            keywords: ["hotbar", "tabs", "mail", "payees", "lists", "sync", "import", "settings"],
            illustration: .navigation,
            sections: [
                HelpMeSection(id: "nav-buttons", title: "Core buttons", points: [
                    "Mail opens email review and order-sheet email tools.",
                    "Estimates opens quotes, proposals, and estimate-from-existing work.",
                    "Invoices opens billing, payment, print, and email tools.",
                    "Expenses opens money-out work, checks, and non-check expenses.",
                    "Documents opens archived PDFs and migrated QuickBooks files."
                ]),
                HelpMeSection(id: "nav-shortcuts", title: "Window shortcuts", points: [
                    "Customer / Register reopens the main customer/bank window.",
                    "Report Center reopens the compact report picker.",
                    "Help Me opens this searchable instruction window."
                ])
            ]
        ),
        HelpMeTopic(
            id: "customer-register",
            title: "Customer / Register",
            subtitle: "Find customers or review bank/register activity",
            symbol: "rectangle.3.group",
            keywords: ["customer center", "register", "search", "filter", "bank account", "reset filters"],
            illustration: .customerRegister,
            sections: [
                HelpMeSection(id: "customer-controls", title: "Customer controls", points: [
                    "Customer Center shows customer records.",
                    "Search finds customers by name, company, contact, or phone.",
                    "Order sorts the list. Initial filters by first letter. Date narrows by date range.",
                    "Reset Filters clears search and filter choices.",
                    "The View triangle expands or collapses the visible customer list."
                ]),
                HelpMeSection(id: "register-controls", title: "Register controls", points: [
                    "Register changes the same window into bank activity mode.",
                    "Choose Check Register or Imported History.",
                    "Bank Account narrows the activity to one account.",
                    "Search register finds payees, memo text, account names, and check numbers.",
                    "Click a saved check row to place that check onto the Check Desk."
                ])
            ]
        ),
        HelpMeTopic(
            id: "report-center",
            title: "Report Center",
            subtitle: "Pick reports, expand previews, or pop out a report window",
            symbol: "chart.bar.doc.horizontal",
            keywords: ["reports", "profit loss", "trial balance", "cash flow", "aging", "1099", "statement"],
            illustration: .reportCenter,
            sections: [
                HelpMeSection(id: "report-list", title: "Report list", points: [
                    "Click a report name to load it.",
                    "Expand opens a reading area inside the Report Center.",
                    "Pop Out opens the selected report in its own larger window.",
                    "Show Customer Center brings the main customer/register window back."
                ]),
                HelpMeSection(id: "report-types", title: "Common reports", points: [
                    "Historical QB Profit and Loss, Trial Balance, Cash Flows, and Sales By Item compare preserved QuickBooks history.",
                    "Operational Cash Summary, A/R Aging, Payee Spend, 1099 Summary, and Customer Statements help daily business review.",
                    "Some reports include Year or Run Report controls when the report depends on a selected year."
                ])
            ]
        ),
        HelpMeTopic(
            id: "add-customer",
            title: "Add Customer / Customer Work",
            subtitle: "Create customers and connect their estimates, invoices, jobs, and statements",
            symbol: "person.crop.circle.badge.plus",
            keywords: ["add customer", "customer detail", "job", "statement", "workspace"],
            illustration: .customerWork,
            sections: [
                HelpMeSection(id: "add-customer-main", title: "Adding a customer", points: [
                    "Click + Add Customer in the Customer / Register window.",
                    "Fill in the customer name and contact details.",
                    "Save only when the customer is real and ready to keep.",
                    "After saving, the customer can be found from Customer Center search."
                ]),
                HelpMeSection(id: "customer-related", title: "Customer-related work", points: [
                    "Selecting a customer can open their workspace.",
                    "Customer context can flow into estimates, invoices, reports, and statements.",
                    "Use customer statements from Report Center when you need a printable customer account history."
                ])
            ]
        ),
        HelpMeTopic(
            id: "estimates",
            title: "Estimates",
            subtitle: "Quotes, change orders, templates, and invoice-from-estimate",
            symbol: "doc.plaintext",
            keywords: ["estimate", "quote", "proposal", "new from", "change order", "duplicate", "progress invoice", "template"],
            illustration: .estimate,
            sections: [
                HelpMeSection(id: "estimate-list", title: "Estimate list", points: [
                    "Search filters existing estimates.",
                    "+ New Estimate starts a blank estimate.",
                    "Import From Mac and Scan Phone Inbox help bring in order sheets.",
                    "Review Pending opens scanned order sheets waiting for approval."
                ]),
                HelpMeSection(id: "estimate-form", title: "Estimate form controls", points: [
                    "Customer and Job tie the estimate to the correct person and job.",
                    "Estimate number, date, valid-until date, and status identify the quote.",
                    "Line items hold description, quantity, rate, and amount.",
                    "+ Add Line adds another work/material line.",
                    "Memo stores notes for the estimate.",
                    "Use Template and Memorize reuse common layouts."
                ]),
                HelpMeSection(id: "estimate-existing", title: "Existing estimate actions", points: [
                    "Edit reopens the estimate.",
                    "New From creates a related estimate/change order from an existing estimate.",
                    "Duplicate makes a copied estimate, but it is not the same as New From.",
                    "Invoice starts an invoice from selected remaining work, percent, fixed amount, or selected lines.",
                    "Print and Email QB File create customer-facing or QuickBooks-compatible output."
                ])
            ]
        ),
        HelpMeTopic(
            id: "invoices",
            title: "Invoices",
            subtitle: "Billing, payment records, print/PDF, and email output",
            symbol: "doc.text",
            keywords: ["invoice", "billing", "payment", "receive payment", "void", "print pdf", "email qb file"],
            illustration: .invoice,
            sections: [
                HelpMeSection(id: "invoice-list", title: "Invoice list", points: [
                    "Search filters invoices.",
                    "+ New Invoice starts a blank invoice.",
                    "Invoices created from estimates keep their source-estimate progress link."
                ]),
                HelpMeSection(id: "invoice-form", title: "Invoice form controls", points: [
                    "Customer and Job tie billing to the right account.",
                    "Invoice number, date, due date, and status identify the bill.",
                    "Line items hold description, quantity, rate, and amount.",
                    "Use Template and Memorize reuse repeat invoice formats.",
                    "Save and Print saves first, then opens printing."
                ]),
                HelpMeSection(id: "invoice-actions", title: "Existing invoice actions", points: [
                    "Edit Invoice reopens the invoice form.",
                    "Receive Payment records payment date, method, reference/check number, and memo.",
                    "Print / Save PDF creates a printable invoice copy.",
                    "Email QB File opens Mail with QuickBooks-compatible output.",
                    "Void Invoice keeps a traceable record instead of silently deleting billing history."
                ])
            ]
        ),
        HelpMeTopic(
            id: "checks-expenses",
            title: "Checks / Expenses",
            subtitle: "Write checks, record expenses, code categories or item lines",
            symbol: "checkbook",
            keywords: ["check", "expense", "payee", "category", "items", "bank account", "save print", "memorize"],
            illustration: .checkExpense,
            sections: [
                HelpMeSection(id: "expense-list", title: "Expense list", points: [
                    "Search finds vendor/payee, memo, amount, account, or check number.",
                    "Write Check opens the check-style workflow.",
                    "+ Add Expense records non-check expenses."
                ]),
                HelpMeSection(id: "check-form", title: "Write Check controls", points: [
                    "Payee searches existing vendors/payees or accepts a typed payee.",
                    "Date, bank account, check number, amount, and memo are the check details.",
                    "Category posts the check to one expense account.",
                    "Items mode allows itemized check lines.",
                    "Use Template and Memorize reuse repeat checks.",
                    "Email QB File, Save, Save and Print, and Delete are final actions."
                ]),
                HelpMeSection(id: "check-save", title: "Saving rule", points: [
                    "Use Save when the check is real and should be kept.",
                    "Use Save and Print when issuing a real paper check.",
                    "Cancel or close the window if you were only testing."
                ])
            ]
        ),
        HelpMeTopic(
            id: "documents",
            title: "Documents",
            subtitle: "Archived files, readable PDFs, email and sharing",
            symbol: "folder",
            keywords: ["documents", "pdf", "paper", "open", "email", "share", "mirrored", "distorted", "normalized"],
            illustration: .documents,
            sections: [
                HelpMeSection(id: "doc-list", title: "Document controls", points: [
                    "Search documents by typing part of a file name, path, or category.",
                    "Apply runs the search. Reset clears the search.",
                    "Rows show category, file path/name, and size.",
                    "Open opens the archived file using the Mac.",
                    "Email opens Mail with the document attached.",
                    "Share uses the Mac sharing sheet when available."
                ]),
                HelpMeSection(id: "doc-quality", title: "Readable document rule", points: [
                    "Imported PDFs are normalized when needed so old QuickBooks exports do not stay mirrored or distorted.",
                    "If a document looks wrong, do not print it yet. Reopen it from Documents so the repaired readable copy is used.",
                    "Current app note: documents do not yet have the same Stack List / Previous / Next controls that Check Desk has."
                ])
            ]
        ),
        HelpMeTopic(
            id: "check-desk",
            title: "Check Desk / Check Stack",
            subtitle: "A movable stack of realistic checks on the desktop",
            symbol: "rectangle.stack",
            keywords: ["check desk", "stack", "previous", "next", "remove", "stack list", "standard view"],
            illustration: .checkStack,
            sections: [
                HelpMeSection(id: "stack-controls", title: "Stack controls", points: [
                    "Previous and Next cycle through checks on the desk.",
                    "Stack List opens the list of checks currently on the desk.",
                    "Checking more than one item in Stack List lines checks up side-by-side.",
                    "Standard View returns to one active check.",
                    "Remove takes the active check off the desk view."
                ]),
                HelpMeSection(id: "stack-safety", title: "Important safety note", points: [
                    "Remove from Check Desk does not delete saved ledger history.",
                    "Open Full Editor returns to the full check/expense editor when a check needs changes.",
                    "Saved ledger changes only happen from the editor when Save is used."
                ])
            ]
        ),
        HelpMeTopic(
            id: "email-print",
            title: "Email, Print, and Closeout",
            subtitle: "Finish work cleanly without stray drafts or confusing windows",
            symbol: "printer",
            keywords: ["email", "print", "pdf", "mail", "draft", "close", "save"],
            illustration: .emailPrint,
            sections: [
                HelpMeSection(id: "before-save", title: "Before saving", points: [
                    "Confirm customer or payee is correct.",
                    "Confirm date and document number are correct.",
                    "Confirm line amounts and totals look right.",
                    "Confirm category, job, or account is selected."
                ]),
                HelpMeSection(id: "before-print-email", title: "Before print or email", points: [
                    "Print only after reviewing the preview/report.",
                    "Email opens Mail so the message and attachment can be reviewed before sending.",
                    "Delete test email drafts if you were only testing.",
                    "Use Cancel or close if something feels wrong."
                ])
            ]
        ),
        HelpMeTopic(
            id: "settings",
            title: "Settings / Colors",
            subtitle: "Font size, palette controls, backups, and workflow preferences",
            symbol: "gearshape",
            keywords: ["settings", "colors", "font size", "backup", "palette", "theme"],
            illustration: .settings,
            sections: [
                HelpMeSection(id: "settings-visual", title: "Visual settings", points: [
                    "The font-size slider scales app text for readability.",
                    "Palette controls can change primary, accent, and text colors.",
                    "Only one color editor should be open at a time; click away or close it before testing work screens."
                ]),
                HelpMeSection(id: "settings-safety", title: "Business safety settings", points: [
                    "Backups protect the ledger file.",
                    "Workflow preferences control defaults such as check behavior and warnings.",
                    "Use Reset when a setting test should go back to the default palette."
                ])
            ]
        )
    ]

    static func search(_ query: String) -> [HelpMeTopic] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return topics }
        return topics.filter { topic in
            words.allSatisfy { topic.searchableText.contains($0) }
        }
    }
}

struct HelpMeWindowView: View {
    @State private var searchText = ""
    @State private var selectedTopicID = HelpMeLibrary.topics.first?.id ?? "start"

    private var searchResults: [HelpMeTopic] {
        HelpMeLibrary.search(searchText)
    }

    private var selectedTopic: HelpMeTopic {
        HelpMeLibrary.topics.first { $0.id == selectedTopicID } ?? HelpMeLibrary.topics[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 275)
                .background(AppTheme.canvas)

            Divider()

            topicDetail(selectedTopic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(AppTheme.surface)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Help Me")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.accent)
                Text("Search instructions or pick a topic.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }

            TextField("Search help, like invoice or check", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("help.search")

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Table of Contents" : "Search Results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink3)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(searchResults) { topic in
                        Button {
                            selectedTopicID = topic.id
                        } label: {
                            helpTopicRow(topic, selected: topic.id == selectedTopicID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("help.topic.\(topic.id)")
                    }

                    if searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(AppTheme.ink3)
                            Text("No help topics matched.")
                                .font(.headline)
                            Text("Try a simpler word like estimate, invoice, check, report, document, or print.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
    }

    private func helpTopicRow(_ topic: HelpMeTopic, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: topic.symbol)
                .frame(width: 22)
                .foregroundStyle(selected ? AppTheme.accent : AppTheme.ink3)

            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.bodyText)
                    .lineLimit(1)
                Text(topic.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? AppTheme.panel : AppTheme.cardFillSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? AppTheme.accent.opacity(0.55) : AppTheme.hairline, lineWidth: 1)
        )
    }

    private func topicDetail(_ topic: HelpMeTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: topic.symbol)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title)
                            .font(.largeTitle.bold())
                        Text(topic.subtitle)
                            .font(.title3)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }

                HelpIllustrationView(kind: topic.illustration)
                    .frame(maxWidth: .infinity)

                ForEach(topic.sections) { section in
                    helpSection(section)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func helpSection(_ section: HelpMeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.accent)

            ForEach(section.points, id: \.self) { point in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent2)
                        .padding(.top, 3)
                    Text(point)
                        .font(.body)
                        .foregroundStyle(AppTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardFill)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct HelpIllustrationView: View {
    let kind: HelpIllustration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visual guide")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink3)

            switch kind {
            case .launchDesk:
                helpFlow(["Navigation", "Customer / Register", "Report Center", "Work Windows"])
            case .navigation:
                helpGrid(["Mail", "Estimates", "Invoices", "Receipts", "Expenses", "Bills", "Payees", "Lists", "Documents", "Sync", "Import", "Settings", "Help Me"])
            case .customerRegister:
                helpFlow(["Customer Center", "Search / Filters", "View List", "Customer Workspace"])
                helpFlow(["Register", "Bank Account", "Search Register", "Check Desk"])
            case .reportCenter:
                helpFlow(["Report Center", "Pick Report", "Expand Preview", "Pop Out Window"])
            case .customerWork:
                helpFlow(["+ Add Customer", "Customer Record", "Jobs", "Estimates / Invoices / Statements"])
            case .estimate:
                helpFlow(["Customer + Job", "Estimate Lines", "New From / Invoice", "Print or Email"])
            case .invoice:
                helpFlow(["Customer + Job", "Invoice Lines", "Receive Payment", "Print / Save PDF"])
            case .checkExpense:
                helpFlow(["Payee", "Check Details", "Category or Items", "Save / Print"])
            case .documents:
                helpFlow(["Search Documents", "Open", "Email", "Share"])
            case .checkStack:
                helpFlow(["Check Desk", "Previous / Next", "Stack List", "Standard View / Remove"])
            case .emailPrint:
                helpFlow(["Review", "Save", "Print or Email", "Close Drafts"])
            case .settings:
                helpFlow(["Font Size", "Color Palette", "Backups", "Workflow Defaults"])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel.opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func helpFlow(_ labels: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                helpNode(label)
                if index < labels.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpGrid(_ labels: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(labels, id: \.self) { label in
                helpNode(label)
            }
        }
    }

    private func helpNode(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.bodyText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 82, minHeight: 38)
            .background(AppTheme.cardFill)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
