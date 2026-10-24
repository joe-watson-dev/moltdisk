import Foundation

enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    static func runSync(_ executable: String, _ args: [String], includeStderr: Bool = false) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = includeStderr ? out : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        // Read before waiting so large outputs can't fill the pipe and deadlock.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a process on a GCD thread so the Swift concurrency pool never blocks on it.
    static func run(_ executable: String, _ args: [String], includeStderr: Bool = false) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(executable, args, includeStderr: includeStderr))
            }
        }
    }

    static func xcrun(_ args: [String], includeStderr: Bool = false) async -> Result {
        await run("/usr/bin/xcrun", args, includeStderr: includeStderr)
    }

    /// Allocated size on disk, via `du` (doesn't follow symlinks, counts hard links once).
    static func diskUsage(_ url: URL) async -> Int64 {
        let result = await run("/usr/bin/du", ["-skx", url.path])
        let first = result.output.split(separator: "\t").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (first.flatMap { Int64($0) } ?? 0) * 1024
    }

    static func diskUsage(of urls: [URL], maxConcurrent: Int = 8) async -> [URL: Int64] {
        var sizes: [URL: Int64] = [:]
        await withTaskGroup(of: (URL, Int64).self) { group in
            var pending = urls.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let url = pending.next() else { break }
                group.addTask { (url, await diskUsage(url)) }
            }
            while let (url, size) = await group.next() {
                sizes[url] = size
                if let next = pending.next() {
                    group.addTask { (next, await diskUsage(next)) }
                }
            }
        }
        return sizes
    }
}
