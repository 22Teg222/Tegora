import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable {
    case systemCache, logs, temporary, languages, xcode, mail, iosBackups, trash, brokenPreferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemCache: return "System Cache"
        case .logs: return "Logs"
        case .temporary: return "Temporary Files"
        case .languages: return "Language Files"
        case .xcode: return "Xcode Junk"
        case .mail: return "Mail Attachments"
        case .iosBackups: return "iOS Backups"
        case .trash: return "Trash"
        case .brokenPreferences: return "Broken Preferences"
        }
    }

    var symbol: String {
        switch self {
        case .systemCache: return "internaldrive"
        case .logs: return "doc.text"
        case .temporary: return "clock.arrow.circlepath"
        case .languages: return "globe"
        case .xcode: return "hammer"
        case .mail: return "paperclip"
        case .iosBackups: return "iphone"
        case .trash: return "trash"
        case .brokenPreferences: return "slider.horizontal.3"
        }
    }

    var detail: String {
        switch self {
        case .systemCache: return "Cache folders apps keep in your Library. They are rebuilt automatically."
        case .logs: return "Diagnostic logs written by apps in your Library."
        case .temporary: return "Leftover files in your temporary folder that haven't been touched for a day."
        case .languages: return "Localisations in third-party apps for languages you don't use. Careful: this changes the app's own files and can break its code signature, so macOS may warn about the app or ask for permissions again. Most people should skip this."
        case .xcode: return "Derived data, device support files and old simulators from Xcode."
        case .mail: return "Attachments Mail has downloaded and stored locally."
        case .iosBackups: return "Local iPhone and iPad backups made by Finder."
        case .trash: return "Items already in your Trash."
        case .brokenPreferences: return "Preference files that are corrupt or no longer readable."
        }
    }

    /// Categories that need Full Disk Access to be scanned reliably.
    var needsFullDiskAccess: Bool {
        self == .mail || self == .iosBackups || self == .trash
    }

    /// Whether removal is permanent (the data is already discarded) instead of going to the Trash.
    var deletesPermanently: Bool { self == .trash }
}

struct CategoryResult: Identifiable {
    let category: CleanupCategory
    var items: [FoundItem]
    var warning: String? = nil

    var id: String { category.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}
