# MoltDisk Safety Boundaries

What MoltDisk will and won't delete, where those rules live in the code, and the known limitations.
Report anything that gets past these rules privately, as described in [SECURITY.md](SECURITY.md).

## Summary

- Nothing is deleted without the user ticking it and confirming a sheet that shows the total.
- Items move to the Trash by default; permanent deletion is an explicit checkbox.
- Every path is checked by `SafetyGuard` (`Sources/MoltDisk/Safety.swift`) right before it is removed, not only
  when it is scanned.
- Data of running apps is locked, and checked again right before deletion.
- Only the items ticked in the section on screen are acted on.
- Apps are never part of Overview, so selecting everything there can't uninstall an app.

## Threat Surface

| Area | Risk | Control |
|---|---|---|
| File deletion | Removing personal files or another app's data | `SafetyGuard.validate`, run in `Cleaner` before each removal |
| App uninstall | Removing the wrong app, Apple's apps or unrelated Library files | `SafetyGuard.validateUninstall` (rules below) |
| Scanning projects | A cloned repository running code when git is invoked | Hardened `git check-ignore` (below) |
| Running apps | Deleting caches an app is using | `RunningApps` snapshot at scan time and again before cleaning |
| Simulators | Corrupting Xcode's simulator state with `rm` | Removed only with `xcrun simctl delete` / `simctl runtime delete` |
| Install script and releases | Tampered downloads | Releases built by GitHub Actions from `main`; `install.sh` downloads only from this repository's releases over HTTPS |

## Cleanup Rules (`SafetyGuard.validate`)

A path is refused unless all of these hold:

1. It is inside the user's home folder and at least two levels deep.
2. It is not under `~/Library/Application Support/Claude` (always refused).
3. It is not under a protected location, unless it matches an exception below:
   `Library/Application Support`, `Library/Containers`, `Library/Group Containers`, `Library/Mobile Documents`,
   `Library/Keychains`, `Library/Mail`, `Library/Messages`, `Library/Preferences`, `Library/CloudStorage`,
   `Documents`, `Desktop`, `Pictures`, `Movies`, `Music`, `.ssh`, `.gnupg`, `.config`.

Exceptions inside protected locations, matched exactly:

- Chromium and Electron cache folders inside Application Support (`Cache`, `Code Cache`, `GPUCache`,
  `Service Worker/CacheStorage` and similar) inside an app's own folder, never the app folder itself.
- VS Code-family editor cache folders (`Cache`, `CachedData`, `CachedExtensionVSIXs`, `Code Cache`, `GPUCache`…).
- A sandboxed app's cache folder: `Library/Containers/<id>/Data/Library/Caches`.
- An old JetBrains or Android Studio version's folder (`…/JetBrains/WebStorm2024.3`); the current version's
  settings are never offered.

Generic project folder names (`build`, `dist`, `bin`, `out`, `target`…) only count when the project file next to
them proves what they are, and they are labelled *Review first* unless git ignores them.

## Uninstall Rules (`SafetyGuard.validateUninstall`)

- The app bundle must be directly in `/Applications`, one folder below it, or in `~/Applications`; never under
  `/System`. Its `Info.plist` must carry the bundle ID being uninstalled.
- The bundle ID must have at least three reverse-DNS parts and must not be Apple's or a system tool's.
  Apple identifiers are refused in every form: `com.apple…`, `group.com.apple…`, `systemgroup.com.apple…`,
  `developer.apple…`, and `is.workflow…` (Shortcuts).
- MoltDisk never uninstalls itself.
- Every other file must sit directly inside one of these `~/Library` folders: Application Support, Caches, Logs,
  Containers, Group Containers, Preferences (and Preferences/ByHost), Saved Application State, HTTPStorages,
  WebKit, Cookies, Application Scripts, LaunchAgents.
- Its name must match the app's bundle ID, after removing a developer Team ID prefix, a `group.` prefix and a
  `.plist`, `.savedState` or `.binarycookies` suffix: either exactly or followed by a `.`
  (`com.foo.app.ShareExtension`). In Application Support, Caches and Logs it may instead match the app's name
  exactly. Lookalikes such as `com.foo.appother` never match.
- The app is moved to the Trash first, through the Finder; if that fails, its files are left in place.

### Leftovers of deleted apps

- Only names that are real reverse-DNS identifiers starting with a known domain ending (`com`, `org`, `io`,
  `dev`, `us`…) are considered, so files such as `warp.log.old.0` are ignored.
- A developer is skipped entirely when any app from them is still on the Mac, checked against every app
  Spotlight knows about (helpers and apps outside Applications included). If Spotlight can't list apps, no
  leftovers are shown.
- Leftovers are always labelled *Review first* and are never preselected.

## Running Apps

`RunningApps` matches data to running apps by bundle ID, by app name and by process name. Locked items can't be
ticked, and `Cleaner` takes a fresh snapshot right before deleting, so an app opened after the scan is still
protected.

## Running git in Scanned Projects

To decide whether a generic build folder is ignored, MoltDisk runs `git check-ignore` inside the project. Because
projects may be untrusted clones, git runs with `core.fsmonitor=false`, `core.hooksPath=/dev/null`,
`GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null`, and with no terminal prompts. The index is read on
purpose, so a folder that contains tracked files never counts as ignored.

## Verification

- `MoltDisk --check-guard` runs the guard against sample paths for cleanup and uninstall (allowed and refused
  cases) and prints PASS or FAIL for each.
- `MoltDisk --report` scans and prints what would be offered, without deleting anything.
- The self-test (see [README](README.md#self-test)) runs a real scan, selection and move to the Trash through the
  same code the buttons use.

## Known Limitations

- Other apps' Containers and Group Containers need Full Disk Access; without it they are reported as not removed.
- Time Machine local snapshots, `/Library/Developer/CoreSimulator` and Homebrew under `/opt/homebrew` are not
  cleaned.
- Leftover detection relies on Spotlight; a disabled Spotlight index hides leftovers rather than risking
  wrong ones.
- The app is ad-hoc signed and not notarized by Apple.
