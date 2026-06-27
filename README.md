# Maclovin

Maclovin is a local-first macOS CLI for understanding and reducing disk usage safely.

V1 focuses on:

- explaining large application-related storage
- auditing Homebrew storage and health
- finding safe generated/cache cleanup opportunities
- applying cleanup only after explicit review and confirmation
- uninstalling apps or Homebrew packages behind stricter approval gates

See [PRD.md](PRD.md) and [docs/implementation-plan.md](docs/implementation-plan.md) for the current product and build plan.

## AFK issue runner

`afk.sh` implements open GitHub issues unattended: for each issue it cuts a
branch, has Claude Code implement it, verifies the build, and opens a PR that
closes the issue on merge (linked back via a comment and the `has-pr` label).

```bash
./afk.sh 3 4 5          # process specific issues
./afk.sh                # process all open issues labeled "afk"
AFK_DRY_RUN=1 ./afk.sh  # plan only, change nothing
```

You review and approve each PR; merging it closes the issue. Requires a clean
working tree and an authenticated `gh`. See the header of `afk.sh` for config
(`AFK_BASE`, `AFK_LABEL`, `AFK_MODEL`).

## Development

Build and test the Swift CLI scaffold:

```bash
swift build
swift test
swift run maclovin --help
```

The initial scaffold is intentionally read-only. Commands print planned behavior and refuse apply/uninstall execution until the safety gates are implemented.
