# Maclovin Decisions

## Product Shape

- V1 is a CLI, not a GUI.
- V1 targets technical Mac users first: developers, designers, power users, Homebrew users, Xcode users, and Docker users.
- V1 is local-first and deterministic. It does not call AI services or network APIs at runtime.
- V1 should be shippable to users as a signed CLI binary and later through a Homebrew tap.

## Implementation

- Build V1 as a Swift CLI using Swift Package Manager and `swift-argument-parser`.
- Keep scanning and cleanup logic reusable so a future SwiftUI app can share the core.
- Do not include JSON output in V1 unless the need reappears.

## Permissions

- V1 works best-effort by default.
- V1 does not require `sudo` for normal scans.
- Full Disk Access guidance is optional and should be improved as real permission gaps are discovered.
- Permission-limited paths are reported clearly instead of treated as hard failures.

## Storage Model

- Maclovin computes its own explainable storage categories.
- macOS Storage Settings category numbers are context, not a target to exactly reproduce.
- `maclovin scan` is the broad dashboard.
- `maclovin apps audit` is the deep investigation for application-related storage.

## Command Set

Accepted V1 commands:

```bash
maclovin scan
maclovin apps audit
maclovin apps uninstall <app-name> --dry-run
maclovin apps uninstall <app-name> --apply
maclovin brew audit
maclovin brew uninstall <formula-or-cask> --dry-run
maclovin brew uninstall <formula-or-cask> --apply
maclovin cleanup scan
maclovin cleanup review
maclovin cleanup apply
maclovin doctor
maclovin history
```

Deferred commands:

- Dedicated `maclovin xcode audit`
- Dedicated `maclovin docker audit`

Xcode and Docker findings are folded into `apps audit` and cleanup recommendations.

## Applications Audit

- `apps audit` reports app bundles plus related app data.
- Related data attribution uses confidence labels.
- Xcode, iOS Simulator data, Docker data, Electron app support data, and Homebrew cask artifacts are treated as likely application-related contributors.

## Cleanup

- V1 includes cleanup, not just recommendations.
- Default diagnostic commands are read-only.
- Cleanup uses an interactive review picker.
- Cleanup requires explicit typed confirmation before applying changes.
- Cleanup recommendations are ranked by size, safety, confidence, and reversibility.
- Official cleanup commands are preferred over direct deletion.
- Direct deletion is reserved for well-known generated/cache paths.

## Uninstall

- V1 includes uninstall with approval.
- App uninstall is two-stage:
  1. Move the `.app` bundle to Trash.
  2. Separately review related support data before cleanup.
- App support data with uncertain value should move to Trash, not be permanently deleted.
- Homebrew uninstall delegates to `brew uninstall` after dry-run and confirmation.

## Trash And Permanent Deletion

- Move to Trash:
  - `.app` bundles
  - app support/container data selected after uninstall
  - anything where user value is uncertain
- Permanent delete:
  - generated caches after confirmation
  - Xcode DerivedData
  - Homebrew cleanup via `brew cleanup`
  - package-manager caches via official commands
  - selected generated logs/cache folders

## Homebrew

- `brew audit` includes both storage and health.
- It reports Homebrew cache, installed formulae/casks, cleanup candidates, `brew doctor`, outdated packages, pinned packages, and dependency issues where available.
- Cleanup may run `brew cleanup` after dry-run and confirmation.
- V1 should not auto-upgrade packages or auto-fix `brew doctor` warnings.

## Docker

- Docker inspection is included in V1.
- Docker is folded into `apps audit`, not a dedicated command.
- V1 reports Docker app and data footprint.
- V1 does not run destructive Docker prune actions by default.

## Xcode

- Xcode and iOS Simulator storage are first-class findings inside `apps audit`.
- No dedicated Xcode command in V1.
- Low-risk cleanup includes Xcode DerivedData and unavailable simulator devices.
- Archives, DeviceSupport, and simulator devices with data are higher-risk and require clearer review.

## Package Managers And Runtimes

- V1 includes secondary package-manager cache detection and cleanup for npm, yarn, pnpm, pip, and Cargo.
- V1 includes language version managers in audit-only mode:
  - nvm
  - pyenv
  - rbenv
  - asdf
  - SDKMAN
  - rustup
- V1 does not automatically delete project-level `node_modules`, virtualenvs, or language runtime installs.

## History And Config

- V1 keeps minimal local-only scan and cleanup history.
- History stores summaries and action logs, not full private file inventories.
- V1 supports a minimal config file at `~/.config/maclovin/config.toml`.
- Config supports scan exclusions, cleanup confirmation behavior, and history enablement.

