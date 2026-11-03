import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum Entry {
    /// The app used to be called DiskSweep: keep its saved extension-usage history.
    static func migrateFromDiskSweep() {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let old = support.appendingPathComponent("DiskSweep"), new = support.appendingPathComponent("MoltDisk")
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    static func main() {
        migrateFromDiskSweep()
        if CommandLine.arguments.contains("--check-guard") {
            Report.checkGuard()
        } else if CommandLine.arguments.contains("--report") {
            Report.run()
        } else {
            MoltDiskApp.main()
        }
    }
}

/// `MoltDisk --report` prints the scan to the terminal without opening a window.
enum Report {
    /// `--check-guard`: prints which sample paths SafetyGuard allows.
    static func checkGuard() {
        let cases: [(String, Bool)] = [
            ("Library/Application Support/Slack/Code Cache", true),
            ("Library/Application Support/Slack/Service Worker/CacheStorage", true),
            ("Library/Application Support/Google/Chrome/Default/GPUCache", true),
            ("Library/Application Support/Claude/Code Cache", false),
            ("Library/Application Support/Claude/Partitions/x/Cache", false),
            ("Library/Application Support/Slack/Cookies", false),
            ("Library/Application Support/Slack/Cache/../Local Storage", false),
            ("Library/Application Support/Code Cache", false),
            ("Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches", true),
            ("Library/Containers/net.whatsapp.WhatsApp/Data/Documents", false),
            ("Library/Caches/com.foo.app", true),
            ("Library/Application Support/JetBrains/WebStorm2024.3", true),
            ("Library/Application Support/JetBrains/Toolbox", false),
            ("Library/Application Support/JetBrains/WebStorm2024.3/options", false),
            ("Library/Application Support/Cursor/CachedData", true),
            ("Library/Application Support/Cursor/User", false),
            ("Library/Application Support/Google/AndroidStudio2024.2", true),
            ("Library/Application Support/Google/Chrome", false),
            ("Documents/Cache", false),
        ]
        var ok = true
        for (rel, expected) in cases {
            let allowed = SafetyGuard.isAllowed(URL(fileURLWithPath: SafetyGuard.home + "/" + rel))
            if allowed != expected { ok = false }
            print("\(allowed == expected ? "PASS" : "FAIL")  \(allowed ? "allow " : "refuse")  ~/\(rel)")
        }
        // Uninstall rule: (bundle ID or developer prefix, app name, file under ~, bundle present?, expected).
        let uninstall: [(String, String, String, Bool, Bool)] = [
            ("com.foo.app", "Foo", "Library/Preferences/com.foo.app.plist", false, true),
            ("com.foo.app", "Foo", "Library/Preferences/ByHost/com.foo.app.1234-ABCD.plist", false, true),
            ("com.foo.app", "Foo", "Library/Containers/com.foo.app.ShareExtension", false, true),
            ("com.foo.app", "Foo", "Library/Group Containers/ABCDE12345.com.foo.app", false, true),
            ("com.foo.app", "Foo", "Library/Application Scripts/ABCDE12345.group.com.foo.app", false, true),
            ("com.foo", "", "Library/Caches/com.foo.helper", false, true),
            ("com.foo.app", "Foo", "Library/Preferences/com.foobar.plist", false, false),
            ("com.foo.app", "Foo", "Library/Containers/com.foo.app/Data/Documents", false, false),
            ("com.foo.app", "Foo", "Library/Application Support/Foo", false, false),
            ("com.foo.app", "Foo", "Library/Keychains/com.foo.app", false, false),
            ("com.foo.app", "Foo", "Documents/com.foo.app", false, false),
            ("com.apple.mail", "Mail", "Library/Containers/com.apple.mail", false, false),
            ("com.apple", "", "Library/Application Scripts/group.com.apple.Maps", false, false),
            ("group.com", "", "Library/Application Scripts/group.com.apple.Maps", false, false),
            ("developer.apple", "", "Library/HTTPStorages/developer.apple.wwdc-Release", false, false),
            ("is.workflow", "", "Library/Application Scripts/group.is.workflow.shortcuts", false, false),
            ("com.anthropic.claudefordesktop", "Claude", "Library/Application Support/Claude", false, false),
        ]
        for (id, name, rel, _, expected) in uninstall {
            let file = URL(fileURLWithPath: SafetyGuard.home + "/" + rel)
            let allowed = (try? SafetyGuard.validateUninstall(bundle: nil, bundleID: id, name: name, files: [file])) != nil
            if allowed != expected { ok = false }
            print("\(allowed == expected ? "PASS" : "FAIL")  \(allowed ? "allow " : "refuse")  uninstall \(id): ~/\(rel)")
        }
        // An app bundle outside an Applications folder is always refused.
        let mailApp = (try? SafetyGuard.validateUninstall(bundle: URL(fileURLWithPath: "/System/Applications/Mail.app"),
                                                          bundleID: "com.apple.mail", name: "Mail", files: [])) != nil
        if mailApp { ok = false }
        print("\(mailApp ? "FAIL" : "PASS")  \(mailApp ? "allow " : "refuse")  uninstall /System/Applications/Mail.app")
        print(ok ? "All guard checks passed" : "GUARD CHECK FAILED")
    }

    static func run() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            // `--root <folder>` (repeatable) overrides the project folders.
            let args = CommandLine.arguments
            let roots = args.indices.filter { args[$0] == "--root" && $0 + 1 < args.count }.map { URL(fileURLWithPath: args[$0 + 1]) }
            let scanner = Scanner(running: RunningApps.snapshot(), projectRoots: roots.isEmpty ? ProjectFolders.current : roots,
                                  includeContainers: args.contains("--containers"))
            var all: [CleanItem] = []
            await withTaskGroup(of: [CleanItem].self) { group in
                for job in scanner.jobs { group.addTask { await job.run() } }
                for await found in group { all += found }
            }
            for category in Category.allCases {
                let rows = all.filter { $0.category == category }.sorted { $0.size > $1.size }
                print("\n== \(category.rawValue): \(formatBytes(rows.reduce(0) { $0 + $1.size })) (\(rows.count) items)")
                for item in rows.prefix(args.contains("--all") ? rows.count : 12) {
                    let status = item.blockedReason.map { "LOCKED: \($0)" } ?? item.safety.label
                    print("  \(formatBytes(item.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.group.map { "[\($0)] " } ?? "")\(item.title) — \(status)")
                }
            }
            print("\nTotal: \(formatBytes(all.reduce(0) { $0 + $1.size }))")
            done.signal()
        }
        done.wait()
    }
}

struct MoltDiskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()

    var body: some Scene {
        WindowGroup("MoltDisk") {
            ContentView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { SelfTest.runIfRequested(store) }
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}
