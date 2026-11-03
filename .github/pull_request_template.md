## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## How it was tested

<!-- Commands you ran, and for anything that deletes files: how you tested it with throwaway files. -->

## Safety checklist

- [ ] `swift build` and `swift run MoltDisk --check-guard` pass
- [ ] Deletions still go only through `Cleaner` and `SafetyGuard`
- [ ] If the guard allows more, I added allowed **and** refused cases to `Report.checkGuard()`
- [ ] `SECURITY_AUDIT.md` is updated if the safety rules changed
