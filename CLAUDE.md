# QuotaWake Mac

Read `AGENTS.md` first — it holds the product boundaries (no provider HTTP
APIs, no tokens, no root, no limit-evasion framing), release rules, and the
removed wake-helper guardrails. Those rules apply to all agents working here.

Quick pointers:

- Code structure: `docs/ARCHITECTURE.md`
- Product spec and scope: `docs/MVP-SPEC.md`
- Build, tests, UI QA, troubleshooting: `DEVELOPMENT.md`
- Design system: `DESIGN.md` · Release process: `RELEASE.md`

Common commands (run from `quotawake_mac/`):

```bash
swift test
swift build -c debug
./Scripts/package_app.sh debug
```

Use fake Claude/Codex CLIs for automated tests and QA. Live provider calls
require explicit user approval.
