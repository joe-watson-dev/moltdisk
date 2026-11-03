import AppKit
import SwiftUI

/// Chooses the folders searched for projects (dependencies and build artifacts).
struct SettingsView: View {
    @State private var folders: [String] = []
    @State private var picked: String?
    @AppStorage(ProjectFolders.containersKey) private var includeContainers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project folders").font(.headline)
            Text("MoltDisk looks inside these folders, at any depth, for node_modules, virtualenvs, build output and other project artifacts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(folders, id: \.self, selection: $picked) { path in
                Label(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
            }
            .listStyle(.bordered)
            .frame(minHeight: 180)
            HStack {
                Button("Add Folder…", systemImage: "plus") { add() }
                Button("Remove", systemImage: "minus") {
                    folders.removeAll { $0 == picked }
                    save()
                }
                .disabled(picked == nil)
                Spacer()
                Button("Reset to Defaults") {
                    folders = ProjectFolders.defaults.map(\.path)
                    UserDefaults.standard.removeObject(forKey: ProjectFolders.key)
                }
            }
            Divider().padding(.vertical, 4)
            Toggle("Include sandboxed app caches (~/Library/Containers)", isOn: $includeContainers)
            Text("Covers App Store apps such as WhatsApp or Telegram. macOS will ask once whether MoltDisk may access other apps' data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Changes apply to the next scan.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { folders = ProjectFolders.current.map(\.path) }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !folders.contains(url.path) { folders.append(url.path) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(folders, forKey: ProjectFolders.key)
    }
}
