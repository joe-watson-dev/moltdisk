import SwiftUI

enum Category: String, CaseIterable, Identifiable, Sendable {
    case dependencies = "Dependencies"
    case buildArtifacts = "Build Artifacts"
    case xcode = "Xcode"
    case packageCaches = "Package Caches"
    case simulators = "iOS Simulators"
    case editors = "Editors & IDEs"
    case appCaches = "App Caches"
    case logs = "Logs"
    case downloads = "Large Downloads"
    case trash = "Trash"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dependencies: "shippingbox"
        case .buildArtifacts: "hammer"
        case .xcode: "wrench.and.screwdriver"
        case .packageCaches: "archivebox"
        case .simulators: "iphone"
        case .editors: "chevron.left.forwardslash.chevron.right"
        case .appCaches: "square.stack.3d.up"
        case .logs: "doc.text"
        case .downloads: "arrow.down.circle"
        case .trash: "trash"
        }
    }

    var blurb: String {
        switch self {
        case .dependencies: "Installed dependencies in your projects: node_modules, Python virtualenvs, vendor, Pods, deps… Restored by the package manager."
        case .buildArtifacts: "Generated output for JS, Python, Java/Spring, Rust, .NET, Flutter, Elixir, C/C++ and more. Rebuilt on the next build."
        case .xcode: "DerivedData, archives and device support files."
        case .packageCaches: "Download caches for npm, pnpm, Homebrew, CocoaPods, Gradle and other tools."
        case .simulators: "Simulator devices and runtimes, removed with xcrun simctl."
        case .editors: "Code editors and IDEs found on this Mac: unused extensions, old IDE versions and their caches. Pick an editor below for details."
        case .appCaches: "App and browser caches: ~/Library/Caches, Chrome/Electron caches in Application Support, and optionally sandboxed apps. Caches of running apps are locked — quit the app to clean them."
        case .logs: "Log files in ~/Library/Logs."
        case .downloads: "Items over 100 MB in your Downloads folder."
        case .trash: "Items already in the Trash. Emptying it is permanent."
        }
    }
}

enum Safety: Int, Sendable {
    case safe, unused, reinstall, review

    var label: String {
        switch self {
        case .safe: "Safe to delete"
        case .unused: "Not used recently"
        case .reinstall: "Will need reinstall"
        case .review: "Review first"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .unused: .teal
        case .reinstall: .orange
        case .review: .red
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .unused: "moon.zzz.fill"
        case .reinstall: "arrow.down.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        }
    }
}

enum ItemKind: Hashable, Sendable {
    case path(URL)
    /// Several small folders shown as one row, e.g. every __pycache__ in a project.
    case group([URL])
    case simDevice(udid: String)
    case simRuntime(id: String)
    case emptyTrash(URL)

    var id: String {
        switch self {
        case .path(let url): url.path
        case .group(let urls): "group:" + urls.map(\.path).joined(separator: "|")
        case .simDevice(let udid): "sim-device:\(udid)"
        case .simRuntime(let id): "sim-runtime:\(id)"
        case .emptyTrash(let url): "trash:\(url.path)"
        }
    }

    /// The on-disk location, when there is one to reveal.
    var url: URL? { paths.first }

    /// Every on-disk path this item deletes (and measures).
    var paths: [URL] {
        switch self {
        case .path(let url), .emptyTrash(let url): [url]
        case .group(let urls): urls
        default: []
        }
    }
}

struct CleanItem: Identifiable, Hashable, Sendable {
    var category: Category
    var title: String
    var detail: String
    var kind: ItemKind
    var size: Int64 = 0
    var lastModified: Date? = nil
    var safety: Safety
    var note: String? = nil
    /// Set when the item must not be deleted right now (e.g. its app is running).
    var blockedReason: String? = nil
    /// Bundle ID or folder name of the app that owns this data; re-checked right before deleting.
    var owner: String? = nil
    /// Name of a command-line process that owns this data.
    var ownerProcess: String? = nil
    var preselected: Bool = false
    /// Sub-section inside a category, e.g. the editor ("Cursor", "WebStorm") an extension belongs to.
    var group: String? = nil

    var id: String { kind.id }
    var isSelectable: Bool { blockedReason == nil }
    var sortDate: Date { lastModified ?? .distantPast }
    var safetyRank: Int { blockedReason == nil ? safety.rawValue : 99 }
    var categoryName: String { category.rawValue }
}

/// What the sidebar shows. Cleaning only ever acts on the items of the current entry.
enum SidebarEntry: Hashable {
    case overview
    case category(Category)
    case group(Category, String)

    var title: String {
        switch self {
        case .overview: "Overview"
        case .category(let c): c.rawValue
        case .group(_, let name): name
        }
    }

    var symbol: String {
        switch self {
        case .overview: "internaldrive"
        case .category(let c), .group(let c, _): c.symbol
        }
    }

    var blurb: String? {
        switch self {
        case .overview: nil
        case .category(let c): c.blurb
        case .group(_, let name):
            CodeEditor.all.contains { $0.name == name }
                ? "Every \(name) extension with when you last used it. Recently used ones are locked; old copies and caches are safe."
                : "Old \(name) versions left behind after upgrades, plus caches and logs. The version you use is kept."
        }
    }

    func contains(_ item: CleanItem) -> Bool {
        switch self {
        case .overview: true
        case .category(let c): item.category == c
        case .group(let c, let name): item.category == c && item.group == name
        }
    }
}

struct CleanResult: Identifiable, Sendable {
    let item: CleanItem
    let error: String?
    var id: String { item.id }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
