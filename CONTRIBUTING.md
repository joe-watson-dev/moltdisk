# Contributing to MoltDisk

Thanks for helping. MoltDisk deletes files, so every change is reviewed with safety first. Everyone taking part
follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Setup

Requirements: a Mac with Apple silicon, macOS 15 or later, and Xcode 16 (or its Command Line Tools with Swift 6).

```bash
git clone https://github.com/joe-watson-dev/moltdisk && cd moltdisk
swift build
```

## Development

```bash
swift run MoltDisk                 # run the app
swift run MoltDisk --report        # scan and print what would be offered, deletes nothing
swift run MoltDisk --check-guard   # safety-guard checks, must end with "All guard checks passed"
./scripts/build-app.sh             # build build/MoltDisk.app
```

Or open `Package.swift` in Xcode and press Run.

## Safety Rules for Changes

- Every deletion goes through `Cleaner`, and every path through `SafetyGuard` right before it is removed. Never
  call `removeItem`, `trashItem` or `rm` anywhere else.
- Move to the Trash by default. Simulators are removed only with `xcrun simctl`.
- New scanners return their items through `Scanner.finalize`, which measures them, drops anything the guard
  refuses and locks data of running apps.
- Prefer missing something over offering something wrong: when a folder name is generic, require proof
  (a project file next to it) and label it *Review first*.
- When you widen what the guard allows, add allowed **and** refused cases to `Report.checkGuard()` in
  `Sources/MoltDisk/MoltDiskApp.swift`.
- Don't run tools inside scanned projects without the protections described in
  [SECURITY_AUDIT.md](SECURITY_AUDIT.md#running-git-in-scanned-projects).
- Update [SECURITY_AUDIT.md](SECURITY_AUDIT.md) when the rules change.

## Code Style

- Swift 5 language mode, SwiftUI, no third-party dependencies.
- Match the surrounding code: short doc comments that explain why, not what.
- Keep UI text plain and specific, in sentence case.

## Pull Requests

1. Fork the repository and create a branch from `main`.
2. Make your change and run `swift build` and `swift run MoltDisk --check-guard`.
3. For changes to what gets deleted, describe how you tested it (ideally with throwaway files, never with
   someone's real data).
4. Open a pull request against `main` and fill in the template.

GitHub Actions builds the app and runs the guard checks on every pull request. `main` is protected: changes
land through reviewed pull requests.

Security problems: please don't open a public issue or pull request; follow [SECURITY.md](SECURITY.md).

## Licensing

MoltDisk is licensed under [GPL-3.0](LICENSE), and that is the license your contribution carries. There is no
CLA: you keep the copyright to your work.

The MoltDisk name and icon are covered by the [trademark policy](TRADEMARK.md), not by the license.
