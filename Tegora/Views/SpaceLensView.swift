import SwiftUI

struct SpaceLensView: View {
    @State private var path: [URL] = [FileUtilities.home]
    @State private var nodes: [SpaceNode] = []
    @State private var scanning = false
    @State private var progress = (done: 0, total: 0)
    @State private var hovered: URL?
    @State private var selected: SpaceNode?
    @State private var largest: [FoundItem] = []
    @State private var showLargest = false
    @State private var removal: RemovalRequest?
    @State private var banner: OperationReport?
    @State private var task: Task<Void, Never>?

    private var current: URL { path.last ?? FileUtilities.home }
    private var totalSize: Int64 { nodes.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                PageHeader(title: "Space Lens", subtitle: "See what's taking up room. Click a folder to look inside.", symbol: "circle.hexagongrid")
                toolbar
                if let banner { ReportBanner(report: banner) { self.banner = nil } }
            }
            .padding(.horizontal, 32).padding(.bottom, 10)
            HStack(spacing: 0) {
                mapArea
                Divider()
                sidePanel.frame(width: 300)
            }
            .tegoraGlass(cornerRadius: 22)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .onAppear { if nodes.isEmpty && !scanning { scan() } }
        .onDisappear { task?.cancel() }
        .sheet(item: $removal) { request in
            ConfirmRemovalSheet(request: request) { report in
                banner = report; removal = nil; selected = nil; scan()
            } onCancel: { removal = nil }
        }
        .sheet(isPresented: $showLargest) {
            LargestFilesSheet(folder: current, items: largest) { showLargest = false }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { goUp() } label: { Image(systemName: "chevron.left") }.disabled(path.count < 2).help("Back")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(path.enumerated()), id: \.offset) { index, url in
                        if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent) { jump(to: index) }
                            .buttonStyle(.plain)
                            .fontWeight(index == path.count - 1 ? .semibold : .regular)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Home Folder") { reset(to: FileUtilities.home) }
                Button("Macintosh HD") { reset(to: URL(fileURLWithPath: "/")) }
                Button("Choose Folder…") { chooseFolder() }
            } label: { Label("Location", systemImage: "externaldrive") }
            .menuStyle(.borderlessButton).fixedSize()
            Button { findLargest() } label: { Label("Largest Files", systemImage: "list.number") }
            Button { scan() } label: { Image(systemName: "arrow.clockwise") }.disabled(scanning).help("Rescan")
        }
    }

    // MARK: Map

    private var mapArea: some View {
        ZStack {
            if scanning {
                VStack(spacing: 10) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).frame(width: 220)
                    Text("Measuring \(progress.done) of \(progress.total) items…").foregroundStyle(.secondary)
                }
            } else if nodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("This folder is empty or can't be read").foregroundStyle(.secondary)
                }
            } else {
                GeometryReader { geo in
                    let rects = Treemap.layout(nodes.map { ($0, Double($0.size)) },
                                               in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 12, dy: 12))
                    ZStack(alignment: .topLeading) {
                        ForEach(rects, id: \.0.id) { node, rect in tile(node, rect) }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: nodes)
    }

    private func tile(_ node: SpaceNode, _ rect: CGRect) -> some View {
        let isHover = hovered == node.id
        let isSelected = selected?.id == node.id
        let color = Treemap.color(for: node, total: totalSize)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(isHover || isSelected ? 0.95 : 0.78).gradient)
            .overlay(alignment: .topLeading) {
                if rect.width > 70 && rect.height > 40 {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if node.isDirectory { Image(systemName: "folder.fill").font(.caption2) }
                            Text(node.name).lineLimit(1).font(.caption.weight(.semibold))
                        }
                        Text(Fmt.bytes(node.size)).font(.caption2)
                    }
                    .foregroundStyle(.white).padding(7).shadow(radius: 1)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2))
            .frame(width: max(rect.width - 3, 1), height: max(rect.height - 3, 1))
            .offset(x: rect.minX + 1.5, y: rect.minY + 1.5)
            .scaleEffect(isHover ? 1.01 : 1)
            .onHover { hovered = $0 ? node.id : (hovered == node.id ? nil : hovered) }
            .onTapGesture(count: 2) { if node.isDirectory { descend(into: node) } }
            .onTapGesture { selected = node }
            .help("\(node.name) · \(Fmt.bytes(node.size))")
            .animation(.easeOut(duration: 0.12), value: isHover)
    }

    // MARK: Side panel

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let node = selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        FileIconView(url: node.url, size: 44)
                        VStack(alignment: .leading) {
                            Text(node.name).font(.headline).lineLimit(2)
                            Text(Fmt.bytes(node.size)).foregroundStyle(.secondary)
                        }
                    }
                    Text(node.url.friendlyPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if totalSize > 0 {
                        Text("\(Fmt.percent(Double(node.size) / Double(totalSize))) of this folder").font(.caption)
                    }
                    HStack {
                        if node.isDirectory { Button("Open") { descend(into: node) } }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                    }
                    Button("Move to Trash…", role: .destructive) {
                        removal = RemovalRequest(title: "Move \(node.name) to the Trash?",
                                                 items: [FoundItem(url: node.url, size: node.size, modified: nil)],
                                                 permanent: false) { items in
                            await Task.detached { ClutterService.remove(items) }.value
                        }
                    }
                }
                .padding(16)
                Divider()
            }
            HStack {
                Text("In this folder").font(.headline)
                Spacer()
                Text(Fmt.bytes(totalSize)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            List(nodes, selection: Binding(get: { selected?.id }, set: { id in selected = nodes.first { $0.id == id } })) { node in
                HStack(spacing: 8) {
                    Circle().fill(Treemap.color(for: node, total: totalSize)).frame(width: 9, height: 9)
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Fmt.bytes(node.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .tag(node.id)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }

    // MARK: Actions

    private func scan() {
        task?.cancel()
        scanning = true
        selected = nil
        progress = (0, 0)
        let folder = current
        task = Task {
            let result = await SpaceLensService.scan(folder: folder) { done, total in
                Task { @MainActor in progress = (done, total) }
            }
            if Task.isCancelled { return }
            nodes = result
            scanning = false
        }
    }

    private func descend(into node: SpaceNode) { path.append(node.url); scan() }
    private func goUp() { if path.count > 1 { path.removeLast(); scan() } }
    private func jump(to index: Int) { guard index < path.count - 1 else { return }; path = Array(path.prefix(index + 1)); scan() }
    private func reset(to url: URL) { path = [url]; scan() }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Analyse"
        if panel.runModal() == .OK, let url = panel.url { reset(to: url) }
    }

    private func findLargest() {
        let folder = current
        Task {
            largest = await Task.detached(priority: .userInitiated) { SpaceLensService.largestFiles(in: folder) }.value
            showLargest = true
        }
    }
}

private struct LargestFilesSheet: View {
    let folder: URL
    let items: [FoundItem]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest files in \(folder.lastPathComponent.isEmpty ? "Macintosh HD" : folder.lastPathComponent)")
                .font(.title3.weight(.semibold))
            List(items) { item in
                HStack(spacing: 10) {
                    FileIconView(url: item.url, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Text(item.url.deletingLastPathComponent().friendlyPath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass.circle") }
                        .buttonStyle(.borderless).help("Show in Finder")
                }
            }
            .frame(height: 360)
            HStack { Spacer(); Button("Done", action: close).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 580)
    }
}

// MARK: - Treemap layout

enum Treemap {
    /// Squarified treemap: lays out weighted items in a rectangle with tiles that stay close to square.
    static func layout(_ items: [(SpaceNode, Double)], in rect: CGRect) -> [(SpaceNode, CGRect)] {
        let sorted = items.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let total = sorted.reduce(0) { $0 + $1.1 }
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        let area = Double(rect.width * rect.height)
        let scaled = sorted.map { ($0.0, $0.1 / total * area) }
        var result: [(SpaceNode, CGRect)] = []
        var remaining = rect
        var row: [(SpaceNode, Double)] = []

        func worst(_ row: [(SpaceNode, Double)], _ side: Double) -> Double {
            let sum = row.reduce(0) { $0 + $1.1 }
            guard let maxV = row.map(\.1).max(), let minV = row.map(\.1).min(), sum > 0, side > 0 else { return .infinity }
            return max(side * side * maxV / (sum * sum), sum * sum / (side * side * minV))
        }

        func place(_ row: [(SpaceNode, Double)]) {
            let sum = row.reduce(0) { $0 + $1.1 }
            guard sum > 0 else { return }
            if remaining.width >= remaining.height {
                let w = CGFloat(sum) / remaining.height
                var y = remaining.minY
                for (node, v) in row {
                    let h = CGFloat(v) / w
                    result.append((node, CGRect(x: remaining.minX, y: y, width: w, height: h)))
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: remaining.width - w, height: remaining.height)
            } else {
                let h = CGFloat(sum) / remaining.width
                var x = remaining.minX
                for (node, v) in row {
                    let w = CGFloat(v) / h
                    result.append((node, CGRect(x: x, y: remaining.minY, width: w, height: h)))
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: remaining.height - h)
            }
        }

        for item in scaled {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [item], side) <= worst(row, side) {
                row.append(item)
            } else {
                place(row)
                row = [item]
            }
        }
        place(row)
        return result
    }

    static func color(for node: SpaceNode, total: Int64) -> Color {
        let palette: [Color] = [.blue, .teal, .indigo, .purple, .pink, .orange, .green, .cyan, .mint, .brown]
        let hash = abs(node.name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) })
        return palette[hash % palette.count]
    }
}
