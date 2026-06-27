# Maclovin

Maclovin is a local-first macOS CLI for understanding and reducing disk usage safely.

V1 focuses on:

- explaining large application-related storage
- auditing Homebrew storage and health
- finding safe generated/cache cleanup opportunities
- applying cleanup only after explicit review and confirmation
- uninstalling apps or Homebrew packages behind stricter approval gates

See [PRD.md](PRD.md) and [docs/implementation-plan.md](docs/implementation-plan.md) for the current product and build plan.

## Development

Build and test the Swift CLI scaffold:

```bash
swift build
swift test
swift run maclovin --help
```

The initial scaffold is intentionally read-only. Commands print planned behavior and refuse apply/uninstall execution until the safety gates are implemented.
