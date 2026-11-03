import Foundation

/// Apps on this Mac with every file they keep in ~/Library, plus files left behind by apps that are gone.
enum AppScanner {
    static let installedGroup = "Installed"
    static let leftoversGroup = "Leftovers"
    /// Apps not opened for this long are labelled "Not used recently".
    static let unusedDays = 90

    struct AppInfo {
        let bundle: URL
        let bundleID: String
        let name: String
    }

    /// Reads an app bundle's ID and display name.
    static func info(_ bundle: URL) -> AppInfo? {
        guard let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let id = plist["CFBundleIdentifier"] as? String else { return nil }
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
            ?? bundle.deletingPathExtension().lastPathComponent
        return AppInfo(bundle: bundle, bundleID: id, name: name)
    }

    /// .app bundles in /Applications (and one folder deep, e.g. /Applications/Adobe X/X.app) and ~/Applications.
    static func installedApps() -> [AppInfo] {
        let fm = FileManager.default
        var bundles: [URL] = []
        for folder in SafetyGuard.appFolders {
            let root = URL(fileURLWithPath: folder)
            for entry in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if entry.pathExtension == "app" {
                    bundles.append(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let inner = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
                    bundles += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        return bundles.compactMap(info).filter { SafetyGuard.isUninstallable(bundleID: $0.bundleID) }
    }

    /// Files in ~/Library that belong to an app: named after its bundle ID (or a sub-ID like "<id>.helper"),
    /// or, in Application Support, Caches and Logs, after its name.
    static func files(bundleID: String, name: String, library: URL) -> [URL] {
        let fm = FileManager.default
        let id = bundleID.lowercased(), appName = name.lowercased()
        var found: [URL] = []
        for location in SafetyGuard.appFileLocations.sorted() {
            let dir = library.appendingPathComponent(location)
            var entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            if location == "Preferences" {
                entries += (try? fm.contentsOfDirectory(at: dir.appendingPathComponent("ByHost"), includingPropertiesForKeys: nil)) ?? []
            }
            for entry in entries {
                let byID = SafetyGuard.belongs(entry.lastPathComponent, to: id)
                let byName = SafetyGuard.nameMatchedLocations.contains(location) && entry.lastPathComponent.lowercased() == appName
                if byID || byName { found.append(entry) }
            }
        }
        return found
    }

    /// When each app was last opened (Spotlight's kMDItemLastUsedDate), in one mdls call.
    static func lastUsed(_ bundles: [URL]) -> [URL: Date] {
        guard !bundles.isEmpty else { return [:] }
        let result = Shell.runSync("/usr/bin/mdls", ["-raw", "-name", "kMDItemLastUsedDate"] + bundles.map(\.path))
        let values = result.output.split(separator: "\0", omittingEmptySubsequences: false)
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var dates: [URL: Date] = [:]
        for (bundle, value) in zip(bundles, values) {
            if let date = parser.date(from: String(value).trimmingCharacters(in: .whitespacesAndNewlines)) { dates[bundle] = date }
        }
        return dates
    }

    /// Bundle IDs of every app Spotlight knows about, anywhere on disk (so helpers and apps outside
    /// /Applications still count as installed).
    static func allKnownBundleIDs() -> Set<String> {
        let result = Shell.runSync("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"])
        var ids: Set<String> = []
        for line in result.output.split(separator: "\n") {
            if let id = info(URL(fileURLWithPath: String(line)))?.bundleID.lowercased() { ids.insert(id) }
        }
        return ids
    }

    /// Products whose identifier isn't their name.
    static let knownProducts = [
        "slackmacgap": "Slack", "xos": "Zoom", "client": "", "desktop": "", "app": "", "mac": "", "macos": "",
        "installer": "", "cli": "", "storage": "", "helper": "", "agent": "", "updater": "",
    ]

    /// First parts of real reverse-DNS identifiers. Names like "warp.log.old.0" look similar but aren't app IDs.
    static let domainEndings: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "co", "us", "uk", "de", "fr", "nl", "se", "no", "dk", "fi", "ch", "at",
        "be", "es", "it", "pt", "pl", "cz", "ru", "ua", "jp", "cn", "kr", "tw", "hk", "in", "au", "nz", "ca", "br",
        "mx", "ar", "is", "ie", "il", "sg", "me", "tv", "cc", "ai", "so", "sh", "xyz", "info", "biz", "company",
        "studio", "tech", "design", "page", "fm", "ly", "to", "gg", "eu",
    ]

    /// A readable name for leftovers: the product part of the most common identifier ("com.hnc.Discord" -> "Discord"),
    /// or the developer when that part is generic or a code ("com.spotify.client" -> "Spotify").
    static func displayName(developer: String, products: [String: Int]) -> String {
        func pretty(_ s: Substring) -> String { s.prefix(1).uppercased() + s.dropFirst() }
        let dev = developer.split(separator: ".").last.map(pretty) ?? developer
        guard let top = products.max(by: { $0.value < $1.value })?.key else { return dev }
        if let known = knownProducts[top.lowercased()] { return known.isEmpty ? dev : known }
        let digits = top.filter(\.isNumber).count
        return digits * 3 > top.count ? dev : pretty(Substring(top))
    }
}

extension Scanner {
    func scanApplications() async -> [CleanItem] {
        let library = url("Library")
        let apps = AppScanner.installedApps()
        let used = AppScanner.lastUsed(apps.map(\.bundle))
        let unusedSince = Calendar.current.date(byAdding: .day, value: -AppScanner.unusedDays, to: Date()) ?? .distantPast
        var items: [CleanItem] = []

        for app in apps {
            let files = AppScanner.files(bundleID: app.bundleID, name: app.name, library: library)
            let lastUsed = used[app.bundle]
            let isUnused = lastUsed.map { $0 < unusedSince } ?? false
            // The Finder name ("Visual Studio Code"); the bundle name ("Code") is what its folders use.
            let title = app.bundle.deletingPathExtension().lastPathComponent
            var item = CleanItem(
                category: .apps, title: title,
                detail: files.isEmpty ? tilde(app.bundle) : "\(tilde(app.bundle)) + \(files.count) related item\(files.count == 1 ? "" : "s")",
                kind: .app(bundle: app.bundle, bundleID: app.bundleID, name: app.name, files: files),
                lastModified: lastUsed, safety: isUnused ? .unused : .reinstall,
                note: ([app.bundleID] + files.map(tilde)).joined(separator: "\n"),
                owner: app.bundleID)
            item.group = AppScanner.installedGroup
            if files.contains(where: { f in SafetyGuard.neverTouch.contains { f.path.hasPrefix(home.path + "/" + $0) } }) {
                item.blockedReason = "Protected — DiskSweep never removes this app's data"
            }
            items.append(item)
        }

        items += orphanLeftovers(installed: apps, library: library)
        // Installed apps always show; leftovers that take no space (empty folders) are noise.
        return await finalize(items, minSize: 0).filter { item in
            if case .app(nil, _, _, _) = item.kind { return item.size > 0 }
            return true
        }
    }

    /// Files named after an identifier that no app on this Mac has, one row per developer. Skipped when
    /// Spotlight can't list apps (then every file would look orphaned).
    func orphanLeftovers(installed: [AppScanner.AppInfo], library: URL) -> [CleanItem] {
        var known = AppScanner.allKnownBundleIDs()
        known.formUnion(installed.map { $0.bundleID.lowercased() })
        known.formUnion(running.apps.keys)
        guard known.count >= 10 else { return [] }
        // A developer with any app still on this Mac is skipped entirely, so helpers and extensions of
        // installed apps never show up as leftovers.
        func developer(_ id: String) -> String? {
            let p = id.split(separator: ".")
            return p.count >= 2 ? "\(p[0]).\(p[1])" : nil
        }
        let installedDevelopers = Set(known.compactMap(developer))
        let reverseDNS = try! Regex("^[a-z0-9-]+\\.[a-z0-9-]+\\.[a-z0-9._-]+$")
        var byDeveloper: [String: [URL]] = [:]
        var products: [String: [String: Int]] = [:]
        let fm = FileManager.default
        for location in SafetyGuard.appFileLocations.sorted() {
            let dir = library.appendingPathComponent(location)
            for entry in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                let id = SafetyGuard.normalizedID(entry.lastPathComponent)
                guard id.wholeMatch(of: reverseDNS) != nil, !SafetyGuard.isSystemID(id), let dev = developer(id),
                      AppScanner.domainEndings.contains(String(id.split(separator: ".")[0])),
                      !installedDevelopers.contains(dev) else { continue }
                byDeveloper[dev, default: []].append(entry)
                let original = entry.lastPathComponent
                let product = original.split(separator: ".").first { $0.lowercased() == id.split(separator: ".")[2] }
                    .map(String.init) ?? String(id.split(separator: ".")[2])
                products[dev, default: [:]][product, default: 0] += 1
            }
        }
        return byDeveloper.map { dev, files in
            let names = (products[dev] ?? [:]).keys.sorted()
            let shown = names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " +\(names.count - 2)" : "")
            var item = CleanItem(
                category: .apps, title: AppScanner.displayName(developer: dev, products: products[dev] ?? [:]),
                detail: "\(dev) · \(shown) · \(files.count) item\(files.count == 1 ? "" : "s") left behind",
                kind: .app(bundle: nil, bundleID: dev, name: "", files: files.sorted { $0.path < $1.path }),
                lastModified: files.compactMap(mtime).max(), safety: .review,
                note: files.map(tilde).joined(separator: "\n"), owner: dev)
            item.group = AppScanner.leftoversGroup
            return item
        }
    }
}
