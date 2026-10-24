import AppKit

/// Opt-in end-to-end check, driven through the same Store calls the buttons use:
///   DISKSWEEP_SELFTEST=/path/to/item (or an item title) DISKSWEEP_SNAPSHOTS=/some/dir DiskSweep
/// Scans, checks only that item, opens the confirmation sheet, moves it to the Trash,
/// saves a PNG of the window at each step, prints the outcome and quits.
@MainActor
enum SelfTest {
    static func runIfRequested(_ store: Store) {
        let env = ProcessInfo.processInfo.environment
        guard let target = env["DISKSWEEP_SELFTEST"] else { return }
        let shots = URL(fileURLWithPath: env["DISKSWEEP_SNAPSHOTS"] ?? NSTemporaryDirectory())
        Task {
            try? await Task.sleep(for: .seconds(1))
            NSApp.windows.first { $0.isVisible }?.setContentSize(NSSize(width: 1440, height: 900))
            store.scan()
            while store.isScanning { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            snapshot(shots.appendingPathComponent("1-scan.png"))

            let id = URL(fileURLWithPath: target).standardizedFileURL.path
            guard let item = store.items.first(where: { $0.id == id || $0.title == target }) else {
                print("SELFTEST FAIL: \(id) not found in scan")
                finish()
                return
            }
            print("SELFTEST found \(item.title) \(formatBytes(item.size)) [\(item.category.rawValue), \(item.safety.label)]")
            // Open the item's own section and tick only it there; ticks in other sections stay,
            // and must not be cleaned from this view.
            store.view = item.group.map { .group(item.category, $0) } ?? .category(item.category)
            store.select(store.visibleItems) { $0.id == item.id }
            print("SELFTEST view \(store.view.title): \(store.selectedItems.count) selected here, \(store.hiddenSelectionCount) ticked elsewhere")
            store.deletePermanently = false
            store.openConfirm()
            try? await Task.sleep(for: .seconds(1))
            snapshot(shots.appendingPathComponent("2-confirm.png"))

            await store.clean()
            try? await Task.sleep(for: .seconds(1))
            snapshot(shots.appendingPathComponent("3-result.png"))
            for r in store.results { print("SELFTEST result \(r.item.title): \(r.error ?? "OK")") }
            print("SELFTEST still ticked elsewhere after clean: \(store.hiddenSelectionCount)")
            print("SELFTEST exists after clean: \(FileManager.default.fileExists(atPath: id))")
            finish()
        }
    }

    private static func finish() {
        fflush(stdout)
        exit(0)
    }

    /// Renders the app's own windows (sheet included) without needing Screen Recording access.
    static func snapshot(_ url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let sheet = window.attachedSheet, let sheetView = sheet.contentView,
           let sheetRep = sheetView.bitmapImageRepForCachingDisplay(in: sheetView.bounds) {
            sheetView.cacheDisplay(in: sheetView.bounds, to: sheetRep)
            try? sheetRep.representation(using: .png, properties: [:])?
                .write(to: url.deletingPathExtension().appendingPathExtension("sheet.png"))
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
