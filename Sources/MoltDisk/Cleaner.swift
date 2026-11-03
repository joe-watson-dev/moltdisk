import AppKit

enum Cleaner {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func clean(_ items: [CleanItem], permanently: Bool) async -> [CleanResult] {
        // Re-check right before deleting: an app may have launched since the scan.
        let running = RunningApps.snapshot()
        var results: [CleanResult] = []
        for item in items {
            do {
                try await clean(item, permanently: permanently, running: running)
                results.append(CleanResult(item: item, error: nil))
            } catch {
                results.append(CleanResult(item: item, error: error.localizedDescription))
            }
        }
        return results
    }

    private static func clean(_ item: CleanItem, permanently: Bool, running: RunningApps) async throws {
        if let reason = item.blockedReason ?? running.blockedReason(owner: item.owner, process: item.ownerProcess) {
            throw Failure(message: reason)
        }
        let fm = FileManager.default
        switch item.kind {
        case .path, .group:
            let urls = item.kind.paths
            try urls.forEach(SafetyGuard.validate)
            for url in urls where fm.fileExists(atPath: url.path) {
                if permanently {
                    try fm.removeItem(at: url)
                } else {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                }
            }
        case .simDevice(let udid):
            try await simctl(["delete", udid])
        case .simRuntime(let id):
            try await simctl(["runtime", "delete", id])
        case .app(let bundle, let bundleID, let name, let files):
            // Everything is checked before anything moves; the app goes first so a failure (e.g. an app
            // installed by an admin) leaves its settings in place.
            try SafetyGuard.validateUninstall(bundle: bundle, bundleID: bundleID, name: name, files: files)
            if let bundle, fm.fileExists(atPath: bundle.path) {
                if permanently {
                    try fm.removeItem(at: bundle)
                } else {
                    try await recycle(bundle)
                }
            }
            // Keep going past a file that can't be moved, then say exactly what is left and why.
            var left: [String] = []
            var needsFullDiskAccess = false
            for url in files where fm.fileExists(atPath: url.path) {
                do {
                    if permanently {
                        try fm.removeItem(at: url)
                    } else {
                        try fm.trashItem(at: url, resultingItemURL: nil)
                    }
                } catch {
                    left.append(url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent)
                    // macOS guards other apps' containers; removing them needs Full Disk Access.
                    if url.path.contains("/Library/Containers/") || url.path.contains("/Library/Group Containers/") {
                        needsFullDiskAccess = true
                    }
                }
            }
            if !left.isEmpty {
                let what = left.count == 1 ? left[0] : "\(left.count) items (\(left.prefix(2).joined(separator: ", "))…)"
                let fix = needsFullDiskAccess
                    ? " Give MoltDisk Full Disk Access in System Settings › Privacy & Security, then rescan to remove the rest."
                    : ""
                throw Failure(message: (bundle == nil ? "Removed part of the leftovers; " : "App removed; ") + "\(what) could not be moved.\(fix)")
            }
        case .emptyTrash(let trash):
            guard trash.standardizedFileURL.path == SafetyGuard.home + "/.Trash" else {
                throw Failure(message: "Refused: \(trash.path) is not your Trash")
            }
            for name in try fm.contentsOfDirectory(atPath: trash.path) {
                try fm.removeItem(at: trash.appendingPathComponent(name))
            }
        }
    }

    /// Moves an app to the Trash through the Finder, which asks for an admin password when the app needs one.
    @MainActor
    private static func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func simctl(_ args: [String]) async throws {
        let result = await Shell.xcrun(["simctl"] + args, includeStderr: true)
        guard result.status == 0 else {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message.isEmpty ? "simctl exited with \(result.status)" : message)
        }
    }
}
