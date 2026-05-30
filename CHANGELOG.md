# Changelog

All notable changes to this extension are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-29

### Added

- Initial release of the `byte-sized` extension.
- Eleven `speckit.byte-sized.*` commands: `init`, `baseline`, `add`, `query`, `list`, `show`, `link`, `extract`, `analyze`, `validate`, `surface`.
- Brownfield `baseline` command for one-shot adoption on existing projects (sweeps docs/specs/code, batches by size, stages candidates to `_drafts/`).
- Cross-platform bash + PowerShell script library backing every command.
- Slim `index.json` projection so the spec-kit agent never loads the whole rules corpus into context.
- Lifecycle hooks: `before_specify`, `after_specify`, `after_clarify`, `before_plan`, `before_implement`, `after_analyze`.
- Self-test harness and CI workflow (Ubuntu + Windows).
