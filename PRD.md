# Maclovin PRD

## Product Positioning

Maclovin is a local-first macOS CLI for technical Mac users who want to understand and reduce disk usage without trusting a black-box cleaner. V1 focuses on explaining high "Applications" storage, auditing Homebrew, finding safe generated/cache cleanup opportunities, and applying selected cleanup or uninstall actions only after explicit approval.

The first audience is developers, designers, and power users who use Homebrew, Xcode, Docker, language toolchains, and package managers.

## Goals

- Explain what is consuming storage on a Mac using categories Maclovin can justify.
- Make the macOS "Applications" category understandable by auditing app bundles plus related app data.
- Audit Homebrew storage and health, including cache, outdated packages, cleanup candidates, and `brew doctor` findings.
- Identify cleanup candidates from generated/cache artifacts.
- Support cleanup and app/package uninstall with explicit confirmation gates.
- Keep all scans, history, and decisions local to the user's machine.

## Non-Goals

- Do not exactly reproduce macOS Storage Settings category math.
- Do not silently delete files.
- Do not auto-clean personal documents, browser profiles, Mail, Messages, Photos, Music, Movies, Desktop, or Documents.
- Do not make AI or network calls in V1.
- Do not perform broad Docker prune actions by default.
- Do not clean project-level `node_modules`, virtualenvs, or language-version-manager installs automatically.
- Do not ship a GUI in V1.

## V1 Command Set

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

## Core User Flows

### Broad Storage Scan

`maclovin scan` is the dashboard. It should show total disk usage, broad Maclovin-defined categories, top contributors, skipped paths, and recommended next commands.

If application-related storage is high, the scan should point the user to:

```bash
maclovin apps audit
```

### Applications Audit

`maclovin apps audit` explains application-related storage. It should inspect:

- `/Applications`
- `~/Applications`
- App support directories
- App containers and group containers
- Xcode-related developer data
- Docker-related data
- Homebrew cask apps and artifacts
- Large Electron apps and related support data where detectable

The audit should report confidence levels for app attribution:

- `high`: direct bundle, known app-owned path, known tool path
- `medium`: likely bundle identifier or app support relationship
- `low`: large nearby or name-matched data with incomplete evidence

### Homebrew Audit

`maclovin brew audit` includes both storage and health:

- Homebrew prefix and cache size
- Installed formulae and casks
- Large packages or casks
- `brew cleanup --dry-run` findings
- `brew doctor` summary
- Outdated formulae and casks
- Pinned packages
- Broken or missing dependencies where detectable

Cleanup may run `brew cleanup` only after dry-run output and confirmation. Upgrades, automatic repair of doctor findings, and automatic uninstall are outside normal cleanup.

### Cleanup Review And Apply

`maclovin cleanup scan` finds cleanup candidates without applying changes.

`maclovin cleanup review` presents an interactive picker grouped by source and risk. Users select what to clean, then type an exact confirmation before anything is applied.

`maclovin cleanup apply` executes only selected or explicit candidates and records the result in local history.

### Uninstall

App uninstall is separate from cleanup and uses a stricter confirmation model.

For apps:

1. Dry-run shows the app bundle, related support data candidates, confidence, and risk.
2. Apply moves the `.app` bundle to Trash after exact typed confirmation.
3. Related app data cleanup is a separate review step and should move uncertain data to Trash.

For Homebrew packages:

1. Dry-run shows the formula or cask, dependents, and likely impact.
2. Apply delegates to `brew uninstall` after exact typed confirmation.

## Cleanup Boundary

### Allowed Cleanup Targets

- Homebrew cleanup candidates via `brew cleanup`
- Homebrew cache when covered by official cleanup behavior
- npm cache
- yarn cache
- pnpm store prune
- pip cache
- Cargo registry/git cache cleanup candidates
- Xcode DerivedData
- Unavailable iOS Simulator devices via `xcrun simctl delete unavailable`
- User logs under known generated log locations
- Clearly generated temporary folders

### Audit-Only Targets

- Docker images, build cache, containers, and volumes
- nvm Node versions
- pyenv Python versions
- rbenv Ruby versions
- asdf installs
- SDKMAN installs
- rustup toolchains
- project-level dependency directories such as `node_modules`
- virtual environments

## Sizing Methodology

Maclovin reports its own measurement and does not try to reproduce macOS Storage Settings numbers.

- Sizes are **on-disk allocated bytes** (sum of `st_blocks * 512`), i.e. what is actually reclaimed when a path is removed — not logical file length. This matches `du` and naturally accounts for sparse files and filesystem compression.
- **Hardlinks** are counted once per inode within a single measurement.
- **Symlinks** are not followed and not traversed into.
- Paths that cannot be read are tallied and surfaced (a measurement can be marked partial) rather than aborting the scan.

Known limits, stated plainly to the user:

- APFS **clones** may over-count, because each clone reports its full allocated blocks even when blocks are shared.
- APFS **snapshots** and **purgeable** space are not counted.

## Safety Model

- Default commands are read-only unless the command name clearly indicates apply or uninstall.
- V1 is best-effort by default and does not require `sudo`.
- Permission gaps are reported plainly with optional guidance to improve coverage.
- Cleanup uses official tool cleanup commands whenever possible.
- Direct deletion is limited to well-known generated/cache paths.
- App uninstall moves bundles to Trash instead of permanently deleting them.
- App support data cleanup is separate from app bundle removal.
- Generated caches may be permanently removed after explicit confirmation.
- Every cleanup recommendation includes size, risk, confidence, and why it is considered safe or risky.
- Cleanup and uninstall actions are written to local history.

### Confirmation Gate

Every destructive action (cleanup apply, app uninstall, Homebrew uninstall) is gated by an explicit confirmation prompt. The default gate is **typed confirmation**:

- For app and Homebrew uninstall, the user types the **resolved target name** exactly — the app name (for example `Slack`) or the formula/cask name shown in the dry-run. Typing the target name guards against acting on the wrong thing, not just against a stray keystroke.
- For a `cleanup apply` batch there is no single target, so the user types the literal word `apply` after reviewing the grouped summary. Selection of which candidates to clean happens earlier in `cleanup review`; `apply` confirms the batch once.

Matching rules:

- Input is trimmed of surrounding whitespace and newlines.
- Typed-target matching is case-sensitive and must match exactly.
- A mismatch aborts the action with no changes — Maclovin does not loop or re-prompt.

When config sets `require_typed_confirmation = false`, the gate falls back to a lighter `[y/N]` prompt that defaults to "no". Maclovin never performs a destructive action with zero interaction.

## Local-Only Data

Maclovin stores only local summaries and action logs by default. It should not store full private file inventories unless a future explicit debug/export mode is added.

Local history should include:

- scan timestamp
- macOS version
- disk usage summary
- top storage contributors
- cleanup candidates found
- cleanup actions applied
- estimated bytes before
- measured bytes after when available
- errors and skipped paths

## Configuration

V1 supports a minimal local config file:

```text
~/.config/maclovin/config.toml
```

Example:

```toml
[scan]
deep_scan_default = false
exclude_paths = [
  "~/Library/Application Support/ImportantApp",
  "~/Work"
]

[cleanup]
require_typed_confirmation = true
move_app_data_to_trash = true

[history]
enabled = true
```

## Success Metrics

- A user can run `maclovin scan` and identify the next useful command within 30 seconds.
- A user with high application storage can run `maclovin apps audit` and see a clear explanation of the largest contributors.
- Cleanup recommendations are understandable without reading source code.
- Applying low-risk cleanup requires deliberate confirmation and records a local history entry.
- No V1 command silently deletes personal user data.

