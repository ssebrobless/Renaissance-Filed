import AppKit
import SwiftUI

final class AppAppearanceSettings: ObservableObject {
    static let shared = AppAppearanceSettings()

    private enum Keys {
        static let fontScale = "appearance.fontScale"
        static let primary = "appearance.primary"
        static let accent1 = "appearance.accent1"
        static let accent2 = "appearance.accent2"
        static let text1 = "appearance.text1"
        static let text2 = "appearance.text2"
    }

    @Published var fontScale: Double {
        didSet { save(fontScale, forKey: Keys.fontScale) }
    }
    @Published var primary: Color {
        didSet { save(primary, forKey: Keys.primary) }
    }
    @Published var accent1: Color {
        didSet { save(accent1, forKey: Keys.accent1) }
    }
    @Published var accent2: Color {
        didSet { save(accent2, forKey: Keys.accent2) }
    }
    @Published var text1: Color {
        didSet { save(text1, forKey: Keys.text1) }
    }
    @Published var text2: Color {
        didSet { save(text2, forKey: Keys.text2) }
    }

    var minimumFontSize: CGFloat {
        max(12, 12 * fontScale)
    }

    var bodyFontSize: CGFloat {
        max(14, 14 * fontScale)
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch fontScale {
        case ..<1.08:
            return .large
        case ..<1.18:
            return .xLarge
        case ..<1.32:
            return .xxLarge
        case ..<1.46:
            return .xxxLarge
        default:
            return .accessibility1
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        fontScale = defaults.object(forKey: Keys.fontScale) as? Double ?? 1.0
        primary = Self.loadColor(forKey: Keys.primary, fallback: Self.defaultPrimary)
        accent1 = Self.loadColor(forKey: Keys.accent1, fallback: Self.defaultAccent1)
        accent2 = Self.loadColor(forKey: Keys.accent2, fallback: Self.defaultAccent2)
        text1 = Self.loadColor(forKey: Keys.text1, fallback: Self.defaultText1)
        text2 = Self.loadColor(forKey: Keys.text2, fallback: Self.defaultText2)
    }

    func resetToDefaults() {
        fontScale = 1.0
        primary = Self.defaultPrimary
        accent1 = Self.defaultAccent1
        accent2 = Self.defaultAccent2
        text1 = Self.defaultText1
        text2 = Self.defaultText2
    }

    static func closeSharedColorPanel() {
        let panel = NSColorPanel.shared
        panel.close()
        panel.orderOut(nil)
    }

    private func save(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        objectWillChange.send()
    }

    private func save(_ color: Color, forKey key: String) {
        UserDefaults.standard.set(Self.hexString(for: color), forKey: key)
        objectWillChange.send()
    }

    private static func loadColor(forKey key: String, fallback: Color) -> Color {
        guard let hex = UserDefaults.standard.string(forKey: key) else { return fallback }
        return Color(hex: hex) ?? fallback
    }

    private static func hexString(for color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static let defaultPrimary = Color(red: 0.310, green: 0.245, blue: 0.190)
    static let defaultAccent1 = Color(red: 1.000, green: 0.780, blue: 0.360)
    static let defaultAccent2 = Color(red: 1.000, green: 0.860, blue: 0.520)
    static let defaultText1 = Color(red: 0.985, green: 0.925, blue: 0.780)
    static let defaultText2 = Color(red: 0.780, green: 0.660, blue: 0.480)
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

enum AppTheme {
    static var appearance: AppAppearanceSettings { AppAppearanceSettings.shared }

    static var canvas: Color { appearance.primary.mix(with: .black, amount: 0.18) }
    static var surface: Color { appearance.primary }
    static var panel: Color { appearance.primary.mix(with: appearance.accent1, amount: 0.10) }
    static var border: Color { appearance.accent1.opacity(0.70) }
    static var accent: Color { appearance.accent1 }
    static var accent2: Color { appearance.accent2 }
    static var ink: Color { appearance.text1 }
    static var ink2: Color { appearance.text1.opacity(0.82) }
    static var ink3: Color { appearance.text2 }
    static let ok = Color(red: 0.365, green: 0.706, blue: 0.443)
    static var warn: Color { accent }
    static let bad = Color(red: 0.875, green: 0.373, blue: 0.290)
    static let paper = Color(red: 0.984, green: 0.957, blue: 0.902)
    static var cardFill: Color { panel.opacity(0.82) }
    static var cardFillSoft: Color { surface.opacity(0.72) }
    static var hairline: Color { accent.opacity(0.20) }
    static var buttonFill: Color { panel.mix(with: accent, amount: 0.12) }
    static var buttonFillPressed: Color { panel.mix(with: accent, amount: 0.22) }
    static var buttonPrimaryFill: Color { accent }
    static var buttonPrimaryPressed: Color { accent2 }
    static var buttonPrimaryText: Color { canvas }

    // Semantic aliases
    static var primary: Color { accent2 }
    static var onPrimary: Color { canvas }
    static var secondaryText: Color { ink3 }
    static var bodyText: Color { ink }
}

private extension Color {
    func mix(with other: Color, amount: Double) -> Color {
        let left = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        let right = NSColor(other).usingColorSpace(.deviceRGB) ?? .black
        let clamped = min(max(amount, 0), 1)
        return Color(
            red: left.redComponent * (1 - clamped) + right.redComponent * clamped,
            green: left.greenComponent * (1 - clamped) + right.greenComponent * clamped,
            blue: left.blueComponent * (1 - clamped) + right.blueComponent * clamped
        )
    }
}

enum RenaissanceButtonRole {
    case primary
    case secondary
}

struct RenaissanceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var role: RenaissanceButtonRole = .secondary

    func makeBody(configuration: Configuration) -> some View {
        let isPrimary = role == .primary
        configuration.label
            .font(buttonFont.weight(isPrimary ? .semibold : .medium))
            .foregroundStyle(isPrimary ? AppTheme.buttonPrimaryText : AppTheme.bodyText)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPrimary: isPrimary, isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isPrimary ? AppTheme.accent2.opacity(0.60) : AppTheme.accent.opacity(0.42), lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.48)
            .shadow(color: .black.opacity(isPrimary ? 0.26 : 0.18), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 0 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPrimary: Bool, isPressed: Bool) -> Color {
        if isPrimary {
            return isPressed ? AppTheme.buttonPrimaryPressed : AppTheme.buttonPrimaryFill
        }
        return isPressed ? AppTheme.buttonFillPressed : AppTheme.buttonFill
    }

    private var buttonFont: Font {
        switch controlSize {
        case .mini:
            return .caption
        case .small:
            return .caption
        case .large:
            return .headline
        default:
            return .callout
        }
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 6
        case .small:
            return 8
        case .large:
            return 16
        default:
            return 12
        }
    }

    private var verticalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 2
        case .small:
            return 3
        case .large:
            return 8
        default:
            return 6
        }
    }

    private var minHeight: CGFloat {
        switch controlSize {
        case .mini:
            return 18
        case .small:
            return 22
        case .large:
            return 34
        default:
            return 28
        }
    }
}

extension ButtonStyle where Self == RenaissanceButtonStyle {
    static var renaissancePrimary: RenaissanceButtonStyle {
        RenaissanceButtonStyle(role: .primary)
    }

    static var renaissanceSecondary: RenaissanceButtonStyle {
        RenaissanceButtonStyle(role: .secondary)
    }
}

/// Wrap any SwiftUI window root with `.themedRoot()` to:
///   - tint every Picker / Toggle / DatePicker / Button / focus ring with gold
///   - set the window's backdrop to dark-brown canvas
///   - pin the color scheme to `.dark` so controls support beige-on-brown chrome
struct ThemedRoot<Content: View>: View {
    @ObservedObject private var appearance = AppAppearanceSettings.shared

    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .tint(AppTheme.accent)
            .foregroundStyle(AppTheme.ink)
            .font(.system(size: appearance.bodyFontSize))
            .dynamicTypeSize(appearance.dynamicTypeSize)
            .background(AppTheme.canvas)
            .buttonStyle(.renaissanceSecondary)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func themedRoot() -> some View { ThemedRoot { self } }
}
