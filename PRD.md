# Maclovin PRD

## Product Positioning

Maclovin is a local-first macOS CLI for technical Mac users who want to understand and reduce pressure on a contended resource without trusting a black-box cleaner. V1 focuses on explaining high "Applications" storage, auditing Homebrew, finding safe generated/cache cleanup opportunities, applying selected cleanup or uninstall actions only after explicit approval, and — read-only — explaining where physical memory went.

The first audience is developers, designers, and power users who use Homebrew, Xcode, Docker, language toolchains, and package managers.

## Goals

- Explain what is consuming storage on a Mac using categories Maclovin can justify.
- Explain what is consuming physical memory, and which of it a runtime reports as reclaimable.
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
- Do not signal, stop, or kill a running process. `memory audit` is read-only and names the command that would release memory instead of running it.

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
maclovin memory audit
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

#### Estimate vs Actual-Freed Reconciliation

Every cleanup candidate states where its estimate came from and how much space was actually freed, on the same basis. Two cleanup modes set that basis:

- **Official-command mode** (for example `brew cleanup`, `npm cache clean`, `pip cache purge`, `pnpm store prune`): the estimate is parsed from the tool's own dry-run output, since Maclovin does not choose which bytes the tool removes. Freed space is the before/after on-disk delta of the tool's managed store (for example the Homebrew cache).
- **Direct-delete mode** (for example Xcode DerivedData, generated log folders): the estimate is the on-disk size measured by walking the target tree immediately before applying, so it reflects current contents rather than a stale scan. Freed space is measured per candidate by re-measuring the tree after removal (`measured-before − measured-after`).

Reconciliation is reported per candidate where feasible. When several official-command candidates share one managed store, reconciliation may only be available at store granularity; Maclovin states that rather than inventing per-candidate numbers.

A partial failure mid-batch stops the batch and is reported honestly: candidates that already succeeded keep their measured freed bytes, the failing candidate is recorded as failed with a reason, and the remaining candidates are recorded as skipped. The total freed so far is always shown.

The per-candidate estimated-vs-freed result surfaces both after `cleanup apply` and in `maclovin history`.

### Memory Audit

`maclovin memory audit` explains physical memory the way `apps audit` explains storage. It is read-only and has no apply counterpart in V1: releasing memory means stopping a process, which Maclovin never does on the user's behalf.

The report leads with pressure signals rather than a "memory used" total. macOS fills unused RAM by design, so a high used figure is normal and carries almost no information; what costs the user time is the compressor working hard and pages travelling to swap. Each signal is reported separately, with the measurement beside the verdict, because they fail in different ways and call for different fixes:

- **Swap** — bytes used against the swap file's current size. Any use is elevated; at or above 75% of the file it is critical.
- **Compressor** — the uncompressed volume held against the RAM it occupies. At or above 2.0x it is elevated, at or above 3.5x critical, and below 5% of RAM it is not flagged however well it compresses.
- **Headroom** — free plus speculative memory against physical. Below 2% it is elevated, and never critical on its own: macOS deliberately keeps free memory low, so scarce free memory is only meaningful alongside the other two signals.

The overall level is the worst individual signal.

Consumers are grouped only by owning `.app` bundle, which is direct evidence from the executable path, so an app's helper processes are reported as one row. Processes are never grouped by executable name — two processes sharing a name can be unrelated, which is exactly the case for virtual machine hosts.

#### Virtualization Runtimes

Virtual machines are the common reason a Mac looks inexplicably full: a VM holds its configured memory whether or not its guest is doing anything, and its host process is usually named after the virtualization framework rather than the app that started it. Apple Virtualization VM hosts are XPC services reparented to `launchd`, so neither the parent process nor the executable path identifies the owner.

Maclovin names such a VM from the disk image it holds open, which is the only direct evidence available without privileges, and reports the resulting attribution confidence. System paths never identify an owner — every process holds those open. A VM traced to an app is reported under that app so its memory is not counted twice.

Whether a runtime is busy comes from the runtime's own CLI, never from inference:

- A **long uptime is never treated as idleness.** A VM up for nine days may be serving a cluster.
- Memory is called reclaimable **only** when the runtime reports no workload — `docker ps` listing no containers, `multipass list` showing no running instance.
- A probe that fails and a runtime that is genuinely idle must not look alike. An unreachable daemon is reported as unknown, never as reclaimable.
- Maclovin cannot see inside a guest, so an attributed VM's workload is reported as unknown rather than guessed.

### Uninstall

App uninstall is separate from cleanup and uses a stricter confirmation model.

For apps, `maclovin apps uninstall <app-name>` first resolves `<app-name>` to a single installed bundle:

- The query matches against an app's **display name** (the `.app` filename without its extension) or its **bundle identifier** (`CFBundleIdentifier`).
- Matching is **case-insensitive** — `slack` resolves `Slack.app`.
- The trailing **`.app` suffix is optional** — `Slack`, `slack`, and `Slack.app` all resolve the same bundle. (Bundle identifiers never carry a `.app` suffix.)
- A **bundle-identifier** match takes precedence over a display-name match, so typing a specific identifier always targets that exact app.
- A query is **ambiguous** when it matches more than one distinct bundle across `/Applications` and `~/Applications` (for example a `Slack.app` present in both). Maclovin aborts and lists every candidate with its path and bundle identifier, asking the user to re-run with the bundle identifier to pick one.
- A query that matches nothing aborts with a not-found message naming what was searched.

Once resolved:

1. Dry-run echoes the **resolved target** — display name, bundle path, and bundle identifier — alongside related support data candidates, confidence, and risk, so the user can verify the right app before confirming.
2. Apply moves the `.app` bundle to Trash after exact typed confirmation of the **resolved display name**.
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

## Memory Measurement Methodology

Per-process memory is `phys_footprint` from `proc_pid_rusage`, the same basis Activity Monitor reports. It is the only per-process number worth ranking by: resident size omits pages held in the compressor, so an idle memory hog reports a small RSS while actually holding gigabytes.

`proc_pid_rusage` refuses processes owned by another user. Those fall back to resident size from `ps`, which is a floor rather than a measurement, and every affected row says so. Processes that cannot be read at all are tallied and disclosed. One resident-only member makes its whole group a lower bound.

System-wide figures come from `host_statistics64(HOST_VM_INFO64)` and `sysctlbyname("vm.swapusage")`. "In use" is physical memory minus free and speculative pages — Maclovin's own accounting, stated as such, and not an attempt to reproduce Activity Monitor's category math.

## Safety Model

- Default commands are read-only unless the command name clearly indicates apply or uninstall.
- `memory audit` is read-only and has no apply counterpart. Maclovin never signals, stops, or kills a process; it names the command that would release memory and leaves running it to the user.
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
- cleanup actions applied, with per-candidate status (succeeded, failed, skipped)
- per-candidate estimated bytes before
- per-candidate measured bytes freed after, where feasible
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

