# Security Policy

MoltDisk deletes files: it cleans caches and build output, removes simulators and uninstalls apps. Deletion
boundaries, path validation and the integrity of releases and install scripts are treated as security-sensitive.
The rules MoltDisk follows are documented in [SECURITY_AUDIT.md](SECURITY_AUDIT.md).

## Reporting a Vulnerability

Please report suspected security issues privately, through GitHub:
**Security › Report a vulnerability** on https://github.com/joe-watson-dev/moltdisk/security.

Do not open a public issue for a problem that isn't fixed yet.

Include as much of this as you can:

- MoltDisk version (About MoltDisk) and how you installed it (install script, Homebrew, zip, built from source)
- macOS version and Mac model
- What you did, step by step, and what was deleted or could be
- The path involved, and whether it involves symlinks, other apps' data, app uninstalling or the install script

## Response Expectations

- New reports are acknowledged within 7 days.
- A status update follows within 30 days if a fix or clear guidance isn't ready yet.
- Disclosure is coordinated once a fix, mitigation or user guidance is available.

MoltDisk is maintained by one person, so these times are best effort; security reports come before other work.

## Supported Versions

Security fixes are made for:

- The latest release
- The `main` branch

Older releases don't receive fixes. The install command and Homebrew always install the latest release.

## What Counts as a Security Issue

- MoltDisk deleting, or offering to delete, anything outside the rules in [SECURITY_AUDIT.md](SECURITY_AUDIT.md),
  such as personal files, another app's data during a cleanup, Apple's apps or system files
- A path, symlink or crafted folder name that gets past the safety guard
- Running commands in a scanned project in a way that lets that project execute code (for example through git
  hooks or config)
- Data of a running app being removed although it should be locked
- Tampering risks in `install.sh`, the Homebrew cask or the release workflow

## What Usually Doesn't Qualify

- Something you ticked and confirmed being moved to the Trash: that is the intended behaviour
- Items that can't be removed without Full Disk Access
- macOS showing that the app isn't notarized
- Problems that need an attacker who already controls your user account
