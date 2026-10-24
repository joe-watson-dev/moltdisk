import Foundation

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
        case .emptyTrash(let trash):
            guard trash.standardizedFileURL.path == SafetyGuard.home + "/.Trash" else {
                throw Failure(message: "Refused: \(trash.path) is not your Trash")
            }
            for name in try fm.contentsOfDirectory(atPath: trash.path) {
                try fm.removeItem(at: trash.appendingPathComponent(name))
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
