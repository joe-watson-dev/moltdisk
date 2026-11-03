import Foundation

/// Works out when each extension of a VS Code-family editor was last really used, from:
/// - the editor's extension-host logs ("_doActivateExtension <id> … activationEvent: '<why>'"),
/// - activity in the extension's globalStorage / workspaceStorage folders,
/// - MoltDisk's own history of past activations (VS Code only keeps a few log sessions),
/// - the install date and VS Code's list of disabled extensions.
struct VSCodeUsage {
    struct Entry: Codable {
        /// Last activation for a specific reason (a language, command, view…).
        var used: Date?
        /// Last activation that happened only because VS Code started.
        var startup: Date?
    }

    var entries: [String: Entry] = [:]
    var trackingSince: Date?

    static let recentDays = 30
    let support: URL

    /// VS Code keeps its original history file name; other editors get their own.
    static func historyFile(for editor: CodeEditor) -> URL {
        let name = editor.supportDir == "Code" ? "vscode" : editor.supportDir.lowercased().replacingOccurrences(of: " ", with: "-")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MoltDisk/\(name)-usage.json")
    }

    private struct Saved: Codable {
        var entries: [String: Entry]
        var trackingSince: Date?
    }

    /// Loads saved history, merges in the current logs and saves it back.
    static func load(_ editor: CodeEditor) -> VSCodeUsage {
        var usage = VSCodeUsage(support: editor.supportURL)
        let historyFile = historyFile(for: editor)
        if let data = try? Data(contentsOf: historyFile), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            usage.entries = saved.entries
            usage.trackingSince = saved.trackingSince
        }
        usage.mergeLogs()
        if let data = try? JSONEncoder().encode(Saved(entries: usage.entries, trackingSince: usage.trackingSince)) {
            try? FileManager.default.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: historyFile)
        }
        return usage
    }

    private mutating func mergeLogs() {
        let fm = FileManager.default
        let logs = support.appendingPathComponent("logs")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let sessionFormatter = DateFormatter()
        sessionFormatter.locale = Locale(identifier: "en_US_POSIX")
        sessionFormatter.dateFormat = "yyyyMMdd'T'HHmmss"

        for session in (try? fm.contentsOfDirectory(atPath: logs.path)) ?? [] {
            if let date = sessionFormatter.date(from: session), date < (trackingSince ?? .distantFuture) { trackingSince = date }
            let sessionDir = logs.appendingPathComponent(session)
            for window in (try? fm.contentsOfDirectory(atPath: sessionDir.path)) ?? [] where window.hasPrefix("window") {
                let log = sessionDir.appendingPathComponent("\(window)/exthost/exthost.log")
                guard let text = try? String(contentsOf: log, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") where line.contains("_doActivateExtension ") {
                    guard let date = formatter.date(from: String(line.prefix(19))),
                          let idPart = line.components(separatedBy: "_doActivateExtension ").last?.split(separator: ",").first
                    else { continue }
                    let id = idPart.trimmingCharacters(in: .whitespaces).lowercased()
                    let event = line.components(separatedBy: "activationEvent: '").last?.split(separator: "'").first.map(String.init) ?? ""
                    var entry = entries[id] ?? Entry()
                    if ["*", "onStartupFinished"].contains(event) {
                        entry.startup = max(entry.startup ?? .distantPast, date)
                    } else {
                        entry.used = max(entry.used ?? .distantPast, date)
                    }
                    entries[id] = entry
                }
            }
        }
    }

    /// Newest modification inside each extension's storage folders, keyed by lowercased extension ID.
    func storageActivity() -> [String: Date] {
        let fm = FileManager.default
        var latest: [String: Date] = [:]
        func record(_ dir: URL) {
            let id = dir.lastPathComponent.lowercased()
            guard id.contains(".") else { return }
            var newest = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            for child in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if let d = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d > newest { newest = d }
            }
            if newest > latest[id] ?? .distantPast { latest[id] = newest }
        }
        let user = support.appendingPathComponent("User")
        let global = user.appendingPathComponent("globalStorage")
        for dir in (try? fm.contentsOfDirectory(at: global, includingPropertiesForKeys: nil)) ?? [] { record(dir) }
        let workspaces = user.appendingPathComponent("workspaceStorage")
        for ws in (try? fm.contentsOfDirectory(at: workspaces, includingPropertiesForKeys: nil)) ?? [] {
            for dir in (try? fm.contentsOfDirectory(at: ws, includingPropertiesForKeys: nil)) ?? [] { record(dir) }
        }
        return latest
    }

    /// IDs VS Code has disabled, read from its state database.
    func disabledIDs() -> Set<String> {
        let db = support.appendingPathComponent("User/globalStorage/state.vscdb").path
        let r = Shell.runSync("/usr/bin/sqlite3", ["-readonly", db, "select value from ItemTable where key='extensionsIdentifiers/disabled'"])
        guard let list = try? JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0["id"] as? String)?.lowercased() })
    }
}

extension Scanner {
    struct VSCodeExtension {
        let url: URL
        let id: String
        let name: String
        let description: String
        let version: [Int]
        let versionText: String
        let dependencies: [String]
        /// No code ("main"/"browser"): only snippets, grammars or themes, which VS Code never logs as activated.
        let isDeclarative: Bool
        /// IDs and labels of the color/icon/product-icon themes it contributes, lowercased.
        let themes: Set<String>
    }

    /// Active color, icon and product-icon themes from settings.json, lowercased.
    static func activeThemes(_ editor: CodeEditor) -> Set<String> {
        let settings = editor.supportURL.appendingPathComponent("User/settings.json")
        guard let text = try? String(contentsOf: settings, encoding: .utf8) else { return [] }
        var themes: Set<String> = []
        // settings.json allows comments, so pull the values out with a pattern instead of a JSON parser.
        for key in ["workbench.colorTheme", "workbench.iconTheme", "workbench.productIconTheme"] {
            let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"([^\"]+)\""
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            themes.insert(text[range].lowercased())
        }
        return themes
    }

    /// Reads an extension's package.json, resolving "%key%" names through package.nls.json.
    static func readExtension(_ dir: URL) -> VSCodeExtension? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")),
              let pkg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publisher = pkg["publisher"] as? String, let name = pkg["name"] as? String
        else { return nil }
        let nls = (try? Data(contentsOf: dir.appendingPathComponent("package.nls.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        func localized(_ key: String) -> String? {
            guard let raw = pkg[key] as? String else { return key.hasPrefix("%") ? resolve(key) : nil }
            return resolve(raw)
        }
        func resolve(_ raw: String) -> String? {
            guard raw.hasPrefix("%"), raw.hasSuffix("%") else { return raw }
            let value = nls[String(raw.dropFirst().dropLast())]
            return value as? String ?? (value as? [String: Any])?["message"] as? String
        }
        let versionText = pkg["version"] as? String ?? "0"
        let contributes = pkg["contributes"] as? [String: Any] ?? [:]
        var themes: Set<String> = []
        for key in ["themes", "iconThemes", "productIconThemes"] {
            for theme in contributes[key] as? [[String: Any]] ?? [] {
                for field in ["id", "label"] {
                    if let value = theme[field] as? String { themes.insert((value.hasPrefix("%") ? localized(value) : value)?.lowercased() ?? value) }
                }
            }
        }
        return VSCodeExtension(
            url: dir, id: "\(publisher).\(name)".lowercased(),
            name: localized("displayName") ?? name, description: localized("description") ?? "",
            version: versionText.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }, versionText: versionText,
            dependencies: (pkg["extensionDependencies"] as? [String] ?? []).map { $0.lowercased() },
            isDeclarative: pkg["main"] == nil && pkg["browser"] == nil, themes: themes)
    }

    /// Every installed VS Code-family editor plus versioned IDEs (JetBrains, Android Studio).
    func scanEditors() async -> [CleanItem] {
        var items: [CleanItem] = []
        for editor in CodeEditor.all where editor.isInstalled {
            items += await scanCodeEditor(editor)
        }
        items += await scanIDEs()
        return items
    }

    func scanCodeEditor(_ editor: CodeEditor) async -> [CleanItem] {
        let owner = editor.owner
        let extRoot = editor.extensionsURL
        let usage = VSCodeUsage.load(editor)
        let storage = usage.storageActivity()
        let disabled = usage.disabledIDs()
        let activeThemes = Self.activeThemes(editor)

        var installed: [String: Date] = [:]
        if let data = try? Data(contentsOf: extRoot.appendingPathComponent("extensions.json")),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for e in list {
                guard let id = (e["identifier"] as? [String: Any])?["id"] as? String,
                      let ms = (e["metadata"] as? [String: Any])?["installedTimestamp"] as? Double else { continue }
                installed[id.lowercased()] = Date(timeIntervalSince1970: ms / 1000)
            }
        }

        let byID = Dictionary(grouping: children(of: extRoot).filter(isDirectory).compactMap(Self.readExtension), by: \.id)
        let now = Date()
        func daysAgo(_ d: Date) -> Int { Int(now.timeIntervalSince(d) / 86_400) }
        func ago(_ d: Date) -> String { d.formatted(.relative(presentation: .named)) }
        func lastUsed(_ id: String) -> Date? {
            [usage.entries[id]?.used, storage[id]].compactMap { $0 }.max()
        }

        // Extensions that a recently used extension depends on are kept too.
        var requiredBy: [String: String] = [:]
        for (id, versions) in byID {
            guard let used = lastUsed(id), daysAgo(used) <= VSCodeUsage.recentDays,
                  let newest = versions.max(by: { $0.version.lexicographicallyPrecedes($1.version) }) else { continue }
            for dep in newest.dependencies { requiredBy[dep] = newest.name }
        }

        let since = usage.trackingSince.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "recently"
        var items: [CleanItem] = []
        for (id, versions) in byID {
            let sorted = versions.sorted { !$0.version.lexicographicallyPrecedes($1.version) }
            let newest = sorted[0]
            for ext in sorted.dropFirst() {
                items.append(CleanItem(category: .editors, title: "\(ext.name) (old copy)", detail: "\(ext.id) · v\(ext.versionText)",
                                       kind: .path(ext.url), lastModified: mtime(ext.url), safety: .safe,
                                       note: "Old duplicate — \(editor.name) uses v\(newest.versionText)", owner: owner, preselected: true,
                                       group: editor.name))
            }

            let used = lastUsed(id)
            let startup = usage.entries[id]?.startup
            var safety = Safety.unused
            var blocked: String?
            var status: String
            if let used, daysAgo(used) <= VSCodeUsage.recentDays {
                blocked = "Used \(ago(used)) — kept"
                status = "Used \(ago(used))"
            } else if !newest.themes.isDisjoint(with: activeThemes) {
                blocked = "Provides the theme you're using — kept"
                status = "Your active theme"
            } else if let parent = requiredBy[id] {
                blocked = "Needed by \(parent), which you use"
                status = "Dependency of \(parent)"
            } else if let date = installed[id], daysAgo(date) <= 14 {
                blocked = "Installed \(ago(date)) — kept"
                status = "Installed \(ago(date))"
            } else if disabled.contains(id) {
                status = "Disabled in \(editor.name)" + (used.map { ", last used \(ago($0))" } ?? "")
            } else if let startup, daysAgo(startup) <= VSCodeUsage.recentDays {
                safety = .review
                status = "Loads every time \(editor.name) starts, so its use can't be measured"
                    + (used.map { ". Last real activity \(ago($0))" } ?? "")
            } else if newest.isDeclarative, used == nil {
                safety = .review
                status = "Snippets, grammar or theme only — \(editor.name) doesn't record when these are used"
            } else {
                status = used.map { "Not used since \(ago($0))" } ?? "No use recorded since \(since)"
            }
            let description = newest.description.isEmpty ? "" : "\(newest.description) — "
            items.append(CleanItem(category: .editors, title: newest.name, detail: "\(newest.id) · v\(newest.versionText)",
                                   kind: .path(newest.url), lastModified: used ?? startup ?? installed[id],
                                   safety: safety, note: description + status, blockedReason: blocked, owner: owner,
                                   group: editor.name))
        }

        for folder in SafetyGuard.vscodeCacheFolders {
            let u = editor.supportURL.appendingPathComponent(folder)
            guard exists(u) else { continue }
            var cache = item(u, .editors, title: "\(editor.name) \(folder)", safety: .safe,
                             note: "Cache — \(editor.name) rebuilds it", owner: owner, preselected: true)
            cache.group = editor.name
            items.append(cache)
        }
        // Every extension is listed, however small.
        return await finalize(items, minSize: 1)
    }
}
