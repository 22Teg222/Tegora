import SwiftUI

/// Each section has its own colour mood, used for the animated backdrop, the sidebar icon and tinted controls.
struct SectionTheme: Equatable {
    let colors: [Color]
    let accent: Color

    var gradient: LinearGradient {
        LinearGradient(colors: Array(colors.prefix(2)), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension SidebarSection {
    var theme: SectionTheme {
        switch self {
        case .smartCare:
            return SectionTheme(colors: [Color(red: 0.05, green: 0.78, blue: 0.72), Color(red: 0.18, green: 0.45, blue: 0.95),
                                         Color(red: 0.45, green: 0.85, blue: 0.55)],
                                accent: Color(red: 0.08, green: 0.70, blue: 0.68))
        case .cleanup:
            return SectionTheme(colors: [Color(red: 0.20, green: 0.50, blue: 1.00), Color(red: 0.40, green: 0.30, blue: 0.95),
                                         Color(red: 0.10, green: 0.75, blue: 0.95)],
                                accent: Color(red: 0.22, green: 0.48, blue: 0.98))
        case .protection:
            return SectionTheme(colors: [Color(red: 0.10, green: 0.78, blue: 0.45), Color(red: 0.05, green: 0.62, blue: 0.70),
                                         Color(red: 0.55, green: 0.88, blue: 0.30)],
                                accent: Color(red: 0.12, green: 0.70, blue: 0.42))
        case .applications:
            return SectionTheme(colors: [Color(red: 1.00, green: 0.55, blue: 0.20), Color(red: 0.98, green: 0.30, blue: 0.50),
                                         Color(red: 1.00, green: 0.75, blue: 0.25)],
                                accent: Color(red: 0.98, green: 0.45, blue: 0.25))
        case .myClutter:
            return SectionTheme(colors: [Color(red: 0.65, green: 0.35, blue: 0.95), Color(red: 0.95, green: 0.35, blue: 0.75),
                                         Color(red: 0.40, green: 0.40, blue: 0.98)],
                                accent: Color(red: 0.62, green: 0.38, blue: 0.95))
        case .spaceLens:
            return SectionTheme(colors: [Color(red: 0.25, green: 0.35, blue: 0.95), Color(red: 0.10, green: 0.70, blue: 0.95),
                                         Color(red: 0.55, green: 0.30, blue: 0.90)],
                                accent: Color(red: 0.25, green: 0.50, blue: 0.98))
        }
    }
}

private struct SectionThemeKey: EnvironmentKey {
    static let defaultValue = SidebarSection.smartCare.theme
}

extension EnvironmentValues {
    var sectionTheme: SectionTheme {
        get { self[SectionThemeKey.self] }
        set { self[SectionThemeKey.self] = newValue }
    }
}

/// A rounded-square gradient tile with a white SF Symbol, in the style of macOS Settings icons.
struct IconBadge: View {
    let symbol: String
    var colors: [Color]
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: (colors.first ?? .clear).opacity(0.35), radius: size * 0.2, y: size * 0.07)
    }
}

/// Slowly drifting blurred colour fields that give the glass something to refract.
struct AuroraBackground: View {
    let theme: SectionTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let base: Color = scheme == .dark ? Color(red: 0.04, green: 0.05, blue: 0.09)
                                                  : Color(red: 0.95, green: 0.96, blue: 0.985)
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
                ctx.addFilter(.blur(radius: min(size.width, size.height) * 0.14))
                let radius = min(size.width, size.height) * 0.42
                for (index, color) in theme.colors.enumerated() {
                    let phase = Double(index) * 2.1
                    let x = size.width * (0.5 + 0.38 * sin(t * 0.11 + phase))
                    let y = size.height * (0.5 + 0.34 * cos(t * 0.09 + phase * 1.4))
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(scheme == .dark ? 0.50 : 0.32)))
                }
            }
        }
    }
}
