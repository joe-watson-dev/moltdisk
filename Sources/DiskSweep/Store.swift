import Foundation
import Observation

@MainActor
@Observable
final class Store {
    var items: [CleanItem] = []
    var selection: Set<String> = []
    var scanning: Set<Category> = []
    var hasScanned = false
    var deletePermanently = false
    var isCleaning = false
    var results: [CleanResult] = []
    var freeSpace: Int64 = 0
    var showConfirm = false
    /// The confirmation sheet switches to its results view once a clean has run.
    var cleanFinished = false
    /// The sidebar section on screen. Selection counts, the confirmation sheet and cleaning only use its items.
    var view: SidebarEntry = .overview
    var scanStarted: Date?
    var scanDuration: TimeInterval?

    init() { refreshFreeSpace() }

    var isScanning: Bool { !scanning.isEmpty }

    var visibleItems: [CleanItem] { items(in: view) }
    /// Ticked items in the current section only — what Clean will act on.
    var selectedItems: [CleanItem] { visibleItems.filter { selection.contains($0.id) && $0.isSelectable } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    /// Items ticked in other sections; shown as a hint, never cleaned from here.
    var hiddenSelectionCount: Int {
        items.filter { selection.contains($0.id) && $0.isSelectable && !view.contains($0) }.count
    }

    func items(in entry: SidebarEntry) -> [CleanItem] { items.filter(entry.contains) }

    func total(_ entry: SidebarEntry) -> Int64 { items(in: entry).reduce(0) { $0 + $1.size } }

    /// Sub-sections of a category (e.g. each detected editor), largest first.
    func groups(in category: Category) -> [String] {
        let names = Set(items.filter { $0.category == category }.compactMap(\.group))
        return names.sorted { total(.group(category, $0)) > total(.group(category, $1)) }
    }

    func scan() {
        guard !isScanning else { return }
        items = []
        selection = []
        results = []
        hasScanned = true
        scanStarted = Date()
        scanDuration = nil
        let scanner = Scanner(running: RunningApps.snapshot(), projectRoots: ProjectFolders.current,
                              includeContainers: UserDefaults.standard.bool(forKey: ProjectFolders.containersKey))
        scanning = Set(Category.allCases)
        for job in scanner.jobs {
            Task {
                let found = await job.run()
                items.append(contentsOf: found)
                selection.formUnion(found.filter { $0.preselected && $0.isSelectable }.map(\.id))
                scanning.subtract(job.categories)
                if scanning.isEmpty, let start = scanStarted { scanDuration = Date().timeIntervalSince(start) }
            }
        }
    }

    func isSelected(_ item: CleanItem) -> Bool { selection.contains(item.id) }

    func setSelected(_ item: CleanItem, _ on: Bool) {
        guard item.isSelectable else { return }
        if on { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    func select(_ items: [CleanItem], where predicate: (CleanItem) -> Bool) {
        for item in items where item.isSelectable {
            if predicate(item) { selection.insert(item.id) } else { selection.remove(item.id) }
        }
    }

    func openConfirm() {
        cleanFinished = false
        showConfirm = true
    }

    func clean() async {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        isCleaning = true
        results = await Cleaner.clean(targets, permanently: deletePermanently)
        let removed = Set(results.filter { $0.error == nil }.map(\.id))
        items.removeAll { removed.contains($0.id) }
        selection.subtract(removed)
        isCleaning = false
        cleanFinished = true
        refreshFreeSpace()
    }

    func refreshFreeSpace() {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeSpace = values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
