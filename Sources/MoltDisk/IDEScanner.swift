import Foundation

extension Scanner {
    /// JetBrains IDEs and Android Studio keep one folder per version in Caches, Application Support and Logs.
    /// Upgrading leaves the old ones behind; the newest version of each product is the one in use.
    func scanIDEs() async -> [CleanItem] {
        let bases = ["Library/Caches", "Library/Application Support", "Library/Logs"]
        var items: [CleanItem] = []
        for family in IDEFamily.all {
            // product prefix -> version -> folders across Caches / Application Support / Logs
            var found: [String: [[Int]: [URL]]] = [:]
            for base in bases {
                for dir in children(of: url("\(base)/\(family.vendor)")) where isDirectory(dir) {
                    guard let parsed = IDEFamily.parse(dir.lastPathComponent), family.products[parsed.prefix] != nil else { continue }
                    found[parsed.prefix, default: [:]][parsed.version, default: []].append(dir)
                }
            }
            for (prefix, versions) in found {
                let product = family.products[prefix]!
                let ordered = versions.keys.sorted { $0.lexicographicallyPrecedes($1) }
                guard let current = ordered.last else { continue }
                let currentName = "\(current[0]).\(current[1])"
                for version in ordered.dropLast() {
                    let dirs = versions[version]!
                    let name = "\(version[0]).\(version[1])"
                    items.append(CleanItem(
                        category: .editors, title: "\(product) \(name) (old version)",
                        detail: dirs.map { tilde($0) }.joined(separator: " · "),
                        kind: dirs.count == 1 ? .path(dirs[0]) : .group(dirs),
                        lastModified: dirs.compactMap(mtime).max(), safety: .safe,
                        note: "Caches, settings and plugins of \(product) \(name), left behind after upgrading to \(currentName). Keep it if you still run this version.",
                        owner: family.owner, group: product))
                }
                // The version in use: only its caches and logs, never its settings or plugins.
                for dir in versions[current]! {
                    if dir.path.contains("/Library/Caches/") {
                        items.append(CleanItem(
                            category: .editors, title: "\(product) \(currentName) caches", detail: tilde(dir), kind: .path(dir),
                            lastModified: mtime(dir), safety: .safe,
                            note: "Indexes and caches — rebuilt on next launch, so the first start is slower",
                            owner: family.owner, group: product))
                    } else if dir.path.contains("/Library/Logs/") {
                        items.append(CleanItem(
                            category: .editors, title: "\(product) \(currentName) logs", detail: tilde(dir), kind: .path(dir),
                            lastModified: mtime(dir), safety: .safe, note: "Log files — the IDE writes new ones as needed",
                            owner: family.owner, preselected: true, group: product))
                    }
                }
            }
        }
        return await finalize(items)
    }
}
