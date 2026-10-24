import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let sidebar = Binding<SidebarEntry?>(get: { store.view }, set: { if let entry = $0 { store.view = entry } })
        NavigationSplitView {
            List(selection: sidebar) {
                SidebarRow(title: "Overview", symbol: "internaldrive", size: store.total(.overview),
                           scanning: store.isScanning)
                    .tag(SidebarEntry.overview)
                Section("Categories") {
                    ForEach(Category.allCases) { c in
                        SidebarRow(title: c.rawValue, symbol: c.symbol, size: store.total(.category(c)),
                                   scanning: store.scanning.contains(c))
                            .tag(SidebarEntry.category(c))
                        ForEach(store.groups(in: c), id: \.self) { name in
                            SidebarRow(title: name, symbol: "app.badge", size: store.total(.group(c, name)), scanning: false)
                                .padding(.leading, 22)
                                .tag(SidebarEntry.group(c, name))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            if store.hasScanned {
                ItemsView(entry: store.view)
                    .safeAreaInset(edge: .bottom) { CleanBar() }
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("\(formatBytes(store.freeSpace)) free")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Project Folders", systemImage: "folder.badge.gearshape")
                }
                .help("Choose which folders are scanned for projects")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.scan()
                } label: {
                    Label(store.hasScanned ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning || store.isCleaning)
                .keyboardShortcut("r")
            }
        }
        .sheet(isPresented: $store.showConfirm) { ConfirmSheet() }
        .onAppear {
            // Self-test hook: open on a category or editor, e.g. DISKSWEEP_SIDEBAR="VS Code".
            if let name = ProcessInfo.processInfo.environment["DISKSWEEP_SIDEBAR"] {
                store.view = Category(rawValue: name).map { .category($0) } ?? .group(.editors, name)
            }
        }
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let size: Int64
    let scanning: Bool

    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                // Brand teal keeps the icons readable on the sidebar in both light and dark mode.
                Image(systemName: symbol).foregroundStyle(Color(red: 0.18, green: 0.83, blue: 0.75))
            }
            Spacer()
            if scanning {
                ProgressView().controlSize(.small)
            } else {
                Text(size > 0 ? formatBytes(size) : "—")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Find reclaimable space")
                .font(.title2.weight(.semibold))
            Text("Scans project dependencies, build output, developer caches, simulators, logs, Downloads and the Trash.\nNothing is deleted until you confirm.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Scan My Mac") { store.scan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Text("Projects are searched in " + ProjectFolders.current.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsLink { Text("Change project folders…") }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ItemsView: View {
    @Environment(Store.self) private var store
    let entry: SidebarEntry
    @State private var sortOrder = [KeyPathComparator(\CleanItem.size, order: .reverse)]
    @State private var highlighted: Set<String> = []

    var body: some View {
        let rows = store.items(in: entry).sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 0) {
            header(rows)
            Divider()
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(store.isScanning ? "Scanning…" : "Nothing found", systemImage: entry.symbol)
                } description: {
                    Text(store.isScanning ? "Sizes appear as each category finishes." : "Nothing reclaimable here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table(rows)
            }
        }
    }

    private func header(_ rows: [CleanItem]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.title2.weight(.semibold))
                Text(entry.blurb ?? summary(rows))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            Text(formatBytes(rows.reduce(0) { $0 + $1.size }))
                .font(.title2.weight(.medium))
                .monospacedDigit()
            Menu("Select") {
                Button("Safe items") { store.select(rows) { $0.safety == .safe } }
                Button("Not used recently") { store.select(rows) { $0.safety == .unused } }
                Button("All") { store.select(rows) { _ in true } }
                Button("None") { store.select(rows) { _ in false } }
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func summary(_ rows: [CleanItem]) -> String {
        var text = "\(rows.count) items found"
        if let d = store.scanDuration { text += " in \(Int(d.rounded())) s" }
        return text + ". Locked items belong to running apps."
    }

    private func table(_ rows: [CleanItem]) -> some View {
        Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(get: { store.isSelected(item) }, set: { store.setSelected(item, $0) }))
                    .labelsHidden()
                    .disabled(!item.isSelectable)
            }
            .width(22)
            TableColumn("Name", value: \.title) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).lineLimit(1)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(item.note ?? item.detail)
            }
            .width(min: 220, ideal: 360)
            if entry == .overview {
                TableColumn("Category", value: \.categoryName) { item in
                    Label(item.category.rawValue, systemImage: item.category.symbol)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 140)
            }
            TableColumn("Size", value: \.size) { item in
                Text(formatBytes(item.size))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Last Activity", value: \.sortDate) { item in
                Text(item.lastModified.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Status", value: \.safetyRank) { item in
                StatusBadge(item: item)
            }
            .width(min: 130, ideal: 160)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let picked = rows.filter { ids.contains($0.id) }
            Button("Check") { picked.forEach { store.setSelected($0, true) } }
            Button("Uncheck") { picked.forEach { store.setSelected($0, false) } }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(picked.compactMap { $0.kind.url })
            }
            .disabled(picked.allSatisfy { $0.kind.url == nil })
        } primaryAction: { ids in
            for item in rows where ids.contains(item.id) { store.setSelected(item, !store.isSelected(item)) }
        }
    }
}

struct StatusBadge: View {
    let item: CleanItem

    var body: some View {
        Group {
            if let reason = item.blockedReason {
                Label("In use", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(reason)
            } else {
                Label(item.safety.label, systemImage: item.safety.symbol)
                    .foregroundStyle(item.safety.color)
                    .help(item.note ?? item.safety.label)
            }
        }
        .font(.callout)
        .lineLimit(1)
    }
}

struct CleanBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.selectedItems.count) selected in \(store.view.title)").font(.headline)
                Text(formatBytes(store.selectedSize)).monospacedDigit().foregroundStyle(.secondary)
            }
            if store.hiddenSelectionCount > 0 {
                Label("\(store.hiddenSelectionCount) ticked in other sections won't be touched", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Only items ticked in the section you're viewing are cleaned. Overview shows everything.")
            }
            if let failed = store.results.filter({ $0.error != nil }).count as Int?, !store.results.isEmpty {
                let freed = store.results.filter { $0.error == nil }.reduce(0) { $0 + $1.item.size }
                Text("Last clean: freed \(formatBytes(freed))" + (failed > 0 ? ", \(failed) failed" : ""))
                    .font(.callout)
                    .foregroundStyle(failed > 0 ? .orange : .secondary)
            }
            Spacer()
            Toggle("Delete permanently (skip Trash)", isOn: $store.deletePermanently)
                .toggleStyle(.checkbox)
            Button(store.deletePermanently ? "Delete…" : "Move to Trash…") { store.openConfirm() }
                .buttonStyle(.borderedProminent)
                .tint(store.deletePermanently ? .red : .accentColor)
                .disabled(store.selectedItems.isEmpty || store.isScanning || store.isCleaning)
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct ConfirmSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.cleanFinished {
                resultsView
            } else {
                confirmView
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
    }

    private var confirmView: some View {
        let items = store.selectedItems.sorted { $0.size > $1.size }
        let total = items.reduce(0) { $0 + $1.size }
        let reinstall = items.filter { $0.safety == .reinstall }.count
        let review = items.filter { $0.safety == .review }.count
        let simItems = items.filter { $0.kind.paths.isEmpty || $0.category == .trash }.count
        return VStack(alignment: .leading, spacing: 14) {
            let source = store.view == .overview ? "" : " from \(store.view.title)"
            Text(store.deletePermanently ? "Permanently delete \(items.count) items\(source)?" : "Move \(items.count) items\(source) to the Trash?")
                .font(.title2.weight(.semibold))
            Text("This frees about \(formatBytes(total)).")
                .font(.title3)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 6) {
                if store.deletePermanently {
                    warning("Permanent: these items will not go to the Trash and can't be recovered.", .red)
                }
                if simItems > 0 {
                    warning("Simulators, runtimes and the Trash are removed with simctl or emptied directly — they never go to the Trash.", .orange)
                }
                if reinstall > 0 { warning("\(reinstall) items will need a reinstall or re-download.", .orange) }
                if review > 0 { warning("\(review) items are marked Review first.", .red) }
            }
            List(items) { item in
                HStack {
                    Image(systemName: item.category.symbol).foregroundStyle(.secondary).frame(width: 18)
                    VStack(alignment: .leading) {
                        Text(item.title).lineLimit(1)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(formatBytes(item.size)).monospacedDigit()
                }
            }
            .listStyle(.bordered)
            HStack {
                if store.isCleaning {
                    ProgressView().controlSize(.small)
                    Text("Cleaning…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isCleaning)
                Button(store.deletePermanently ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                    Task { await store.clean() }
                }
                .buttonStyle(.borderedProminent)
                .tint(store.deletePermanently ? .red : .accentColor)
                .keyboardShortcut(.defaultAction)
                .disabled(store.isCleaning)
            }
        }
    }

    private var resultsView: some View {
        let ok = store.results.filter { $0.error == nil }
        let failed = store.results.filter { $0.error != nil }
        return VStack(alignment: .leading, spacing: 14) {
            Label("Freed \(formatBytes(ok.reduce(0) { $0 + $1.item.size }))", systemImage: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
            Text("\(ok.count) items removed. \(formatBytes(store.freeSpace)) now free.")
                .foregroundStyle(.secondary)
            if !failed.isEmpty {
                Text("\(failed.count) items could not be removed").font(.headline)
                List(failed) { r in
                    VStack(alignment: .leading) {
                        Text(r.item.title)
                        Text(r.error ?? "").font(.caption).foregroundStyle(.red)
                    }
                }
                .listStyle(.bordered)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func warning(_ text: String, _ color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(color)
            .font(.callout)
    }
}
