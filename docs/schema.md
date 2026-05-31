# Business Bite Schema

Each business bite is a single markdown file with YAML frontmatter.
File layout: `.specify/bites/domains/<domain>/BB-<DOMAIN>-NNN-<slug>.md`.

## Frontmatter

```yaml
id: BB-AUTH-001                    # immutable; format: <id_prefix>-<DOMAIN>-<3-digit>
statement: "MFA is required for all admin accounts."   # one sentence, declarative
rationale: |                       # why this bite exists; multi-line allowed
  Admin accounts grant elevated privileges; MFA mitigates credential theft.
domain: auth                       # one of the configured domains
tags: [security, admin, mfa]       # free-form lowercase tokens
status: active                     # active | draft | superseded | deprecated
source:
  feature: 002-photo-albums        # spec-kit feature directory name
  spec: specs/002-photo-albums/spec.md#FR-12
  created: 2026-01-15              # YYYY-MM-DD
  superseded_by: null              # optional: id of replacing bite
edges:
  relates_to: [BB-AUTH-002]
  supersedes: []
  depends_on: [BB-SEC-014]
  conflicts_with: []
```

## Body

The markdown body is free-form. Suggested sections:

- **Context** — surrounding business situation.
- **Implications** — what the bite forces downstream (architecture, tests, UX).
- **Examples** — short positive/negative illustrations.
- **Notes** — caveats, open questions.

The body is **not** loaded into the slim `index.json`. The agent reads it only via `speckit.byte-sized.show`.

## ID allocation

- `id_prefix` defaults to `BB` and is configurable in `byte-sized-config.yml`.
- The `<DOMAIN>` token is the uppercased `domain` field.
- The numeric suffix is allocated by `bites-add` as `max(existing_in_domain) + 1`, zero-padded to 3 digits.

## Edge semantics

| Edge              | Meaning                                                                              |
|-------------------|--------------------------------------------------------------------------------------|
| `relates_to`      | Soft semantic relationship; no enforcement.                                          |
| `supersedes`      | This bite replaces the listed bite(s); the superseded bite's `status` becomes `superseded`. |
| `depends_on`      | The bite is meaningful only if the listed bite(s) are active.                        |
| `conflicts_with`  | The bite contradicts the listed bite(s); `analyze` will surface for resolution.      |

Edges are **bidirectional in the index** (the inverse is materialised when `bites-index` rebuilds) but the source-of-truth lives on the originating bite file.

## Status lifecycle

```
draft ──promote──> active ──supersede──> superseded
                       │
                       └──deprecate──> deprecated
```

- `draft` bites live under `.specify/bites/_drafts/` and are **excluded** from `query`/`surface` results unless `--include-drafts` is passed.
- `superseded` bites are moved to `.specify/bites/_archive/` but remain reachable by id (for traceability).
- `deprecated` bites stay in place with `status: deprecated` and are excluded from default queries.
