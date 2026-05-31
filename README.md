<div align="center">

  <img src="./assets/graphics/info-graphic-600x600.png" alt="ByteSize banner" width="600">


  # spec-kit-byte-sized
</div>



A [Spec Kit](https://github.com/github/spec-kit) extension that maintains a versioned **business rules (bites) knowledge graph** in your repo and lets the spec-kit agent **navigate** it on demand — so the agent only loads a tiny (bite-sized), relevance-ranked projection into its context window instead of the whole rule corpus.

> Bites live as markdown files with YAML frontmatter under `.specify/bites/`. A slim `index.json` is the only thing the agent reads up-front; full rule bodies are fetched only when a specific decision needs them.

## Why

As a Spec Kit project grows, business rules accumulate across specs, clarifications, plans, and tasks. Re-feeding all of them into every prompt is wasteful and brittle. This extension:

- Stores each rule (bite) as a tiny (bite-sized), diffable markdown file (one bite = one node).
- Tracks edges between rules (`relates_to`, `supersedes`, `depends_on`, `conflicts_with`).
- Surfaces only the **relevant** bites via lifecycle hooks (`before_specify`, `before_plan`, `before_implement`).
- Captures new rules during `after_specify` / `after_clarify` — human-gated, staged in `_drafts/`.
- Runs coverage + conflict analysis during `after_analyze`.

## Install

```bash
# From a local checkout (for development)
specify extension add --dev /path/to/spec-kit-byte-sized

# Or from a GitHub release archive
specify extension add byte-sized --from https://github.com/gaklions/byte-sized/archive/refs/tags/v0.2.2.zip
```

After installing, scaffold storage:

```text
/speckit.byte-sized.init
```

This creates `.specify/bites/{domains,_drafts,_archive,README.md,index.json}` and copies the config template to `.specify/extensions/byte-sized/byte-sized-config.yml`.

### Brownfield bootstrap

If you're adopting this on an existing project, run a baseline sweep to seed the graph from docs/specs that already exist:

```text
/speckit.byte-sized.baseline                    # docs+specs (default)
/speckit.byte-sized.baseline --scope all        # also scan src/, lib/, app/, packages/
/speckit.byte-sized.baseline --dry-run          # just show what would be scanned
```

Candidates are staged in `.specify/bites/_drafts/baseline-<batch>-<ts>.yml`. Review them, then promote each accepted bite via `/speckit.byte-sized.add`.

## Requirements

- Spec Kit `>= 0.8.0`
- [`jq`](https://stedolan.github.io/jq/) `>= 1.6`
- [`yq`](https://github.com/mikefarah/yq) `>= 4.0` (the Go implementation by mikefarah)
- `python3` `>= 3.10` — **optional**, only required to launch the review portal (see [Review portal](#review-portal))

## Commands

| Command                          | What it does                                                                  |
|----------------------------------|-------------------------------------------------------------------------------|
| `speckit.byte-sized.init`       | Scaffold `.specify/bites/` and copy the config template.                      |
| `speckit.byte-sized.baseline`   | One-shot brownfield sweep: extract candidate bites from existing docs/specs/code into `_drafts/`. |
| `speckit.byte-sized.add`        | Author a bite in plain English (or structured form); agent classifies it and runs a conflict pre-check. |
| `speckit.byte-sized.query`      | Compact, token-efficient lookup. Returns `{id, statement, domain, tags}`.     |
| `speckit.byte-sized.list`       | Human-facing summary grouped by domain/status.                                |
| `speckit.byte-sized.show`       | Full markdown of one or more bites, with optional N-hop neighbour expansion.  |
| `speckit.byte-sized.link`       | Add or remove an edge between two bites; auto-flips status on `supersedes`.   |
| `speckit.byte-sized.extract`    | Propose candidate bites from a spec/clarify file; stages drafts for review.   |
| `speckit.byte-sized.analyze`    | Validate + coverage (FR/NFR/TASK ↔ bites) + cross-bite conflict detection.    |
| `speckit.byte-sized.validate`   | Graph integrity only (cheaper than `analyze`).                                |
| `speckit.byte-sized.surface`    | Hook-only: inject relevant bites into the active phase context.               |
| `speckit.byte-sized.portal`     | Launch the local review portal (web UI) for triaging drafts and navigating the graph. |

### Authoring a bite in plain English

You don't need to hand-write YAML. Type the rule and the agent classifies it:

```text
/speckit.byte-sized.add Admins must use MFA for production access
```

The agent proposes a classification and asks once before writing:

```text
statement: Admins must use MFA for production access.
domain:    auth
tags:      [admin, mfa, production, access]
rationale:

Add this bite? (yes / no / edit)
```

On `yes`, the conflict pre-check runs and the bite is written under `.specify/bites/domains/auth/`. A structured shortcut (`statement="..." domain=... tags=...,...`) is also accepted for power users.

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

## How a bite looks

`.specify/bites/domains/auth/BB-AUTH-001-mfa-required-for-admin.md`:

```markdown
---
id: BB-AUTH-001
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
  relates_to: [BB-AUTH-002]
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
  bites_dir: ".specify/bites"
  id_prefix: "BB"

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

## Review portal

When a brownfield baseline produces hundreds of draft stubs, reviewing them via the agent is the wrong shape of interaction. The extension ships a small local web UI for triaging drafts, navigating the active bite graph, and editing bites in place.

```text
/speckit.byte-sized.portal              # launches it (recommended)
```

or directly:

```bash
bash scripts/bash/bites-portal.sh                      # Linux / macOS
pwsh -NoProfile -File scripts/powershell/bites-portal.ps1  # Windows
```

The portal serves a single static SPA from a Python stdlib HTTP server bound to `127.0.0.1` only (non-loopback hosts are refused at startup). Every mutation shells out to the existing helper scripts (`bites-add`, `bites-link`, `bites-index`, plus the new `bites-promote` / `bites-reject` / `bites-status` / `bites-edit`), so the on-disk result is identical whether you trigger it from the portal, the CLI, or an agent command.

Highlights:

- Drafts tab — filterable multi-select list, inline edit before approve, side-by-side "closest active bite" diff, bulk approve / reject, configurable auto-handle thresholds, keyboard shortcuts (`j`/`k`/`a`/`r`/`x`/`e`).
- Graph tab — Cytoscape.js force-directed view of the active corpus with filters by domain, status, and edge type.
- Bite detail tab — editable frontmatter, edge add / remove (with the right confirmation on `supersedes`), status change (auto-moves files between `domains/<domain>/` and `_archive/<domain>/`), and a `vscode://file/...` deep-link for body edits.

See [docs/portal.md](docs/portal.md) for the full guide.

## Token-efficiency contract

- The agent **never** loads the whole bite corpus. `surface` and `query` return one-line projections only.
- The agent fetches a full bite body (`show <id>`) only when it needs the rationale, examples, or neighbours for a specific decision.
- The `before_*` hooks are designed to cost at most a few hundred tokens per invocation.

## What this extension does **not** do (v1)

- No semantic / embedding-based search (lexical only).
- No external graph database or MCP server.
- No silent bite writes — extraction always stages to `_drafts/` for human review.
- No cross-repository bite sharing (one graph per project).

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
