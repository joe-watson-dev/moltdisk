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

// MARK: - Uninstalling apps

extension SafetyGuard {
    /// Library folders where apps keep files named after their bundle ID (or, for the first three, their name).
    static let appFileLocations: Set<String> = [
        "Application Support", "Caches", "Logs", "Containers", "Group Containers", "Preferences",
        "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "Application Scripts", "LaunchAgents",
    ]
    static let nameMatchedLocations: Set<String> = ["Application Support", "Caches", "Logs"]

    /// Folders apps may be installed in. Anything under /System or elsewhere is refused.
    static var appFolders: [String] { ["/Applications", home + "/Applications"] }

    /// Developer prefixes that are Apple's or belong to system tools, never offered for removal.
    static let systemDevelopers: Set<String> = ["is.workflow", "org.swift", "org.llvm", "org.python", "org.cups"]

    /// A Library file or folder name reduced to the identifier it belongs to: lowercased, without ".plist",
    /// ".savedState" or ".binarycookies", without a "group." / "systemgroup." prefix and without a leading
    /// developer Team ID ("S8EX82NJP6.com.macpaw.CleanMyMac4" -> "com.macpaw.cleanmymac4").
    static func normalizedID(_ leaf: String) -> String {
        var name = leaf
        let teamID = try! Regex("^[A-Z0-9]{10}\\.")
        if let match = name.prefixMatch(of: teamID), name[match.range].contains(where: \.isNumber) {
            name = String(name[match.range.upperBound...])
        }
        name = name.lowercased()
        for prefix in ["systemgroup.", "group."] where name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        for suffix in [".plist", ".savedstate", ".binarycookies"] where name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        return name
    }

    /// True for Apple's identifiers in any form (com.apple…, developer.apple…) and known system tools.
    static func isSystemID(_ id: String) -> Bool {
        let p = id.lowercased().split(separator: ".")
        guard p.count >= 2 else { return true }
        return p[0].contains("apple") || p[1].contains("apple") || systemDevelopers.contains("\(p[0]).\(p[1])")
    }

    /// An app MoltDisk will uninstall: reverse-DNS with at least three parts, never Apple's, a system tool's or its own.
    static func isUninstallable(bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        guard id.split(separator: ".").count >= 3, !isSystemID(id) else { return false }
        if let own = Bundle.main.bundleIdentifier?.lowercased(), id == own || id.hasPrefix(own + ".") { return false }
        return true
    }

    /// Whether a Library file or folder name belongs to `id` (an app's bundle ID, or a developer prefix for leftovers).
    static func belongs(_ leaf: String, to id: String) -> Bool {
        let n = normalizedID(leaf), id = id.lowercased()
        return !isSystemID(n) && (n == id || n.hasPrefix(id + "."))
    }

    /// Checks an uninstall right before it happens. The app bundle must sit in an Applications folder and carry
    /// `bundleID`; every other file must be directly inside a known Library location and named after the app's
    /// bundle ID (exactly, or with a "." suffix such as ".plist") or, in Application Support/Caches/Logs, its name.
    static func validateUninstall(bundle: URL?, bundleID: String, name: String, files: [URL]) throws {
        // Leftovers of a deleted app are grouped by developer prefix ("com.macpaw"), so two parts are enough there.
        let idOK = bundle == nil
            ? bundleID.split(separator: ".").count >= 2 && !isSystemID(bundleID) && isUninstallable(bundleID: bundleID + ".x")
            : isUninstallable(bundleID: bundleID)
        guard idOK else { throw Violation.protected(bundleID) }
        if let bundle {
            let path = bundle.standardizedFileURL.path
            let parent = bundle.standardizedFileURL.deletingLastPathComponent().path
            let grandparent = bundle.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent().path
            guard path.hasSuffix(".app"), appFolders.contains(parent) || appFolders.contains(grandparent),
                  !path.hasPrefix("/System/") else { throw Violation.protected(path) }
            let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
            guard (plist?["CFBundleIdentifier"] as? String)?.lowercased() == bundleID.lowercased() else {
                throw Violation.protected(path)
            }
        }
        let id = bundleID.lowercased()
        let appName = name.lowercased()
        for file in files {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(home + "/Library/") else { throw Violation.outsideHome(path) }
            let rel = String(path.dropFirst(home.count + 1))
            if neverTouch.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) { throw Violation.protected(path) }
            var parts = rel.split(separator: "/").map(String.init)
            // Preferences/ByHost/<id>.<host-uuid>.plist
            if parts.count == 4, parts[1] == "Preferences", parts[2] == "ByHost" { parts.remove(at: 2) }
            guard parts.count == 3, appFileLocations.contains(parts[1]) else { throw Violation.protected(path) }
            let byID = belongs(parts[2], to: id)
            let byName = bundle != nil && nameMatchedLocations.contains(parts[1]) && !appName.isEmpty && parts[2].lowercased() == appName
            guard byID || byName else { throw Violation.protected(path) }
        }
    }
}
