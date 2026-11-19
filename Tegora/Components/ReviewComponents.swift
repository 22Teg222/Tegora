import AppKit
import QuickLookThumbnailing
import SwiftUI

// MARK: - Icons and thumbnails

struct FileIconView: View {
    let url: URL
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// A Quick Look thumbnail (real preview for images, videos and documents), falling back to the file icon.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 44
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                FileIconView(url: url, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                       representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = rep.nsImage
            }
        }
    }
}

// MARK: - Selectable review list

/// The review screen used before anything is removed: every item shows its name, location, size and a preview,
/// with a checkbox. Nothing is selected by default unless the caller says so.
struct ReviewList: View {
    let items: [FoundItem]
    @Binding var selection: Set<URL>
    var showThumbnails = false
    var showNotes = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(items.map(\.url))
                }
                .buttonStyle(.link)
                Spacer()
                Text("\(selection.count) of \(items.count) selected · \(Fmt.bytes(selectedSize))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        ReviewRow(item: item, isSelected: selection.contains(item.url),
                                  showThumbnail: showThumbnails, showNote: showNotes) {
                            if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
                        }
                        Divider().padding(.leading, 54)
                    }
                }
            }
        }
    }

    private var allSelected: Bool { !items.isEmpty && selection.count == items.count }
    private var selectedSize: Int64 { items.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.size } }
}

struct ReviewRow: View {
    let item: FoundItem
    let isSelected: Bool
    var showThumbnail = false
    var showNote = true
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden()
            if showThumbnail { ThumbnailView(url: item.url, size: 36) } else { FileIconView(url: item.url, size: 28) }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(detailLine).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Fmt.bytes(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
    }

    private var detailLine: String {
        var parts: [String] = []
        if showNote, let note = item.note { parts.append(note) }
        parts.append(item.url.deletingLastPathComponent().friendlyPath)
        if let m = item.modified { parts.append(Fmt.relativeDate(m)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Confirmation and results

struct RemovalRequest: Identifiable {
    let id = UUID()
    let title: String
    let items: [FoundItem]
    let permanent: Bool
    var extraNote: String? = nil
    let perform: ([FoundItem]) async -> OperationReport

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Final confirmation, shown before every destructive operation.
struct ConfirmRemovalSheet: View {
    let request: RemovalRequest
    let onFinish: (OperationReport) -> Void
    let onCancel: () -> Void
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: request.permanent ? "exclamationmark.triangle.fill" : "trash.fill")
                    .font(.title).foregroundStyle(request.permanent ? .orange : .accentColor)
                VStack(alignment: .leading) {
                    Text(request.title).font(.title3.weight(.semibold))
                    Text("\(request.items.count) item\(request.items.count == 1 ? "" : "s") · \(Fmt.bytes(request.totalSize))")
                        .foregroundStyle(.secondary)
                }
            }
            Text(request.permanent
                 ? "These items will be permanently deleted. This can't be undone."
                 : "These items will be moved to the Trash. You can put them back from there.")
                .font(.callout)
            if let note = request.extraNote {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            GroupBox {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(request.items.prefix(200)) { item in
                            HStack {
                                Text(item.url.friendlyPath).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Fmt.bytes(item.size)).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        if request.items.count > 200 {
                            Text("and \(request.items.count - 200) more…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
            }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction).disabled(working)
                Button(request.permanent ? "Delete Permanently" : "Move to Trash") {
                    working = true
                    Task {
                        let report = await request.perform(request.items)
                        onFinish(report)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .prominentGlassButton()
                .tint(request.permanent ? .red : .accentColor)
                .disabled(working)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct ReportBanner: View {
    let report: OperationReport
    let dismiss: () -> Void

    var body: some View {
        GlassCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: report.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(report.errors.isEmpty ? .green : .orange).font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Removed \(report.removedCount) item\(report.removedCount == 1 ? "" : "s"), freed \(Fmt.bytes(report.freedBytes))")
                        .font(.headline)
                    ForEach(Array(report.errors.prefix(4).enumerated()), id: \.offset) { _, e in
                        Text(e).font(.caption).foregroundStyle(.secondary)
                    }
                    if report.errors.count > 4 {
                        Text("and \(report.errors.count - 4) more issues").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }
}

/// Explains Full Disk Access and takes the user to the right System Settings pane.
struct PermissionBanner: View {
    var body: some View {
        if !FileUtilities.hasFullDiskAccess() {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Disk Access is off").font(.headline)
                        Text("macOS protects Mail, Safari and some Library folders. Tegora only reads and removes what you review, but it needs this permission to see those locations. Turn it on for Tegora in System Settings, then relaunch the app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        ProtectionService.openSettings(ProtectionService.fullDiskAccessURL)
                    }
                }
            }
        }
    }
}
