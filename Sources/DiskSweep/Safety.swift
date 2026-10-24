import AppKit

/// What is running right now, so data that belongs to a live app is never deleted.
struct RunningApps: Sendable {
    /// Lowercased bundle ID -> app name.
    let apps: [String: String]
    /// Lowercased app names.
    let names: Set<String>
    /// Short command names of all processes (`ps -c`).
    let processes: Set<String>

    static func snapshot() -> RunningApps {
        var apps: [String: String] = [:]
        var names: Set<String> = []
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName ?? app.bundleIdentifier ?? "An app"
            if let id = app.bundleIdentifier { apps[id.lowercased()] = name }
            names.insert(name.lowercased())
        }
        let ps = Shell.runSync("/bin/ps", ["-axco", "comm="])
        let processes = Set(ps.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        return RunningApps(apps: apps, names: names, processes: processes)
    }

    /// Name of the running app that owns `token` (a bundle ID or a cache/log folder name), if any.
    /// Deliberately broad: "Google" matches a running com.google.Chrome, "com.foo.App.ShipIt" matches com.foo.App.
    func runningOwner(of token: String) -> String? {
        let t = token.lowercased()
        for (bundleID, name) in apps {
            if t == bundleID || t.hasPrefix(bundleID + ".") { return name }
            let parts = bundleID.split(separator: ".")
            if parts.count >= 3, parts[0] != "com" || parts[1] != "apple", t == parts[1] { return name }
        }
        if names.contains(t) { return token }
        // Plain file names like "warp.log.old.0" -> "warp".
        let isReverseDNS = ["com.", "org.", "io.", "net.", "dev.", "app."].contains { t.hasPrefix($0) }
        if !isReverseDNS, let stem = t.split(separator: ".").first, names.contains(String(stem)) {
            return String(stem).capitalized
        }
        return nil
    }

    func blockedReason(owner: String?, process: String?) -> String? {
        if let owner, let name = runningOwner(of: owner) { return "\(name) is running — quit it to clean this" }
        if let process, processes.contains(process) { return "\(process) is running — quit it to clean this" }
        return nil
    }
}

/// Last line of defence: every path is checked here right before it is deleted.
enum SafetyGuard {
    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    static let vscodeCacheFolders = [
        "Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache",
        "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
    ]

    /// Paths (relative to home) that are allowed even though a protected prefix covers them.
    static let exceptions: Set<String> = Set(CodeEditor.all.flatMap { editor in
        vscodeCacheFolders.map { "Library/Application Support/\(editor.supportDir)/\($0)" }
    })

    static let neverTouch = ["Library/Application Support/Claude"]

    static let protectedPrefixes = [
        "Library/Application Support", "Library/Containers", "Library/Group Containers",
        "Library/Mobile Documents", "Library/Keychains", "Library/Mail", "Library/Messages",
        "Library/Preferences", "Library/CloudStorage", "Documents", "Desktop", "Pictures",
        "Movies", "Music", ".ssh", ".gnupg", ".config",
    ]

    enum Violation: LocalizedError {
        case outsideHome(String), tooShallow(String), protected(String)
        var errorDescription: String? {
            switch self {
            case .outsideHome(let p): "Refused: \(p) is outside your home folder"
            case .tooShallow(let p): "Refused: \(p) is a top-level folder"
            case .protected(let p): "Refused: \(p) is protected app or personal data"
            }
        }
    }

    static func validate(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { throw Violation.outsideHome(path) }
        let rel = String(path.dropFirst(home.count + 1))
        guard rel.split(separator: "/").count >= 2 else { throw Violation.tooShallow(path) }
        func under(_ prefix: String) -> Bool { rel == prefix || rel.hasPrefix(prefix + "/") }
        if neverTouch.contains(where: under) { throw Violation.protected(path) }
        if exceptions.contains(rel) { return }
        // An old IDE version's folder, e.g. Library/Application Support/JetBrains/WebStorm2024.3
        if IDEFamily.isVersionedSupportFolder(rel) { return }
        // Chromium/Electron cache folders inside Application Support, e.g. ".../Slack/Code Cache".
        let parts = rel.split(separator: "/").map(String.init)
        if under("Library/Application Support"), parts.count >= 4, let last = parts.last,
           Scanner.chromiumCacheNames.contains(last) { return }
        // A sandboxed app's cache folder: Library/Containers/<id>/Data/Library/Caches
        if parts.count == 6, parts[0] == "Library", parts[1] == "Containers", parts[3...] == ["Data", "Library", "Caches"] { return }
        if protectedPrefixes.contains(where: under) { throw Violation.protected(path) }
    }

    static func isAllowed(_ url: URL) -> Bool { (try? validate(url)) != nil }
}
