import SwiftUI

enum StartupWorkspaceWindowID: String, CaseIterable, Codable, Hashable, Identifiable {
    case centerPanel
    case reportCenter
    case reportWindow
    case customerDetail

    var id: String { rawValue }
}

enum StartupCenterMode: String, CaseIterable, Codable, Identifiable {
    case customers = "Customer Center"
    case register = "Register"

    var id: String { rawValue }
}

enum StartupRegisterMode: String, CaseIterable, Codable, Identifiable {
    case checkRegister = "Check Register"
    case importedHistory = "Imported History"

    var id: String { rawValue }
}

struct StartupWorkspaceWindowLayout: Codable, Equatable {
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double
    var isVisible: Bool
    var isCollapsed: Bool

    var origin: CGPoint {
        get { CGPoint(x: CGFloat(originX), y: CGFloat(originY)) }
        set {
            originX = Double(newValue.x)
            originY = Double(newValue.y)
        }
    }

    var panelWidth: CGFloat { CGFloat(width) }
    var panelHeight: CGFloat { CGFloat(height) }
    var renderedHeight: CGFloat { isCollapsed ? 46 : CGFloat(height) }

    func clamped(to bounds: CGSize) -> StartupWorkspaceWindowLayout {
        var layout = self
        let safeWidth = min(max(panelWidth, 260), max(bounds.width - 32, 260))
        let safeHeight = min(max(panelHeight, 160), max(bounds.height - 32, 160))
        let safeX = min(max(CGFloat(originX), 16), max(16, bounds.width - safeWidth - 16))
        let safeY = min(max(CGFloat(originY), 16), max(16, bounds.height - (isCollapsed ? 46 : safeHeight) - 16))
        layout.width = Double(safeWidth)
        layout.height = Double(safeHeight)
        layout.originX = Double(safeX)
        layout.originY = Double(safeY)
        return layout
    }
}

private struct StartupWorkspaceSnapshot: Codable {
    var layouts: [String: StartupWorkspaceWindowLayout]
    var zOrder: [StartupWorkspaceWindowID]
    var centerMode: StartupCenterMode
    var isCenterTrayExpanded: Bool
    var selectedCustomerID: Int64?
    var registerMode: StartupRegisterMode
    var selectedBankAccountID: Int64
    var activeReportTab: ReportTab
    var requestedHistoricalYear: Int?
}

@MainActor
final class StartupWorkspaceStore: ObservableObject {
    private static let storageKey = "renaissanceLedger.startupWorkspace.v1"

    @Published private(set) var layouts: [StartupWorkspaceWindowID: StartupWorkspaceWindowLayout] = [:]
    @Published private(set) var zOrder: [StartupWorkspaceWindowID] = [
        .centerPanel,
        .reportWindow,
        .customerDetail,
        .reportCenter,
    ]
    @Published var centerMode: StartupCenterMode = .customers {
        didSet { persist() }
    }
    @Published var isCenterTrayExpanded = true {
        didSet { persist() }
    }
    @Published var selectedCustomerID: Int64? {
        didSet { persist() }
    }
    @Published var registerMode: StartupRegisterMode = .checkRegister {
        didSet { persist() }
    }
    @Published var selectedBankAccountID: Int64 = 0 {
        didSet { persist() }
    }
    @Published var activeReportTab: ReportTab = .historicalPL {
        didSet { persist() }
    }
    @Published var requestedHistoricalYear: Int? {
        didSet { persist() }
    }
    @Published var customerSearch = "" {
        didSet {
            if !customerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCenterTrayExpanded {
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
            if !registerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCenterTrayExpanded {
                isCenterTrayExpanded = true
            }
        }
    }

    private var hasPreparedInitialLayout = false
    private var isRestoring = false

    init() {
        restore()
    }

    func ensureWorkspaceLayout(in bounds: CGSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        if !hasPreparedInitialLayout {
            if layouts.isEmpty {
                layouts = Self.defaultLayouts(in: bounds)
            } else {
                for id in StartupWorkspaceWindowID.allCases where layouts[id] == nil {
                    layouts[id] = Self.defaultLayout(for: id, in: bounds)
                }
            }
            hasPreparedInitialLayout = true
        }

        clampAll(in: bounds)
        persist()
    }

    func layout(for id: StartupWorkspaceWindowID) -> StartupWorkspaceWindowLayout {
        layouts[id] ?? Self.defaultLayout(for: id, in: CGSize(width: 1400, height: 900))
    }

    func zIndex(for id: StartupWorkspaceWindowID) -> Double {
        Double(zOrder.firstIndex(of: id) ?? 0)
    }

    func isWindowVisible(_ id: StartupWorkspaceWindowID) -> Bool {
        layout(for: id).isVisible
    }

    func closeWindow(_ id: StartupWorkspaceWindowID) {
        updateLayout(id) { $0.isVisible = false }
    }

    func toggleCollapsed(_ id: StartupWorkspaceWindowID) {
        focus(id)
        updateLayout(id) { $0.isCollapsed.toggle() }
    }

    func restoreWindow(_ id: StartupWorkspaceWindowID, expand: Bool = false) {
        focus(id)
        updateLayout(id) { layout in
            layout.isVisible = true
            if expand {
                layout.isCollapsed = false
            }
        }
    }

    func moveWindow(_ id: StartupWorkspaceWindowID, to origin: CGPoint, in bounds: CGSize) {
        var layout = self.layout(for: id)
        layout.origin = origin
        layouts[id] = layout.clamped(to: bounds)
        persist()
    }

    func focus(_ id: StartupWorkspaceWindowID) {
        zOrder.removeAll { $0 == id }
        zOrder.append(id)
        persist()
    }

    func openCustomerWorkspace(customerID: Int64) {
        selectedCustomerID = customerID
        centerMode = .customers
        isCenterTrayExpanded = true
        restoreWindow(.customerDetail, expand: true)
    }

    func openReport(_ tab: ReportTab, requestedHistoricalYear: Int? = nil) {
        activeReportTab = tab
        self.requestedHistoricalYear = requestedHistoricalYear
        restoreWindow(.reportWindow, expand: true)
    }

    func clearCustomerSelection() {
        selectedCustomerID = nil
        closeWindow(.customerDetail)
    }

    func resetFilters() {
        customerSearch = ""
        customerSortMode = .alphabeticalAsc
        customerInitialFilter = "All"
        customerDateFilterMode = .allTime
        customerFromDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        customerToDate = Date()
    }

    private func updateLayout(_ id: StartupWorkspaceWindowID, mutate: (inout StartupWorkspaceWindowLayout) -> Void) {
        var layout = self.layout(for: id)
        mutate(&layout)
        layouts[id] = layout
        persist()
    }

    private func clampAll(in bounds: CGSize) {
        layouts = layouts.mapValues { $0.clamped(to: bounds) }
    }

    private func persist() {
        guard hasPreparedInitialLayout, !isRestoring else { return }
        let snapshot = StartupWorkspaceSnapshot(
            layouts: layouts.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key.rawValue] = entry.value
            },
            zOrder: zOrder,
            centerMode: centerMode,
            isCenterTrayExpanded: isCenterTrayExpanded,
            selectedCustomerID: selectedCustomerID,
            registerMode: registerMode,
            selectedBankAccountID: selectedBankAccountID,
            activeReportTab: activeReportTab,
            requestedHistoricalYear: requestedHistoricalYear
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(StartupWorkspaceSnapshot.self, from: data)
        else { return }

        isRestoring = true
        layouts = snapshot.layouts.reduce(into: [:]) { partialResult, entry in
            guard let id = StartupWorkspaceWindowID(rawValue: entry.key) else { return }
            partialResult[id] = entry.value
        }
        zOrder = snapshot.zOrder.isEmpty ? zOrder : snapshot.zOrder
        centerMode = snapshot.centerMode
        isCenterTrayExpanded = snapshot.isCenterTrayExpanded
        selectedCustomerID = snapshot.selectedCustomerID
        registerMode = snapshot.registerMode
        selectedBankAccountID = snapshot.selectedBankAccountID
        activeReportTab = snapshot.activeReportTab
        requestedHistoricalYear = snapshot.requestedHistoricalYear
        isRestoring = false
    }

    private static func defaultLayouts(in bounds: CGSize) -> [StartupWorkspaceWindowID: StartupWorkspaceWindowLayout] {
        Dictionary(uniqueKeysWithValues: StartupWorkspaceWindowID.allCases.map { id in
            (id, defaultLayout(for: id, in: bounds))
        })
    }

    private static func defaultLayout(for id: StartupWorkspaceWindowID, in bounds: CGSize) -> StartupWorkspaceWindowLayout {
        switch id {
        case .centerPanel:
            let width = min(max(bounds.width - 360, 760), 980)
            let height = min(max(bounds.height * 0.34, 250), 360)
            return StartupWorkspaceWindowLayout(
                originX: 20,
                originY: 20,
                width: Double(width),
                height: Double(height),
                isVisible: true,
                isCollapsed: false
            )
        case .reportCenter:
            let width = min(max(bounds.width * 0.22, 250), 290)
            let height = min(max(bounds.height * 0.72, 420), 560)
            return StartupWorkspaceWindowLayout(
                originX: Double(max(bounds.width - width - 20, 20)),
                originY: 20,
                width: Double(width),
                height: Double(height),
                isVisible: true,
                isCollapsed: false
            )
        case .reportWindow:
            let width = min(max(bounds.width * 0.40, 560), 700)
            let height = min(max(bounds.height * 0.58, 430), 580)
            return StartupWorkspaceWindowLayout(
                originX: Double(max(bounds.width - width - 320, 160)),
                originY: 120,
                width: Double(width),
                height: Double(height),
                isVisible: true,
                isCollapsed: false
            )
        case .customerDetail:
            let width = min(max(bounds.width * 0.62, 780), 940)
            let height = min(max(bounds.height * 0.66, 560), 720)
            return StartupWorkspaceWindowLayout(
                originX: 80,
                originY: 180,
                width: Double(width),
                height: Double(height),
                isVisible: false,
                isCollapsed: false
            )
        }
    }
}

struct StartupWorkspaceWindow<Content: View>: View {
    let title: String
    let subtitle: String?
    let layout: StartupWorkspaceWindowLayout
    let zIndex: Double
    let onFocus: () -> Void
    let onClose: () -> Void
    let onToggleCollapse: () -> Void
    let onMove: (CGPoint) -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragStartOrigin: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !layout.isCollapsed {
                Divider()
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: layout.panelWidth, height: layout.renderedHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.14), radius: 24, y: 14)
        .offset(x: CGFloat(layout.originX), y: CGFloat(layout.originY))
        .zIndex(zIndex)
        .onTapGesture { onFocus() }
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: layout.isCollapsed)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                windowControlButton(color: Color(red: 0.96, green: 0.40, blue: 0.34), symbol: "xmark", action: onClose)
                windowControlButton(
                    color: Color(red: 0.95, green: 0.76, blue: 0.24),
                    symbol: layout.isCollapsed ? "arrow.down.forward.and.arrow.up.backward" : "arrow.up.left.and.arrow.down.right",
                    action: onToggleCollapse
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.bodyText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [AppTheme.surface.opacity(0.95), AppTheme.panel.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartOrigin == nil {
                        dragStartOrigin = layout.origin
                        onFocus()
                    }
                    guard let dragStartOrigin else { return }
                    onMove(CGPoint(
                        x: dragStartOrigin.x + value.translation.width,
                        y: dragStartOrigin.y + value.translation.height
                    ))
                }
                .onEnded { _ in
                    dragStartOrigin = nil
                }
        )
    }

    private func windowControlButton(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 13, height: 13)
                Image(systemName: symbol)
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}
