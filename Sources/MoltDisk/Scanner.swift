import Foundation

struct Scanner: Sendable {
    let running: RunningApps
    /// Folders searched for projects; empty means `ProjectFolders.defaults`.
    var projectRoots: [URL] = []
    /// Also scan sandboxed apps' caches in ~/Library/Containers (macOS asks permission once).
    var includeContainers = false
    let home = FileManager.default.homeDirectoryForCurrentUser

    struct Job: Sendable {
        let categories: [Category]
        let run: @Sendable () async -> [CleanItem]
    }

    var jobs: [Job] {
        [
            Job(categories: [.dependencies, .buildArtifacts]) { await scanProjects() },
            Job(categories: [.xcode]) { await scanXcode() },
            Job(categories: [.packageCaches]) { await scanPackageCaches() },
            Job(categories: [.simulators]) { await scanSimulators() },
            Job(categories: [.editors]) { await scanEditors() },
            Job(categories: [.appCaches]) { await scanAllAppCaches() },
            Job(categories: [.logs]) { await scanFolderChildren(of: "Library/Logs", category: .logs) },
            Job(categories: [.downloads]) { await scanDownloads() },
            Job(categories: [.trash]) { await scanTrash() },
            Job(categories: [.apps]) { await scanApplications() },
        ]
    }

    // MARK: - Helpers

    func url(_ rel: String) -> URL { home.appendingPathComponent(rel) }

    func tilde(_ url: URL) -> String {
        let p = url.path
        return p.hasPrefix(home.path) ? "~" + p.dropFirst(home.path.count) : p
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func children(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { ![".DS_Store", ".localized"].contains($0.lastPathComponent) }
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    func mtime(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func item(_ url: URL, _ category: Category, title: String? = nil, safety: Safety, note: String? = nil,
              owner: String? = nil, ownerProcess: String? = nil, preselected: Bool = false) -> CleanItem {
        CleanItem(category: category, title: title ?? url.lastPathComponent, detail: tilde(url), kind: .path(url),
                  lastModified: mtime(url), safety: safety, note: note, owner: owner, ownerProcess: ownerProcess,
                  preselected: preselected)
    }

    /// Fills in sizes with `du`, drops small items and anything the safety guard would refuse,
    /// and locks items whose owning app is running.
    func finalize(_ items: [CleanItem], minSize: Int64 = 1_000_000) async -> [CleanItem] {
        let toMeasure = items.filter { $0.size == 0 }.flatMap { $0.kind.paths }
        let sizes = await Shell.diskUsage(of: toMeasure)
        return items.compactMap { original in
            var item = original
            if item.size == 0 { item.size = item.kind.paths.reduce(0) { $0 + (sizes[$1] ?? 0) } }
            guard item.size >= minSize else { return nil }
            switch item.kind {
            case .emptyTrash: break
            case .app(let bundle, let bundleID, let name, let files):
                guard (try? SafetyGuard.validateUninstall(bundle: bundle, bundleID: bundleID, name: name, files: files)) != nil else { return nil }
            default:
                if !item.kind.paths.allSatisfy(SafetyGuard.isAllowed) { return nil }
            }
            if item.blockedReason == nil {
                item.blockedReason = running.blockedReason(owner: item.owner, process: item.ownerProcess)
            }
            return item
        }
    }

    // MARK: - Xcode

    func scanXcode() async -> [CleanItem] {
        let xcode = "com.apple.dt.Xcode"
        var items: [CleanItem] = []
        for dir in children(of: url("Library/Developer/Xcode/DerivedData")) where isDirectory(dir) {
            let name = dir.lastPathComponent
            // "MyApp-abcdefghijk" -> "MyApp"
            let title = name.range(of: "-[a-z]{20,}$", options: .regularExpression).map { String(name[..<$0.lowerBound]) } ?? name
            items.append(item(dir, .xcode, title: "DerivedData · \(title)", safety: .safe,
                              note: "Rebuilt on next Xcode build", owner: xcode, preselected: true))
        }
        for day in children(of: url("Library/Developer/Xcode/Archives")) where isDirectory(day) {
            for archive in children(of: day) where archive.pathExtension == "xcarchive" {
                items.append(item(archive, .xcode, title: "Archive · \(archive.deletingPathExtension().lastPathComponent)",
                                  safety: .review, note: "Needed to re-export a build or symbolicate its crash logs",
                                  owner: xcode))
            }
        }
        for platform in ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport"] {
            for dir in children(of: url("Library/Developer/Xcode/\(platform)")) where isDirectory(dir) {
                items.append(item(dir, .xcode, title: "\(platform) · \(dir.lastPathComponent)", safety: .safe,
                                  note: "Re-copied the next time that device connects", owner: xcode, preselected: true))
            }
        }
        let previews = url("Library/Developer/Xcode/UserData/Previews")
        if exists(previews) {
            items.append(item(previews, .xcode, title: "SwiftUI Previews", safety: .safe,
                              note: "Preview simulators — recreated on demand", owner: xcode, preselected: true))
        }
        return await finalize(items)
    }

    // MARK: - Package caches

    /// Known tool caches (relative to home). App Caches skips these so nothing is listed twice.
    static let packageCaches: [(path: String, title: String, note: String)] = [
        (".npm/_cacache", "npm cache", "Re-downloaded on next install"),
        (".npm/_npx", "npx cache", "Re-downloaded on next npx run"),
        ("Library/Caches/pnpm", "pnpm metadata cache", "Re-downloaded on next install"),
        ("Library/Caches/Yarn", "Yarn cache", "Re-downloaded on next install"),
        (".yarn/berry/cache", "Yarn Berry cache", "Re-downloaded on next install"),
        (".bun/install/cache", "Bun cache", "Re-downloaded on next install"),
        ("Library/Caches/Homebrew", "Homebrew cache", "Old bottles and downloads — same as brew cleanup"),
        ("Library/Caches/CocoaPods", "CocoaPods cache", "Re-downloaded on next pod install"),
        (".cocoapods/repos", "CocoaPods spec repos", "Re-cloned on next pod install"),
        (".gradle/caches", "Gradle caches", "Re-downloaded on next Gradle build"),
        (".gradle/wrapper/dists", "Gradle wrapper distributions", "Re-downloaded on next Gradle build"),
        ("Library/Caches/pip", "pip cache", "Re-downloaded on next install"),
        ("Library/Caches/org.swift.swiftpm", "SwiftPM cache", "Re-downloaded on next resolve"),
        ("Library/Caches/go-build", "Go build cache", "Rebuilt on next go build"),
        ("Library/Caches/electron", "Electron downloads", "Re-downloaded on next install"),
        ("Library/Caches/ms-playwright", "Playwright browsers", "Reinstall with npx playwright install"),
        (".cargo/registry/cache", "Cargo registry cache", "Re-downloaded on next build"),
        (".m2/repository", "Maven repository (~/.m2)", "Spring Boot/Maven dependencies — re-downloaded on next build"),
        (".ivy2/cache", "Ivy cache", "Re-downloaded on next build"),
        (".nuget/packages", "NuGet packages", ".NET dependencies — re-downloaded by dotnet restore"),
        (".pub-cache", "Dart/Flutter pub cache", "Re-downloaded by flutter pub get"),
        ("Library/Caches/composer", "Composer cache", "Re-downloaded on next composer install"),
        (".composer/cache", "Composer cache", "Re-downloaded on next composer install"),
        ("go/pkg/mod", "Go module cache", "Re-downloaded on next build (same as go clean -modcache)"),
        (".gem", "Ruby gems (user)", "Reinstall with bundle install"),
        (".deno", "Deno cache", "Re-downloaded on next run"),
        ("Library/Caches/deno", "Deno cache", "Re-downloaded on next run"),
    ]

    func scanPackageCaches() async -> [CleanItem] {
        var items: [CleanItem] = []
        for cache in Self.packageCaches {
            let u = url(cache.path)
            guard exists(u) else { continue }
            let safety: Safety = cache.path.contains("playwright") ? .reinstall : .safe
            items.append(item(u, .packageCaches, title: cache.title, safety: safety, note: cache.note,
                              preselected: safety == .safe))
        }
        // pnpm content-addressable store: one folder per store format (v3, v10, v11...).
        // The newest one is live — projects hard-link or symlink into it — so it is locked.
        let storeRoot = url("Library/pnpm/store")
        let stores = children(of: storeRoot).filter { isDirectory($0) && $0.lastPathComponent.hasPrefix("v") }
        let newest = stores.max { (Int($0.lastPathComponent.dropFirst()) ?? 0) < (Int($1.lastPathComponent.dropFirst()) ?? 0) }
        for store in stores {
            let isLive = store == newest
            var entry = item(store, .packageCaches, title: "pnpm store \(store.lastPathComponent)",
                             safety: isLive ? .reinstall : .safe,
                             note: isLive ? "Active store — projects link into it" : "Old store format, unused by your pnpm version",
                             preselected: !isLive)
            if isLive { entry.blockedReason = "Active pnpm store — run `pnpm store prune` instead" }
            items.append(entry)
        }
        // ~/.cache/<tool>
        for dir in children(of: url(".cache")) where isDirectory(dir) {
            items.append(item(dir, .packageCaches, title: "~/.cache/\(dir.lastPathComponent)", safety: .safe,
                              note: "Tool cache — re-created on demand", preselected: true))
        }
        return await finalize(items)
    }

    // MARK: - Simulators

    private struct DeviceList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let isAvailable: Bool?
            let dataPath: String?
            let dataPathSize: Int64?
        }
        let devices: [String: [Device]]
    }

    private struct Runtime: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let sizeBytes: Int64?
        let deletable: Bool?
        let runtimeIdentifier: String?
        let lastUsedAt: String?
        let kind: String?
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-0" -> "iOS 26.0"
    private func runtimeName(_ id: String) -> String {
        let short = id.components(separatedBy: ".").last ?? id
        let parts = short.split(separator: "-")
        guard let os = parts.first else { return short }
        return parts.count > 1 ? "\(os) \(parts.dropFirst().joined(separator: "."))" : String(os)
    }

    func scanSimulators() async -> [CleanItem] {
        var items: [CleanItem] = []
        var bootedRuntimes: Set<String> = []

        let devicesJSON = await Shell.xcrun(["simctl", "list", "devices", "-j"])
        if let list = try? JSONDecoder().decode(DeviceList.self, from: Data(devicesJSON.output.utf8)) {
            for (runtimeID, devices) in list.devices {
                for d in devices {
                    if d.state == "Booted" { bootedRuntimes.insert(runtimeID) }
                    let deviceDir = d.dataPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
                    var size = d.dataPathSize ?? 0
                    if size == 0, let deviceDir { size = await Shell.diskUsage(deviceDir) }
                    let available = d.isAvailable ?? true
                    items.append(CleanItem(
                        category: .simulators, title: d.name, detail: "\(runtimeName(runtimeID)) · \(d.udid)",
                        kind: .simDevice(udid: d.udid), size: max(size, 1_000_000),
                        lastModified: deviceDir.flatMap(mtime),
                        safety: available ? .reinstall : .safe,
                        note: available ? "Apps and data on this simulator are lost; recreate it in Xcode" : "Its runtime is no longer installed",
                        blockedReason: d.state == "Booted" ? "Simulator is booted — shut it down first" : nil,
                        preselected: !available))
                }
            }
        }

        let runtimesJSON = await Shell.xcrun(["simctl", "runtime", "list", "-j"])
        if let runtimes = try? JSONDecoder().decode([String: Runtime].self, from: Data(runtimesJSON.output.utf8)) {
            let iso = ISO8601DateFormatter()
            for rt in runtimes.values {
                let name = rt.runtimeIdentifier.map(runtimeName) ?? "Runtime \(rt.version ?? "")"
                var blocked: String?
                if rt.deletable == false { blocked = "simctl reports this runtime can't be deleted" }
                if let rid = rt.runtimeIdentifier, bootedRuntimes.contains(rid) { blocked = "A simulator on this runtime is booted" }
                items.append(CleanItem(
                    category: .simulators, title: "\(name) runtime", detail: "Build \(rt.build ?? "?") · \(rt.kind ?? "Disk image")",
                    kind: .simRuntime(id: rt.identifier), size: rt.sizeBytes ?? 0,
                    lastModified: rt.lastUsedAt.flatMap { iso.date(from: $0) },
                    safety: .reinstall, note: "Re-download in Xcode › Settings › Components. Devices using it become unavailable.",
                    blockedReason: blocked))
            }
        }

        let caches = url("Library/Developer/CoreSimulator/Caches")
        if exists(caches) {
            items.append(item(caches, .simulators, title: "CoreSimulator caches", safety: .safe,
                              note: "Rebuilt when simulators boot", preselected: true))
        }
        return await finalize(items)
    }

    // MARK: - App caches & logs

    private static let cliOwners = ["claude-cli-nodejs": "claude"]

    func scanFolderChildren(of rel: String, category: Category, minSize: Int64 = 1_000_000) async -> [CleanItem] {
        // Listed elsewhere: tool caches under Package Caches, IDE folders under Editors & IDEs.
        let claimed = Set(Self.packageCaches.map(\.path)).union(IDEFamily.all.flatMap { ["Library/Caches/\($0.vendor)", "Library/Logs/\($0.vendor)"] })
        var items: [CleanItem] = []
        for child in children(of: url(rel)) {
            let name = child.lastPathComponent
            if claimed.contains("\(rel)/\(name)") { continue }
            let isApple = name.hasPrefix("com.apple.")
            let safety: Safety = isApple && category == .appCaches ? .review : .safe
            let note = category == .logs ? "Log files — apps write new ones as needed"
                : isApple ? "Used by macOS services — usually rebuilt, some may be protected"
                : "Cache — the app rebuilds it"
            items.append(item(child, category, safety: safety, note: note, owner: name,
                              ownerProcess: Self.cliOwners[name], preselected: safety == .safe))
        }
        return await finalize(items, minSize: minSize)
    }

    // MARK: - Downloads & Trash

    func scanDownloads() async -> [CleanItem] {
        let items = children(of: url("Downloads")).map { u in
            item(u, .downloads, safety: .review,
                 note: ["dmg", "pkg", "iso", "zip", "xip"].contains(u.pathExtension.lowercased())
                    ? "Installer or archive — fine to delete once installed/extracted" : "Personal file — check before deleting")
        }
        return await finalize(items, minSize: 100_000_000)
    }

    func scanTrash() async -> [CleanItem] {
        let trash = url(".Trash")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else {
            return [CleanItem(category: .trash, title: "Trash", detail: "~/.Trash", kind: .emptyTrash(trash),
                              safety: .review, note: "Can't read the Trash",
                              blockedReason: "Grant Full Disk Access in System Settings › Privacy to read the Trash")]
        }
        let visible = contents.filter { $0 != ".DS_Store" }
        guard !visible.isEmpty else { return [] }
        let size = await Shell.diskUsage(trash)
        return [CleanItem(category: .trash, title: "Empty Trash (\(visible.count) items)", detail: "~/.Trash",
                          kind: .emptyTrash(trash), size: size, lastModified: mtime(trash), safety: .review,
                          note: "Emptying the Trash is permanent")]
    }
}
