import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case smartCare = "Smart Care"
    case cleanup = "Cleanup"
    case protection = "Protection"
    case applications = "Applications"
    case myClutter = "My Clutter"
    case spaceLens = "Space Lens"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .smartCare: return "sparkles"
        case .cleanup: return "trash.slash"
        case .protection: return "checkmark.shield"
        case .applications: return "square.grid.2x2"
        case .myClutter: return "square.stack.3d.up"
        case .spaceLens: return "circle.hexagongrid"
        }
    }
}

@main
struct TegoraApp: App {
    @StateObject private var smartCare = SmartCareModel()
    @StateObject private var navigation = Navigation()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(smartCare)
                .environmentObject(navigation)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { navigation.selection = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}

final class Navigation: ObservableObject {
    @Published var selection: SidebarSection = .smartCare
}
