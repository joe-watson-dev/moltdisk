import Foundation

/// An editor built on VS Code: same extension folders, logs and storage layout, under its own names.
struct CodeEditor: Sendable {
    let name: String
    /// Extensions folder, relative to home.
    let extensionsDir: String
    /// Folder in ~/Library/Application Support.
    let supportDir: String
    /// Bundle ID or app name, used to lock its data while it runs.
    let owner: String

    static let all: [CodeEditor] = [
        CodeEditor(name: "VS Code", extensionsDir: ".vscode/extensions", supportDir: "Code", owner: "com.microsoft.VSCode"),
        CodeEditor(name: "VS Code Insiders", extensionsDir: ".vscode-insiders/extensions", supportDir: "Code - Insiders", owner: "com.microsoft.VSCodeInsiders"),
        CodeEditor(name: "VSCodium", extensionsDir: ".vscode-oss/extensions", supportDir: "VSCodium", owner: "VSCodium"),
        CodeEditor(name: "Cursor", extensionsDir: ".cursor/extensions", supportDir: "Cursor", owner: "Cursor"),
        CodeEditor(name: "Windsurf", extensionsDir: ".windsurf/extensions", supportDir: "Windsurf", owner: "Windsurf"),
        CodeEditor(name: "Antigravity", extensionsDir: ".antigravity/extensions", supportDir: "Antigravity", owner: "Antigravity"),
        CodeEditor(name: "Kiro", extensionsDir: ".kiro/extensions", supportDir: "Kiro", owner: "Kiro"),
        CodeEditor(name: "Trae", extensionsDir: ".trae/extensions", supportDir: "Trae", owner: "Trae"),
        CodeEditor(name: "Positron", extensionsDir: ".positron/extensions", supportDir: "Positron", owner: "Positron"),
        CodeEditor(name: "Void", extensionsDir: ".void-editor/extensions", supportDir: "Void", owner: "Void"),
    ]

    var supportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\(supportDir)")
    }

    var extensionsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(extensionsDir) }

    /// Installed means it has extensions or app data; a leftover dotfolder with only settings doesn't count.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: extensionsURL.path) || FileManager.default.fileExists(atPath: supportURL.path)
    }
}

/// IDE families that keep one folder per version, e.g. ~/Library/Caches/JetBrains/WebStorm2025.1.
struct IDEFamily: Sendable {
    /// Vendor folder inside Caches, Application Support and Logs.
    let vendor: String
    /// Folder prefix -> product name.
    let products: [String: String]
    let owner: String

    static let all: [IDEFamily] = [
        IDEFamily(vendor: "JetBrains", products: [
            "IntelliJIdea": "IntelliJ IDEA", "IdeaIC": "IntelliJ IDEA CE", "WebStorm": "WebStorm", "PyCharm": "PyCharm",
            "PyCharmCE": "PyCharm CE", "GoLand": "GoLand", "CLion": "CLion", "DataGrip": "DataGrip", "Rider": "Rider",
            "RubyMine": "RubyMine", "PhpStorm": "PhpStorm", "RustRover": "RustRover", "Aqua": "Aqua",
            "DataSpell": "DataSpell", "AppCode": "AppCode", "Writerside": "Writerside", "Fleet": "Fleet",
        ], owner: "jetbrains"),
        IDEFamily(vendor: "Google", products: ["AndroidStudio": "Android Studio"], owner: "Android Studio"),
    ]

    nonisolated(unsafe) private static let versionedFolder = try! Regex(#"([A-Za-z]+)(\d{4})\.(\d+)"#)

    /// "WebStorm2025.1" -> ("WebStorm", [2025, 1])
    static func parse(_ folder: String) -> (prefix: String, version: [Int])? {
        guard let match = try? versionedFolder.wholeMatch(in: folder) else { return nil }
        let parts = match.output.compactMap { $0.substring.map(String.init) }
        guard parts.count == 4 else { return nil }
        return (parts[1], [Int(parts[2]) ?? 0, Int(parts[3]) ?? 0])
    }

    /// Whether `rel` (relative to home) is a versioned IDE folder in Application Support, e.g. ".../JetBrains/WebStorm2024.3".
    static func isVersionedSupportFolder(_ rel: String) -> Bool {
        let parts = rel.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "Library", parts[1] == "Application Support",
              let family = all.first(where: { $0.vendor == parts[2] }),
              let parsed = parse(parts[3]) else { return false }
        return family.products[parsed.prefix] != nil
    }
}
