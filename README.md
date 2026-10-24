<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="DiskSweep icon">
</p>

<h1 align="center">DiskSweep</h1>

<p align="center"><b>The Mac cleaner made for developers.</b><br>
Find the space your dev tools quietly eat, and clean it safely.</p>

<p align="center">macOS 15 or later · Apple silicon · native SwiftUI<br>
<a href="https://disksweep.vercel.app">disksweep.vercel.app</a></p>

![DiskSweep showing VS Code extensions with sizes, last activity and labels like In use and Not used recently](marketing/screenshot-vscode-full.png)

DiskSweep scans a developer Mac for reclaimable space (`node_modules` and build folders in any language, package caches, Xcode data, old simulators, unused editor extensions, app caches, logs) and groups it by category with sizes and a safety label on every item. It deletes only what you tick, after a confirmation sheet showing the total, and moves things to the Trash by default.

## Highlights

- **Every project, every language.** JS, Python, Java/Spring, Rust, .NET, Swift, Flutter, Elixir and more. Generic names like `build` or `dist` only count when the project file next to them proves it.
- **Old simulators and runtimes**, removed with `xcrun simctl`, the way Xcode does it.
- **Editor extensions by real use.** VS Code, Cursor, Windsurf, Antigravity, Kiro and other VS Code-based editors, plus JetBrains IDEs. Extensions you used recently are locked.
- **Running apps stay locked.** Caches of open apps can't be ticked, and DiskSweep checks again right before it deletes.
- **Trash first.** Permanent delete is an explicit checkbox.

## Install

Download `DiskSweep.zip` from [Releases](https://github.com/joe-watson-sbf/disk-sweep/releases), unzip it and move `DiskSweep.app` to Applications.

The app is ad-hoc signed, not notarized, so the first time macOS will block it: open **System Settings › Privacy & Security** and click **Open Anyway**. To read the Trash and some caches, grant **Full Disk Access** in System Settings › Privacy & Security.

## Build from source

```bash
./scripts/build-app.sh          # builds build/DiskSweep.app (release, ad-hoc signed)
open build/DiskSweep.app
```

Or open `Package.swift` in Xcode and press Run. `swift run DiskSweep` works too.

`swift run DiskSweep --report` prints the scan to the terminal without opening a window.

The app icon (a broom sweeping a drive) is drawn in code by `scripts/make-icon.swift`, which writes `Resources/AppIcon.icns`; `build-app.sh` bundles it. Rerun the script after tweaking colors or shapes.

## What it scans

| Category | Where | Label |
|---|---|---|
| Dependencies | `node_modules`, Python virtualenvs (any folder with `pyvenv.cfg`), Composer `vendor`, `Pods`, Carthage, Elixir `deps`, `.tox`, `.terraform`, project-local `.pnpm-store` | Will need reinstall |
| Build artifacts | JS (`.next`, `.turbo`, `.expo`, `.nuxt`, `.svelte-kit`, `.angular`, `dist`, `build`, `out`, `coverage`…), Python (`__pycache__` grouped per project, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `*.egg-info`, `dist`), Java/Spring Boot (Maven `target`, Gradle `build` + `.gradle`), Rust `target`, .NET `bin`/`obj`, SwiftPM `.build`, Xcode, Flutter `build` + `.dart_tool`, Elixir `_build`, Haskell, Zig, CMake, Rails `tmp`, Unity `Library`/`Temp` | Safe, or Review first when a generic name like `build`/`bin` isn't gitignored |
| Xcode | DerivedData, Archives, DeviceSupport, SwiftUI Previews | Safe / Review |
| Package caches | npm, npx, pnpm (old store versions; the live store is locked), Yarn, Bun, Homebrew, CocoaPods, Gradle, Maven `~/.m2`, NuGet, pub, Composer, Go modules, Cargo, pip, SwiftPM, Deno, `~/.cache/*` | Safe |
| iOS Simulators | devices and runtimes from `xcrun simctl` | Will need reinstall (unavailable devices: Safe) |
| Editors & IDEs | Each editor found on the Mac gets its own sidebar entry. **VS Code family** (VS Code, Insiders, VSCodium, Cursor, Windsurf, Antigravity, Kiro, Trae, Positron, Void): every extension with its real name and whether you use it (see below), old duplicate versions, editor caches. **JetBrains** (IntelliJ, WebStorm, PyCharm, GoLand, Rider…) and **Android Studio**: old versions left after upgrades (caches + settings + plugins + logs), plus the current version's caches and logs. The current version's settings are never offered | Locked / Not used recently / Review / Safe |
| App caches | `~/Library/Caches/*`, Chrome/Brave/Edge/Arc and Electron app caches (Slack, Discord, Cursor, Notion…) inside Application Support, optionally sandboxed app caches in `~/Library/Containers` (Settings) | Safe (`com.apple.*`: Review) |
| Logs | `~/Library/Logs/*` | Safe |
| Large downloads | items over 100 MB in `~/Downloads` | Review |
| Trash | `~/.Trash` (needs Full Disk Access to read) | Review |

Projects are searched in `~/DEV`, `~/Developer`, `~/Projects`, `~/code`… by default; change them in **Settings › Project folders** (⌘,).

### How extension usage is detected (VS Code, Cursor, Windsurf, Antigravity…)

- **Activations:** VS Code's extension-host logs record each extension it activates and why. DiskSweep saves them per editor in `~/Library/Application Support/DiskSweep/` (e.g. `vscode-usage.json`, `cursor-usage.json`), so the history keeps growing after VS Code rotates its logs.
- **Storage:** activity in each extension's `globalStorage` and `workspaceStorage` folders also counts as use.
- **Locked:** extensions used in the last 30 days, installed in the last 14 days, needed by an extension you use, or providing your active color/icon theme.
- **Review first:** extensions that load at every VS Code startup (so real use can't be told apart), and snippet/grammar/theme-only extensions (VS Code never logs those).
- **Not used recently:** no activation and no storage activity in 30 days. Use **Select › Not used recently** to tick them all.

## Selection

Cleaning only acts on items ticked **in the section you're viewing**. Ticks you made in other sections stay, but are never included; the bottom bar shows how many there are. Overview shows everything, so cleaning from Overview includes every ticked item.

## Safety

- **Trash by default.** Items are moved to the Trash; "Delete permanently" is an explicit checkbox.
- **Simulators** are removed with `xcrun simctl delete` / `simctl runtime delete`, never `rm`.
- **Running apps are locked.** Caches, logs and data whose owner app is running (matched by bundle ID or name) show as *In use* and can't be selected. This is checked again just before deleting. Booted simulators and the live pnpm store are locked too.
- **Hard guard (`SafetyGuard`).** Every path is checked right before deletion: it must be inside your home folder and at least two levels deep. `~/Library/Application Support` (Claude always), Containers, Group Containers, iCloud Drive, Keychains, Preferences, Documents, Desktop, Pictures, `.ssh` and `.config` are refused. The only exceptions are Chromium/Electron cache folders (`Cache`, `Code Cache`, `GPUCache`, `Service Worker/CacheStorage`…) and a sandboxed app's `Data/Library/Caches`. `DiskSweep --check-guard` prints the guard's decisions for sample paths.

## Not covered

- `/Library/Developer/CoreSimulator` (root-owned simulator volumes and dyld caches). Removing the runtime through the app frees the runtime image itself.
- Homebrew under `/opt/homebrew`: use `brew cleanup` / `brew autoremove`.

## Self-test

```bash
DISKSWEEP_SELFTEST=/path/to/some/node_modules DISKSWEEP_SNAPSHOTS=/tmp/shots build/DiskSweep.app/Contents/MacOS/DiskSweep
```

This scans, ticks only that item, opens the confirmation sheet, moves the item to the Trash through the same `Store.clean()` call the button uses, saves a PNG of the window at each step and quits.

## Project layout

| Path | What |
|---|---|
| `Sources/DiskSweep/` | The app: scanners, safety guard, cleaner, SwiftUI views |
| `Resources/` | App icon |
| `scripts/` | App build script, icon and marketing image generators |
| `landing/` | Product landing page (static HTML) |
| `marketing/` | Screenshot and promo images |
