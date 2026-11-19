import Foundation

enum Fmt {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func bytes(_ value: Int64) -> String {
        if value <= 0 { return "Zero KB" }
        return byteFormatter.string(fromByteCount: value)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

extension URL {
    /// Path with the home directory abbreviated to "~".
    var friendlyPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
