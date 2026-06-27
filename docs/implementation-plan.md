# Maclovin Implementation Plan

## Stack

- Swift CLI
- Swift Package Manager
- `swift-argument-parser`
- Foundation `FileManager` for filesystem inspection
- `Process` wrappers for trusted local tools
- Local TOML config support
- Local history stored under the user's application support or config/state directory

## Architecture

```text
Sources/
  MaclovinCLI/
    main.swift
    Commands/
      ScanCommand.swift
      AppsAuditCommand.swift
      BrewAuditCommand.swift
      CleanupCommand.swift
      DoctorCommand.swift
      HistoryCommand.swift
    Core/
      ByteSize.swift
      Paths.swift
      Risk.swift
      Confidence.swift
      Shell.swift
      ReportPrinter.swift
      Config.swift
      HistoryStore.swift
    Scanners/
      DiskScanner.swift
      AppScanner.swift
      AppAttributor.swift
      BrewScanner.swift
      PackageCacheScanner.swift
      DockerScanner.swift
      XcodeScanner.swift
      VersionManagerScanner.swift
    Cleanup/
      CleanupCandidate.swift
      CleanupPlanner.swift
      CleanupExecutor.swift
      TrashMover.swift
      Confirmation.swift
```

Keep scanner logic separate from command formatting so a future SwiftUI app can reuse the core.

## Milestone 1: Repo And CLI Skeleton

Deliverables:

- Initialize Swift package.
- Add top-level commands and help text.
- Add basic human-readable output.
- Add unit tests for shared models and formatting.

Validation:

```bash
swift build
swift test
swift run maclovin --help
```

## Milestone 2: Doctor

Implement `maclovin doctor`.

Checks:

- macOS version
- CPU architecture
- available disk space
- Homebrew availability and prefix
- Xcode Command Line Tools availability
- Docker CLI availability
- key scan paths readable or skipped
- Trash accessibility

Validation:

- Doctor runs without sudo.
- Missing tools are warnings, not failures.
- Permission-limited paths are reported clearly.

## Milestone 3: Broad Scan

Implement `maclovin scan`.

Targeted locations:

- `/Applications`
- `~/Applications`
- `~/Library/Application Support`
- `~/Library/Containers`
- `~/Library/Group Containers`
- `~/Library/Caches`
- `~/Library/Logs`
- `~/Library/Developer/Xcode`
- `~/Library/Developer/CoreSimulator`
- Homebrew prefix and cache
- Docker data locations if present
- common package-manager caches

Add optional:

```bash
maclovin scan --deep
```

Validation:

- Scan is useful without Full Disk Access.
- Skipped paths are reported.
- Output recommends `maclovin apps audit` when app-related usage is high.

## Milestone 4: Apps Audit

Implement `maclovin apps audit`.

Capabilities:

- Measure app bundle sizes.
- Attribute related app support/container data with confidence labels.
- Fold Xcode and Docker into application-related storage.
- Identify largest contributors and recommended next steps.

Validation:

- Known app bundles appear with sizes.
- Xcode/Docker data appears when present.
- Attribution confidence is explicit.
- The report does not claim to exactly match macOS Storage Settings.

## Milestone 5: Homebrew Audit

Implement `maclovin brew audit`.

Capabilities:

- Detect Homebrew prefix.
- Measure Homebrew cache and installed package footprint where practical.
- Run and summarize `brew cleanup --dry-run`.
- Run and summarize `brew doctor`.
- Report outdated formulae/casks and pinned packages.

Validation:

- Works when Homebrew is not installed.
- Failing brew commands become readable warnings.
- Cleanup estimates are tied to dry-run output where possible.

## Milestone 6: Cleanup Scan And Review

Implement:

```bash
maclovin cleanup scan
maclovin cleanup review
maclovin cleanup apply
```

Candidate fields:

- id
- title
- source
- paths or command
- estimated bytes
- risk
- confidence
- cleanup mode: official command, direct generated-cache delete, Trash
- explanation

Interactive review:

- Group candidates by source.
- Show size, risk, confidence, and explanation.
- Require explicit typed confirmation before apply.

Validation:

- Default cleanup scan performs no writes.
- Apply refuses to run without confirmation.
- Low-risk generated cleanup succeeds on fixtures.
- Failed cleanup records partial result clearly.

## Milestone 7: Uninstall

Implement:

```bash
maclovin apps uninstall <app-name> --dry-run
maclovin apps uninstall <app-name> --apply
maclovin brew uninstall <formula-or-cask> --dry-run
maclovin brew uninstall <formula-or-cask> --apply
```

Rules:

- Apps move to Trash.
- Related support data is separate from app bundle uninstall.
- Homebrew uninstall delegates to `brew uninstall`.
- Exact typed confirmation is required.

Validation:

- App dry-run shows the exact target.
- Apply refuses ambiguous app names.
- Homebrew dry-run shows dependents or risk where available.

## Milestone 8: History And Config

Implement:

- `maclovin history`
- `maclovin history show latest`
- `~/.config/maclovin/config.toml`

History stores summaries and action logs, not full private inventories.

Validation:

- Scan writes a summary when history is enabled.
- Cleanup writes before/after action records.
- Excluded paths from config are respected.

## Release Readiness

Before V1 release:

- `swift test` passes.
- Manual smoke test on a developer Mac.
- Confirm no command requires sudo by default.
- Confirm uninstall uses Trash for `.app` bundles.
- Confirm package-manager cleanup delegates to official commands.
- Add README installation instructions.
- Prepare Homebrew tap formula.
- Code sign the release binary if distributing outside local builds.

