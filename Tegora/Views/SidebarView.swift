import SwiftUI

struct RootView: View {
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        let theme = navigation.selection.theme
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            detail(for: navigation.selection)
                .id(navigation.selection)
                .transition(.opacity.combined(with: .scale(scale: 0.992)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    AuroraBackground(theme: theme)
                        .id(navigation.selection)
                        .transition(.opacity)
                        .ignoresSafeArea()
                }
                .animation(.smooth(duration: 0.35), value: navigation.selection)
        }
        .environment(\.sectionTheme, theme)
        .tint(theme.accent)
    }

    @ViewBuilder
    private func detail(for section: SidebarSection) -> some View {
        switch section {
        case .smartCare: SmartCareView()
        case .cleanup: CleanupView()
        case .protection: ProtectionView()
        case .applications: ApplicationsView()
        case .myClutter: MyClutterView()
        case .spaceLens: SpaceLensView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var navigation: Navigation
    @State private var hovered: SidebarSection?

    var body: some View {
        List(selection: Binding<SidebarSection?>(
            get: { navigation.selection },
            set: { if let value = $0 { navigation.selection = value } }
        )) {
            Section {
                ForEach(SidebarSection.allCases) { section in
                    HStack(spacing: 10) {
                        IconBadge(symbol: section.symbol, colors: section.theme.colors, size: 26)
                        Text(section.rawValue).font(.body.weight(navigation.selection == section ? .semibold : .regular))
                    }
                    .padding(.vertical, 3)
                    .scaleEffect(hovered == section ? 1.02 : 1, anchor: .leading)
                    .tag(section)
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.15)) { hovered = inside ? section : nil }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
