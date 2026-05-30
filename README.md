# spec-kit-byte-sized

A [Spec Kit](https://github.com/github/spec-kit) extension that maintains a versioned **business rules knowledge graph** in your repo and lets the spec-kit agent **navigate** it on demand — so the agent only loads a tiny (bite-sized), relevance-ranked projection into its context window instead of the whole rules corpus.

> Rules live as markdown files with YAML frontmatter under `.specify/rules/`. A slim `index.json` is the only thing the agent reads up-front; full rule bodies are fetched only when a specific decision needs them.

## Why

As a Spec Kit project grows, business rules accumulate across specs, clarifications, plans, and tasks. Re-feeding all of them into every prompt is wasteful and brittle. This extension:

- Stores each rule as a tiny (bite-sized), diffable markdown file (one rule = one node).
- Tracks edges between rules (`relates_to`, `supersedes`, `depends_on`, `conflicts_with`).
- Surfaces only the **relevant** rules via lifecycle hooks (`before_specify`, `before_plan`, `before_implement`).
- Captures new rules during `after_specify` / `after_clarify` — human-gated, staged in `_drafts/`.
- Runs coverage + conflict analysis during `after_analyze`.

## Install

```bash
# From a local checkout (for development)
specify extension add --dev /path/to/spec-kit-byte-sized

# Or from a GitHub release archive
specify extension add byte-sized --from https://github.com/your-org/spec-kit-byte-sized/archive/refs/tags/v0.1.0.zip
```

After installing, scaffold storage:

```text
/speckit.byte-sized.init
```

This creates `.specify/rules/{domains,_drafts,_archive,README.md,index.json}` and copies the config template to `.specify/extensions/byte-sized/byte-sized-config.yml`.

### Brownfield bootstrap

If you're adopting this on an existing project, run a baseline sweep to seed the graph from docs/specs that already exist:

```text
/speckit.byte-sized.baseline                    # docs+specs (default)
/speckit.byte-sized.baseline --scope all        # also scan src/, lib/, app/, packages/
/speckit.byte-sized.baseline --dry-run          # just show what would be scanned
```

Candidates are staged in `.specify/rules/_drafts/baseline-<batch>-<ts>.yml`. Review them, then promote each accepted rule via `/speckit.byte-sized.add`.

## Requirements

- Spec Kit `>= 0.8.0`
- [`jq`](https://stedolan.github.io/jq/) `>= 1.6`
- [`yq`](https://github.com/mikefarah/yq) `>= 4.0` (the Go implementation by mikefarah)

## Commands

| Command                          | What it does                                                                  |
|----------------------------------|-------------------------------------------------------------------------------|
| `speckit.byte-sized.init`       | Scaffold `.specify/rules/` and copy the config template.                      |
| `speckit.byte-sized.baseline`   | One-shot brownfield sweep: extract candidate rules from existing docs/specs/code into `_drafts/`. |
| `speckit.byte-sized.add`        | Guided rule creation with a conflict pre-check.                               |
| `speckit.byte-sized.query`      | Compact, token-efficient lookup. Returns `{id, statement, domain, tags}`.     |
| `speckit.byte-sized.list`       | Human-facing summary grouped by domain/status.                                |
| `speckit.byte-sized.show`       | Full markdown of one or more rules, with optional N-hop neighbour expansion.  |
| `speckit.byte-sized.link`       | Add or remove an edge between two rules; auto-flips status on `supersedes`.   |
| `speckit.byte-sized.extract`    | Propose candidate rules from a spec/clarify file; stages drafts for review.   |
| `speckit.byte-sized.analyze`    | Validate + coverage (FR/NFR/TASK ↔ rules) + cross-rule conflict detection.    |
| `speckit.byte-sized.validate`   | Graph integrity only (cheaper than `analyze`).                                |
| `speckit.byte-sized.surface`    | Hook-only: inject relevant rules into the active phase context.               |

## Hooks

| Phase              | Hook command                       | Optional? |
|--------------------|------------------------------------|-----------|
| `before_specify`   | `speckit.byte-sized.surface`      | no        |
| `after_specify`    | `speckit.byte-sized.extract`      | yes       |
| `after_clarify`    | `speckit.byte-sized.extract`      | yes       |
| `before_plan`      | `speckit.byte-sized.surface`      | no        |
| `before_implement` | `speckit.byte-sized.surface`      | no        |
| `after_analyze`    | `speckit.byte-sized.analyze`      | yes       |

`surface` is silent and capped; `extract` and `analyze` always prompt before acting.

## How a rule looks

`.specify/rules/domains/auth/BR-AUTH-001-mfa-required-for-admin.md`:

```markdown
---
id: BR-AUTH-001
statement: "MFA is required for all admin accounts."
rationale: |
  Mitigates credential theft on privileged accounts.
domain: auth
tags: [security, admin, mfa]
status: active
source:
  feature: 002-photo-albums
  spec: specs/002-photo-albums/spec.md#FR-12
  created: 2026-01-15
  superseded_by: null
edges:
  relates_to: [BR-AUTH-002]
  supersedes: []
  depends_on: []
  conflicts_with: []
---

## Context

Admins can publish and delete content; compromised admin credentials are the
highest-impact failure mode.

## Implications

- Login flow must integrate an authenticator-app TOTP step for admin accounts.
- Tests must cover the disabled-MFA refusal path.
```

See [docs/schema.md](docs/schema.md) for the full schema and [docs/workflows.md](docs/workflows.md) for the phase-by-phase flow.

## Configuration

Edit `.specify/extensions/byte-sized/byte-sized-config.yml` (created by `init` from [config-template.yml](config-template.yml)). Highlights:

```yaml
storage:
  rules_dir: ".specify/rules"
  id_prefix: "BR"

relevance:
  max_results: 12       # hard cap on query/surface output
  min_score: 0.2
  include_neighbors: 1
  max_projection_kb: 8  # surface truncates above this

extraction:
  auto_propose: true
  require_review: true  # nothing auto-merges; drafts stay in _drafts/

domains: [architecture, auth, code, compliance, data, pricing, security, tech, ux]

phase_hints:
  before_plan: [architecture, tech]
  before_implement: [code, compliance]
```

## Token-efficiency contract

- The agent **never** loads the whole rule corpus. `surface` and `query` return one-line projections only.
- The agent fetches a full rule body (`show <id>`) only when it needs the rationale, examples, or neighbours for a specific decision.
- The `before_*` hooks are designed to cost at most a few hundred tokens per invocation.

## What this extension does **not** do (v1)

- No semantic / embedding-based search (lexical only).
- No external graph database or MCP server.
- No silent rule writes — extraction always stages to `_drafts/` for human review.
- No cross-repository rule sharing (one graph per project).

## Selftest

```bash
# Linux / macOS
bash selftest/scripts/selftest.sh

# Windows
pwsh -NoProfile -File selftest/scripts/selftest.ps1
```

CI runs both on every push (see [.github/workflows/selftest.yml](.github/workflows/selftest.yml)).

## License

MIT — see [LICENSE](LICENSE).
