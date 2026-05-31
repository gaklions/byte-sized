# Changelog

All notable changes to this extension are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-05-30

### Added

- `/speckit.byte-sized.init` now pre-creates `.specify/bites/.tmp-byte-sized/` and appends `.tmp-byte-sized/` to the user's project root `.gitignore` (idempotent), so the agent has a documented scratch directory for `/baseline` and `/add` payloads that is automatically excluded from source control.

### Changed

- `/speckit.byte-sized.baseline` and `/speckit.byte-sized.add` prompts updated with an explicit scratch-file convention: per-batch / per-stub YAML payloads must be written to `.specify/bites/.tmp-byte-sized/<name>.yml` rather than the repo root, and removed after a successful stage / add call.

## [0.2.0] - 2026-05-30

### Changed — BREAKING

- Renamed the core noun from **rule** to **bite** throughout the extension to match the project's "byte-sized" framing.
  - Data folder: `.specify/rules/` → `.specify/bites/`.
  - Config keys: `storage.rules_dir` → `storage.bites_dir`.
  - Default id prefix: `BR` → `BB` (existing rule files written under the old prefix will not be migrated automatically).
  - Index schema field: `index.json` now exposes `bites: [...]` instead of `rules: [...]`.
  - Script filenames: `scripts/bash/rules-*.sh` → `scripts/bash/bites-*.sh` and `scripts/powershell/rules-*.ps1` → `scripts/powershell/bites-*.ps1` (same for `scripts/portal/rules-portal.py`).
  - Library functions: `bs_rules_dir` → `bs_bites_dir`, `Get-BsRulesDir` → `Get-BsBitesDir`.
  - Template renamed: `templates/rule.template.md` → `templates/bite.template.md`.
- **Migration for existing v0.1.0 installs:**
  1. `git mv .specify/rules .specify/bites`
  2. In `.specify/extensions/byte-sized/byte-sized-config.yml`, rename `storage.rules_dir` → `storage.bites_dir` and update the value to `.specify/bites`. Set `storage.id_prefix` to `BB` (or keep `BR` if you'd rather not re-id existing files).
  3. Re-run `/speckit.byte-sized.init` is **not** required; instead run the index regen: `bash scripts/bash/bites-index.sh` (or `pwsh -NoProfile -File scripts/powershell/bites-index.ps1`).
  4. If you adopt the new `BB-` prefix and want to rename existing `BR-<DOMAIN>-NNN` ids, do it manually — the extension does not ship a migration script.

## [0.1.0] - 2026-05-29

### Added

- Initial release of the `byte-sized` extension.
- Eleven `speckit.byte-sized.*` commands: `init`, `baseline`, `add`, `query`, `list`, `show`, `link`, `extract`, `analyze`, `validate`, `surface`.
- Brownfield `baseline` command for one-shot adoption on existing projects (sweeps docs/specs/code, batches by size, stages candidates to `_drafts/`).
- Cross-platform bash + PowerShell script library backing every command.
- Slim `index.json` projection so the spec-kit agent never loads the whole bites corpus into context.
- Lifecycle hooks: `before_specify`, `after_specify`, `after_clarify`, `before_plan`, `before_implement`, `after_analyze`.
- Self-test harness and CI workflow (Ubuntu + Windows).
