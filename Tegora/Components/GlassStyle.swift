import SwiftUI

// MARK: - Glass modifiers

extension View {
    /// Liquid Glass on macOS 26 and later, a native material with a hairline edge on earlier systems.
    @ViewBuilder
    func tegoraGlass(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular,
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self.materialShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.materialShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Circular Liquid Glass, used for the big scan disc.
    @ViewBuilder
    func tegoraGlassCircle(interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: .circle)
        } else {
            self.materialShape(Circle())
        }
        #else
        self.materialShape(Circle())
        #endif
    }

    fileprivate func materialShape<S: InsettableShape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 0.8))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    /// The main call-to-action button: glass with a tint on macOS 26, bordered-prominent before that.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }

    /// A secondary button: plain glass on macOS 26, bordered before that.
    @ViewBuilder
    func glassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }
}

// MARK: - Containers

/// A rounded glass container with a soft hover response.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var hoverEffect = false
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tegoraGlass()
            .scaleEffect(hoverEffect && hovering ? 1.012 : 1)
            .animation(.smooth(duration: 0.22), value: hovering)
            .onHover { if hoverEffect { hovering = $0 } }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil
    @Environment(\.sectionTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let symbol {
                IconBadge(symbol: symbol, colors: theme.colors, size: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 30)
    }
}

// MARK: - Meters

/// A horizontal bar showing a fraction of a whole.
struct MeterBar: View {
    let fraction: Double
    var tint: Color? = nil
    var height: CGFloat = 8
    @Environment(\.sectionTheme) private var theme

    var body: some View {
        let color = tint ?? theme.accent
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color.gradient)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.smooth, value: fraction)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 12
    var tint: Color? = nil
    @Environment(\.sectionTheme) private var theme

    var body: some View {
        let color = tint ?? theme.accent
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: lineWidth * 0.6)
        }
        .animation(.smooth, value: fraction)
    }
}

/// A tile with a coloured icon, a title and a value.
struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    var detail: String? = nil
    var colors: [Color] = [.blue, .indigo]
    var tint: Color? = nil

    var body: some View {
        GlassCard(hoverEffect: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconBadge(symbol: symbol, colors: colors, size: 30)
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(tint ?? .primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
