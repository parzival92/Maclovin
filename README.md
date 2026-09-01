# Maclovin

**A local-first macOS CLI that explains where your disk space and memory went — and reclaims only with your explicit approval.**

Maclovin is built for developers, designers, and power users who want to understand a full disk or a thrashing machine without trusting a black-box cleaner. It measures the system itself, explains every number, states where every estimate comes from, and never deletes anything without a typed confirmation.

```
$ maclovin cleanup scan

Cleanup Scan
============

Summary
-------
  Candidates             4
  Estimated reclaimable  up to 6.3 GB
  Audit-only findings    1
  Writes                 none

Candidates (largest first)
--------------------------
  npm cache         est 5.8 GB  [Low risk, high confidence]
                    id: npm-cache  ·  runs `npm cache clean --force`
                    Downloaded package tarballs and metadata; npm re-fetches on
                    demand. Estimate: on-disk size of the npm cache store.
  Homebrew cleanup  est 300 MB  [Low risk, high confidence]
                    id: brew-cleanup  ·  runs `brew cleanup`
                    Outdated downloads and stale versions Homebrew itself says it
                    would remove. Estimate: parsed from `brew cleanup --dry-run`.
  User logs         est 6.8 MB  [Low risk, high confidence]
                    id: user-logs  ·  deletes ~/Library/Logs
                    Generated application and diagnostic logs under ~/Library/Logs.
                    Estimate: on-disk size measured by walking the target tree.
```

## Principles

- **Local-first.** No network calls, no telemetry, no AI services. Scans, decisions, and history stay on your machine.
- **Read-only by default.** Only commands named `apply` or `uninstall` can change files, and each one is gated behind an explicit typed confirmation. A wrong keystroke aborts — Maclovin never re-prompts its way into a deletion.
- **Official tools first.** Cleanup delegates to `brew cleanup`, `npm cache clean`, `pip cache purge`, and friends wherever possible. Direct deletion is reserved for well-known generated paths like Xcode DerivedData.
- **Honest numbers.** Every candidate states where its estimate came from, and after applying you see estimated vs actually-freed bytes per candidate, measured on the same basis. When a tool only reconciles at store granularity, Maclovin says so instead of inventing figures.
- **Personal data is out of bounds.** Documents, photos, mail, browser profiles, and project directories are never cleanup candidates.

## Install

Requires macOS 13+ and a Swift 6 toolchain (Xcode or Command Line Tools).

```bash
git clone https://github.com/parzival92/Maclovin.git
cd Maclovin
swift build -c release
ln -s "$PWD/.build/release/maclovin" ~/.local/bin/maclovin   # or any directory on your PATH
```

A Homebrew tap is planned for the first tagged release.

## Usage

### Explain memory pressure

```bash
maclovin memory audit
```

Read-only, always. Releasing memory means stopping a process, so Maclovin names the command that would do it and leaves running it to you.

```
Critical pressure — the workload does not fit in RAM (Swap, Compressor). Up to
2.2 GB can be freed by quitting runtimes that report no workload; see
Virtualization Runtimes below.

Pressure Signals
----------------
  Swap        [Critical]  4.7 GB of 6.0 GB (79%)
              The swap file is nearly full. macOS grows it on demand, but pages
              are moving to disk continuously and every miss costs real time.
  Compressor  [Elevated]  21 GB held in 6.7 GB (3.2x)
              The compressor is doing steady work to keep the workload resident.
  Headroom    [Elevated]  149 MB free of 16 GB (1%)
              Almost no memory is immediately available, so a new allocation
              must first reclaim from something else.

Virtualization Runtimes
-----------------------
  Docker Desktop  2.2 GB — Reclaimable (high confidence)
    evidence      10 processes, including its Linux VM
    state         0 containers running
    to release    Quit Docker Desktop; it restarts in seconds when you need it.

Largest Consumers
-----------------
  Visual Studio Code (26)  3.5 GB   22%  ############
  Docker (9)               2.2 GB   14%  ########
  Google Chrome (19)       2.2 GB   14%  #######
```

Every report is wrapped to the terminal width, labels share a column, and levels
are colour-coded when stdout is a terminal. Piped or redirected output, and
`NO_COLOR`, get the same text without escape sequences.

It leads with swap and the compressor rather than a "memory used" total, because macOS fills unused RAM by design — a high used figure is normal and tells you almost nothing. A virtual machine is the usual reason a Mac looks inexplicably full: it holds its configured memory whether or not the guest is doing anything, and its process is named after the virtualization framework rather than the app that started it. Maclovin names such a VM from the disk image it holds open and reports it under the app that owns it.

Memory is only ever called reclaimable when the runtime's own CLI says it has no workload. A long uptime is never treated as idleness, and a probe that fails is reported as unknown rather than as free memory.

### Find and apply safe cleanup

```bash
maclovin cleanup scan     # read-only: list candidates with size, risk, and confidence
maclovin cleanup review   # interactive picker, then typed confirmation
maclovin cleanup apply npm-cache pip-cache   # apply explicit candidates by ID
```

`review` and `apply` show the batch, require you to type `apply` (case-sensitive), execute, and then report estimate vs actual per candidate:

```
Per-Candidate Estimate vs Actual
--------------------------------
  npm cache  est 5.8 GB  ->  freed 5.8 GB
             succeeded, on estimate

Totals
------
  Estimated total  5.8 GB
  Freed total      5.8 GB
  Result           complete
```

A failure stops the batch: succeeded candidates keep their measured freed bytes, the rest are recorded as skipped, and the partial result is reported plainly.

Cleanup candidates cover Homebrew, npm, yarn, pnpm, pip, and Cargo caches, Xcode DerivedData, unavailable iOS Simulator devices, and generated user logs. Docker data and language version managers (nvm, pyenv, rbenv, asdf, SDKMAN, rustup) are reported **audit-only** — shown with sizes and the official way to reclaim them, never offered for deletion.

### Explain application storage

```bash
maclovin apps audit
```

Measures every app bundle in `/Applications` and `~/Applications`, attributes related data in Application Support, Caches, Containers, and Group Containers to its app with an explicit confidence label (High/Medium/Low), and lists what could not be attributed — so a 44 GB Docker or 12 GB Electron-app footprint is visible instead of a mystery.

```
Largest Apps
------------
  Docker               42 GB   44%  bundle 1.9 GB + data 40 GB · low-confidence match
  Claude               11 GB   12%  bundle 823 MB + data 10 GB · medium-confidence match
  iMovie              3.7 GB    4%  bundle 3.7 GB + data 4.0 KB · high-confidence match
  Serato DJ Lite      2.3 GB    2%  bundle only; no data matched
```

### Review what happened

```bash
maclovin history               # recent scans and cleanups, newest first
maclovin history show latest   # full detail, including per-candidate estimate vs freed
```

History is stored locally under `~/.local/state/maclovin/history` as summaries and action logs only — never full file inventories.

## Configuration

Optional, at `~/.config/maclovin/config.toml`. Missing files and unknown keys are fine; every setting has a safe default.

```toml
[scan]
exclude_paths = [
  "~/Library/Application Support/ImportantApp",
]

[cleanup]
require_typed_confirmation = true   # false falls back to a [y/N] prompt — never zero-interaction
move_app_data_to_trash = true

[history]
enabled = true
```

## How Maclovin measures

### Memory

Per-process figures are `phys_footprint` (`proc_pid_rusage`) — the same basis Activity Monitor reports, and the only one worth ranking by. Resident size excludes pages held in the compressor, so it understates worst for exactly the idle processes most worth finding: an idle VM here reported 787 MB resident against a real 5.17 GB.

Processes owned by another user cannot be read that way and fall back to resident size, which is a floor rather than a measurement; those rows say so, and one such process makes its whole group a lower bound. Processes that cannot be read at all are counted and disclosed. System-wide figures come from `host_statistics64` and `vm.swapusage`; "in use" is physical minus free and speculative pages, which is Maclovin's own accounting rather than Activity Monitor's category math.

### Storage

Sizes are **on-disk allocated bytes** (what `du` reports, and what deletion actually reclaims) — not logical file length. Hardlinks are counted once, symlinks are never followed, and unreadable paths are tallied and disclosed rather than silently skipped. APFS clones may over-count and snapshots/purgeable space are not counted; Maclovin states this rather than pretending to match the macOS Storage Settings math.

## Command status

| Command | Status |
|---|---|
| `cleanup scan` / `review` / `apply` | ✅ working |
| `apps audit` | ✅ working |
| `memory audit` | ✅ working |
| `history` / `history show` | ✅ working |
| `scan` (broad dashboard) | 🚧 planned |
| `brew audit` | 🚧 planned |
| `doctor` | 🚧 planned |
| `apps uninstall` / `brew uninstall` | 🚧 planned — refuse to run until their safety gates ship |

See [PRD.md](PRD.md) and [docs/implementation-plan.md](docs/implementation-plan.md) for the full product spec and roadmap.

## Development

```bash
swift build
swift run maclovin-tests    # swift-testing suite (not `swift test`; works on CLT-only machines)
swift run maclovin --help
```

Core logic lives in `MaclovinCore` (scanners, executor, config, history — reusable by a future GUI); `MaclovinCLI` is the argument-parser layer.

### AFK issue runner

`afk.sh` implements open GitHub issues unattended: for each issue it cuts a branch, has Claude Code implement it, verifies the build, and opens a PR that closes the issue on merge.

```bash
./afk.sh 3 4 5          # process specific issues
./afk.sh                # process all open issues labeled "afk"
AFK_DRY_RUN=1 ./afk.sh  # plan only, change nothing
```

Requires a clean working tree and an authenticated `gh`; see the header of `afk.sh` for configuration.
