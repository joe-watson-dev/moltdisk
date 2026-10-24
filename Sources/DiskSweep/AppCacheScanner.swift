import Foundation

extension Scanner {
    /// Cache folders Chromium-based browsers and Electron apps (Chrome, Slack, Discord, Cursor, Notion…)
    /// keep inside ~/Library/Application Support. All are rebuilt on demand.
    static let chromiumCacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GraphiteDawnCache", "ShaderCache", "GrShaderCache", "CacheStorage", "component_crx_cache",
        "GPUPersistentCache", "ScriptCache",
    ]

    /// Application Support folders never walked: Claude is off-limits, VS Code has its own category,
    /// the rest hold user data rather than Chromium caches.
    static let appSupportSkip: Set<String> = [
        "Claude", "Code", "MobileSync", "AddressBook", "CallHistoryDB", "Knowledge", "com.apple.TCC",
        "CloudDocs", "iCloud", "FileProvider", "Mail", "Messages",
    ]

    /// Folder name -> bundle ID, for apps whose support folder isn't named after the app.
    static let appSupportOwners = [
        "BraveSoftware": "com.brave.Browser",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Arc": "company.thebrowser.Browser",
        "Vivaldi": "com.vivaldi.Vivaldi",
        "discord": "com.hnc.Discord",
        "Google": "com.google.Chrome",
    ]

    /// Browser and Electron caches, one row per app (all of its cache folders together).
    func scanAppSupportCaches() -> [CleanItem] {
        let support = url("Library/Application Support")
        let fm = FileManager.default
        var items: [CleanItem] = []
        for appDir in children(of: support) where isDirectory(appDir) {
            let name = appDir.lastPathComponent
            if Self.appSupportSkip.contains(name) || name.hasPrefix("com.apple.") { continue }
            // Editors and IDEs have their own section.
            if CodeEditor.all.contains(where: { $0.supportDir == name }) || name == "JetBrains" { continue }
            guard let walker = fm.enumerator(at: appDir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                             options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
            else { continue }
            var caches: [URL] = []
            for case let dir as URL in walker {
                if walker.level > 5 { walker.skipDescendants(); continue }
                let values = try? dir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                let folder = dir.lastPathComponent
                guard Self.chromiumCacheNames.contains(folder) else { continue }
                // "Cache" is a generic name; only take it when Chromium's siblings or layout confirm it.
                if folder == "Cache" {
                    let parent = dir.deletingLastPathComponent()
                    let chromium = ["Code Cache", "GPUCache"].contains { exists(parent.appendingPathComponent($0)) }
                        || exists(dir.appendingPathComponent("Cache_Data"))
                    guard chromium else { continue }
                }
                if folder == "CacheStorage", dir.deletingLastPathComponent().lastPathComponent != "Service Worker" { continue }
                caches.append(dir)
                walker.skipDescendants()
            }
            guard !caches.isEmpty else { continue }
            let kinds = Set(caches.map(\.lastPathComponent)).sorted().joined(separator: ", ")
            items.append(CleanItem(
                category: .appCaches, title: "\(name) — app caches",
                detail: "\(tilde(appDir)) · \(caches.count) folders", kind: caches.count == 1 ? .path(caches[0]) : .group(caches),
                lastModified: mtime(appDir), safety: .safe,
                note: "Browser/Electron caches (\(kinds)) — rebuilt when the app runs. Logins and settings are kept.",
                owner: Self.appSupportOwners[name] ?? name, preselected: true))
        }
        return items
    }

    /// Caches of sandboxed apps (~/Library/Containers/<app>/Data/Library/Caches).
    /// Off by default: macOS asks before an app may read other apps' containers.
    func scanContainerCaches() -> [CleanItem] {
        var items: [CleanItem] = []
        for container in children(of: url("Library/Containers")) {
            let caches = container.appendingPathComponent("Data/Library/Caches")
            guard exists(caches) else { continue }
            let id = container.lastPathComponent
            let isApple = id.hasPrefix("com.apple.")
            var entry = item(caches, .appCaches, title: "\(id) — sandbox cache", safety: isApple ? .review : .safe,
                             note: isApple ? "Used by macOS — usually rebuilt" : "Cache — the app rebuilds it",
                             owner: id, preselected: !isApple)
            entry.detail = tilde(caches)
            items.append(entry)
        }
        return items
    }

    func scanAllAppCaches() async -> [CleanItem] {
        var items = await scanFolderChildren(of: "Library/Caches", category: .appCaches, minSize: 5_000_000)
        items += await finalize(scanAppSupportCaches(), minSize: 5_000_000)
        if includeContainers { items += await finalize(scanContainerCaches(), minSize: 5_000_000) }
        return items
    }
}
