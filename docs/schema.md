# Business Rule Schema

Each business rule is a single markdown file with YAML frontmatter.
File layout: `.specify/rules/domains/<domain>/BR-<DOMAIN>-NNN-<slug>.md`.

## Frontmatter

```yaml
id: BR-AUTH-001                    # immutable; format: <id_prefix>-<DOMAIN>-<3-digit>
statement: "MFA is required for all admin accounts."   # one sentence, declarative
rationale: |                       # why this rule exists; multi-line allowed
  Admin accounts grant elevated privileges; MFA mitigates credential theft.
domain: auth                       # one of the configured domains
tags: [security, admin, mfa]       # free-form lowercase tokens
status: active                     # active | draft | superseded | deprecated
source:
  feature: 002-photo-albums        # spec-kit feature directory name
  spec: specs/002-photo-albums/spec.md#FR-12
  created: 2026-01-15              # YYYY-MM-DD
  superseded_by: null              # optional: id of replacing rule
edges:
  relates_to: [BR-AUTH-002]
  supersedes: []
  depends_on: [BR-SEC-014]
  conflicts_with: []
```

## Body

The markdown body is free-form. Suggested sections:

- **Context** — surrounding business situation.
- **Implications** — what the rule forces downstream (architecture, tests, UX).
- **Examples** — short positive/negative illustrations.
- **Notes** — caveats, open questions.

The body is **not** loaded into the slim `index.json`. The agent reads it only via `speckit.byte-sized.show`.

## ID allocation

- `id_prefix` defaults to `BR` and is configurable in `byte-sized-config.yml`.
- The `<DOMAIN>` token is the uppercased `domain` field.
- The numeric suffix is allocated by `rules-add` as `max(existing_in_domain) + 1`, zero-padded to 3 digits.

## Edge semantics

| Edge              | Meaning                                                                              |
|-------------------|--------------------------------------------------------------------------------------|
| `relates_to`      | Soft semantic relationship; no enforcement.                                          |
| `supersedes`      | This rule replaces the listed rule(s); the superseded rule's `status` becomes `superseded`. |
| `depends_on`      | The rule is meaningful only if the listed rule(s) are active.                        |
| `conflicts_with`  | The rule contradicts the listed rule(s); `analyze` will surface for resolution.      |

Edges are **bidirectional in the index** (the inverse is materialised when `rules-index` rebuilds) but the source-of-truth lives on the originating rule file.

## Status lifecycle

```
draft ──promote──> active ──supersede──> superseded
                       │
                       └──deprecate──> deprecated
```

- `draft` rules live under `.specify/rules/_drafts/` and are **excluded** from `query`/`surface` results unless `--include-drafts` is passed.
- `superseded` rules are moved to `.specify/rules/_archive/` but remain reachable by id (for traceability).
- `deprecated` rules stay in place with `status: deprecated` and are excluded from default queries.
