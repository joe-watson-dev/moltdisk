import Foundation

/// A generated folder inside a project, recognised by its name plus a marker file next to it.
struct ArtifactRule {
    let names: [String]
    /// Any one of these must exist next to the folder. "*.ext" matches any file with that extension;
    /// an empty list means the name alone is distinctive enough.
    let markers: [String]
    let ecosystem: String
    let note: String
    var safety: Safety = .safe
    var isDependency = false
    /// Only call it safe when git ignores it — names like build/dist/bin can be real source.
    var gitCheck = false
}

extension ArtifactRule {
    static let gradle = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
    static let pythonProject = ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", "tox.ini"]

    /// Checked in order; the first rule whose name and markers match wins.
    static let all: [ArtifactRule] = [
        // JavaScript / TypeScript
        ArtifactRule(names: ["node_modules"], markers: [], ecosystem: "Node", note: "restore with pnpm/npm/yarn install",
                     safety: .reinstall, isDependency: true),
        ArtifactRule(names: [".pnpm-store"], markers: ["package.json"], ecosystem: "pnpm", note: "project-local store — restored by pnpm install",
                     safety: .reinstall, isDependency: true),
        ArtifactRule(names: [".next"], markers: ["package.json"], ecosystem: "Next.js", note: "build cache — rebuilt by next dev/build"),
        ArtifactRule(names: [".turbo"], markers: ["package.json", "turbo.json"], ecosystem: "Turborepo", note: "cache — rebuilt on next run"),
        ArtifactRule(names: [".expo"], markers: ["package.json", "app.json"], ecosystem: "Expo", note: "dev cache — rebuilt on next start"),
        ArtifactRule(names: [".nuxt", ".output"], markers: ["package.json"], ecosystem: "Nuxt", note: "build output"),
        ArtifactRule(names: [".svelte-kit"], markers: ["package.json"], ecosystem: "SvelteKit", note: "build output"),
        ArtifactRule(names: [".angular"], markers: ["angular.json", "package.json"], ecosystem: "Angular", note: "build cache"),
        ArtifactRule(names: [".astro"], markers: ["package.json"], ecosystem: "Astro", note: "generated cache"),
        ArtifactRule(names: [".parcel-cache", ".vite", ".cache", ".docusaurus", ".nx", ".wrangler", ".serverless", ".vercel", ".netlify", ".eslintcache"],
                     markers: ["package.json"], ecosystem: "JavaScript", note: "tool cache — rebuilt on demand"),
        ArtifactRule(names: ["storybook-static"], markers: ["package.json"], ecosystem: "Storybook", note: "static build"),
        ArtifactRule(names: ["dist", "build", "out", "coverage"], markers: ["package.json"], ecosystem: "JavaScript",
                     note: "build output — rebuilt by the build script", gitCheck: true),

        // Python (virtualenvs and __pycache__ are detected separately)
        ArtifactRule(names: [".pytest_cache", ".mypy_cache", ".ruff_cache", ".hypothesis", ".ipynb_checkpoints", ".pytype", ".pyre"],
                     markers: [], ecosystem: "Python", note: "tool cache — rebuilt on next run"),
        ArtifactRule(names: ["htmlcov"], markers: pythonProject, ecosystem: "Python", note: "coverage report"),
        ArtifactRule(names: [".tox", ".nox"], markers: ["tox.ini", "noxfile.py", "pyproject.toml", "setup.py"], ecosystem: "Python",
                     note: "test environments — recreated by tox/nox", safety: .reinstall, isDependency: true),
        ArtifactRule(names: ["dist", "build"], markers: ["pyproject.toml", "setup.py", "setup.cfg"], ecosystem: "Python",
                     note: "package build output", gitCheck: true),

        // Java / Kotlin / Spring Boot / Android
        ArtifactRule(names: ["target"], markers: ["pom.xml"], ecosystem: "Maven", note: "build output — rebuilt by mvn package"),
        ArtifactRule(names: ["build"], markers: gradle, ecosystem: "Gradle", note: "build output — rebuilt by gradle build"),
        ArtifactRule(names: [".gradle"], markers: gradle, ecosystem: "Gradle", note: "project cache — rebuilt by Gradle"),
        ArtifactRule(names: [".kotlin"], markers: gradle, ecosystem: "Kotlin", note: "compiler cache"),
        ArtifactRule(names: [".cxx"], markers: gradle, ecosystem: "Android", note: "native build cache"),
        ArtifactRule(names: ["out"], markers: ["*.iml", ".idea"], ecosystem: "IntelliJ", note: "compiler output", gitCheck: true),

        // Rust
        ArtifactRule(names: ["target"], markers: ["Cargo.toml"], ecosystem: "Rust", note: "build output — rebuilt by cargo build"),

        // .NET
        ArtifactRule(names: ["bin", "obj"], markers: ["*.csproj", "*.fsproj", "*.vbproj"], ecosystem: ".NET",
                     note: "build output — rebuilt by dotnet build", gitCheck: true),

        // Swift / Apple
        ArtifactRule(names: [".build"], markers: ["Package.swift"], ecosystem: "SwiftPM", note: "build folder"),
        ArtifactRule(names: ["Pods"], markers: ["Podfile"], ecosystem: "CocoaPods", note: "restore with pod install",
                     safety: .reinstall, isDependency: true),
        ArtifactRule(names: ["Carthage"], markers: ["Cartfile"], ecosystem: "Carthage", note: "restore with carthage bootstrap",
                     safety: .reinstall, isDependency: true),
        ArtifactRule(names: ["DerivedData", "build"], markers: ["*.xcodeproj", "*.xcworkspace"], ecosystem: "Xcode",
                     note: "project-local build output", gitCheck: true),

        // Flutter / Dart
        ArtifactRule(names: [".dart_tool"], markers: ["pubspec.yaml"], ecosystem: "Dart", note: "restored by flutter pub get", safety: .reinstall),
        ArtifactRule(names: ["build"], markers: ["pubspec.yaml"], ecosystem: "Flutter", note: "build output — rebuilt by flutter build"),

        // PHP / Ruby
        ArtifactRule(names: ["vendor"], markers: ["composer.json"], ecosystem: "Composer", note: "restore with composer install",
                     safety: .reinstall, isDependency: true),
        ArtifactRule(names: ["tmp"], markers: ["Gemfile"], ecosystem: "Rails", note: "temp and cache files", gitCheck: true),

        // Elixir
        ArtifactRule(names: ["_build"], markers: ["mix.exs"], ecosystem: "Elixir", note: "build output — rebuilt by mix compile"),
        ArtifactRule(names: ["deps"], markers: ["mix.exs"], ecosystem: "Elixir", note: "restore with mix deps.get",
                     safety: .reinstall, isDependency: true),

        // Haskell / Zig / C / C++
        ArtifactRule(names: [".stack-work", "dist-newstyle"], markers: ["stack.yaml", "*.cabal", "cabal.project"], ecosystem: "Haskell", note: "build output"),
        ArtifactRule(names: [".zig-cache", "zig-cache", "zig-out"], markers: ["build.zig"], ecosystem: "Zig", note: "build output"),
        ArtifactRule(names: ["cmake-build-debug", "cmake-build-release"], markers: ["CMakeLists.txt"], ecosystem: "CMake",
                     note: "CLion build tree — regenerated by cmake"),
        ArtifactRule(names: ["build"], markers: ["CMakeLists.txt"], ecosystem: "CMake",
                     note: "build tree — regenerated by cmake", gitCheck: true),

        // Infra / game engines
        ArtifactRule(names: [".terraform"], markers: ["*.tf"], ecosystem: "Terraform", note: "providers and modules — restore with terraform init",
                     safety: .reinstall, isDependency: true),
        ArtifactRule(names: ["Library", "Temp", "obj"], markers: ["ProjectSettings/ProjectVersion.txt"], ecosystem: "Unity",
                     note: "regenerated when the project is reopened"),
    ]

    static let byName: [String: [ArtifactRule]] = Dictionary(grouping: all.flatMap { rule in rule.names.map { ($0, rule) } },
                                                            by: \.0).mapValues { $0.map(\.1) }
}

enum ProjectFolders {
    static let key = "projectFolders"
    static let containersKey = "includeContainerCaches"
    static let candidates = ["DEV", "Developer", "Projects", "projects", "code", "Code", "src", "Sites", "repos", "workspace", "dev", "git", "GitHub"]

    static var defaults: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var seen: Set<String> = []
        return candidates.map { home.appendingPathComponent($0) }.filter {
            // The default APFS volume is case-insensitive: "Projects" and "projects" are the same folder.
            FileManager.default.fileExists(atPath: $0.path) && seen.insert($0.resolvingSymlinksInPath().path.lowercased()).inserted
        }
    }

    /// Folders chosen in Settings, or the defaults when none are set.
    static var current: [URL] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        return saved.isEmpty ? defaults : saved.map { URL(fileURLWithPath: $0) }
    }
}

extension Scanner {
    private struct Found {
        let url: URL
        let project: URL
        let rule: ArtifactRule
    }

    private static let venvRule = ArtifactRule(names: [], markers: [], ecosystem: "Python virtualenv",
                                               note: "recreate with python -m venv / uv sync / poetry install",
                                               safety: .reinstall, isDependency: true)
    private static let pycacheRule = ArtifactRule(names: ["__pycache__"], markers: [], ecosystem: "Python",
                                                  note: "bytecode cache — recreated when the code runs")

    private func matches(_ markers: [String], in dir: URL, listings: inout [URL: [String]]) -> Bool {
        if markers.isEmpty { return true }
        for marker in markers {
            if marker.hasPrefix("*.") {
                if listings[dir] == nil { listings[dir] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] }
                let ext = String(marker.dropFirst(2))
                if listings[dir]!.contains(where: { ($0 as NSString).pathExtension == ext }) { return true }
            } else if exists(dir.appendingPathComponent(marker)) {
                return true
            }
        }
        return false
    }

    /// Nearest folder above `dir` that looks like a project root, used to group __pycache__ folders.
    private func projectRoot(above dir: URL, roots: Set<URL>, cache: inout [URL: URL]) -> URL {
        if let hit = cache[dir] { return hit }
        var current = dir
        var result = dir
        while !roots.contains(current), current.path.count > home.path.count {
            if (ArtifactRule.pythonProject + [".git"]).contains(where: { exists(current.appendingPathComponent($0)) }) {
                result = current
                break
            }
            current = current.deletingLastPathComponent()
        }
        cache[dir] = result
        return result
    }

    private func findProjectArtifacts() -> (found: [Found], pycache: [URL: [URL]]) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let roots = projectRoots.isEmpty ? ProjectFolders.defaults : projectRoots
        let rootSet = Set(roots.map(\.standardizedFileURL))
        var found: [Found] = []
        var pycache: [URL: [URL]] = [:]
        var listings: [URL: [String]] = [:]
        var rootCache: [URL: URL] = [:]
        var visitedRoots: Set<String> = []

        for root in roots where exists(root) {
            // Skip a root nested inside one already walked.
            let rootPath = root.resolvingSymlinksInPath().path
            if visitedRoots.contains(where: { rootPath == $0 || rootPath.hasPrefix($0 + "/") }) { continue }
            visitedRoots.insert(rootPath)
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
            else { continue }
            for case let dir as URL in walker {
                let values = try? dir.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if walker.level > 12 { walker.skipDescendants(); continue }
                let name = dir.lastPathComponent
                let parent = dir.deletingLastPathComponent()

                if parent.path == home.path, ["Library", "Applications", "Pictures", "Music", "Movies"].contains(name) {
                    walker.skipDescendants()
                } else if exists(dir.appendingPathComponent("pyvenv.cfg")) {
                    found.append(Found(url: dir, project: parent, rule: Self.venvRule))
                    walker.skipDescendants()
                } else if name == "__pycache__" {
                    let project = projectRoot(above: parent, roots: rootSet, cache: &rootCache)
                    pycache[project, default: []].append(dir)
                    walker.skipDescendants()
                } else if let rule = ArtifactRule.byName[name]?.first(where: { matches($0.markers, in: parent, listings: &listings) }) {
                    found.append(Found(url: dir, project: parent, rule: rule))
                    walker.skipDescendants()
                } else if name.hasSuffix(".egg-info") {
                    found.append(Found(url: dir, project: parent, rule: ArtifactRule(
                        names: [], markers: [], ecosystem: "Python", note: "package metadata — regenerated by pip install -e")))
                    walker.skipDescendants()
                } else if name.hasPrefix(".") || name == "vendor" {
                    // Hidden folders (.git, .idea…) and vendored code never hold projects worth walking.
                    walker.skipDescendants()
                }
            }
        }
        return (found, pycache)
    }

    /// Latest modification among a project's own top-level files (and its git index).
    private func projectActivity(_ dir: URL) -> Date? {
        let skip = Set(ArtifactRule.byName.keys).union([".DS_Store", ".venv", "venv", "__pycache__"])
        var latest: Date?
        for child in children(of: dir) where !skip.contains(child.lastPathComponent) {
            if let d = mtime(child), d > (latest ?? .distantPast) { latest = d }
        }
        if let d = mtime(dir.appendingPathComponent(".git/index")), d > (latest ?? .distantPast) { latest = d }
        return latest
    }

    func scanProjects() async -> [CleanItem] {
        let (found, pycache) = findProjectArtifacts()
        var activity: [URL: Date] = [:]
        func lastActive(_ project: URL) -> Date? {
            if activity[project] == nil { activity[project] = projectActivity(project) ?? .distantPast }
            return activity[project] == .distantPast ? nil : activity[project]
        }
        func describe(_ base: String, _ last: Date?) -> String {
            guard let last else { return base }
            let days = Int(Date().timeIntervalSince(last) / 86_400)
            return days >= 30 ? "\(base) · project untouched for \(days) days" : base
        }

        var items: [CleanItem] = []
        for f in found {
            var safety = f.rule.safety
            var note = "\(f.rule.ecosystem) — \(f.rule.note)"
            if f.rule.gitCheck {
                let r = await Shell.run("/usr/bin/git", ["-C", f.project.path, "check-ignore", "-q", f.url.lastPathComponent])
                if r.status != 0 {
                    safety = .review
                    note += r.status == 1 ? " · not in .gitignore, check it isn't source code" : " · not a git repo, check it's generated output"
                }
            }
            let last = lastActive(f.project)
            items.append(CleanItem(category: f.rule.isDependency ? .dependencies : .buildArtifacts,
                                   title: "\(f.project.lastPathComponent)/\(f.url.lastPathComponent)",
                                   detail: tilde(f.url), kind: .path(f.url), lastModified: last, safety: safety,
                                   note: describe(note, last), preselected: safety == .safe))
        }
        for (project, dirs) in pycache {
            let last = lastActive(project)
            items.append(CleanItem(category: .buildArtifacts,
                                   title: "\(project.lastPathComponent)/__pycache__ ×\(dirs.count)",
                                   detail: tilde(project), kind: dirs.count == 1 ? .path(dirs[0]) : .group(dirs),
                                   lastModified: last, safety: .safe,
                                   note: describe("Python — \(Self.pycacheRule.note)", last), preselected: true))
        }
        return await finalize(items)
    }
}
