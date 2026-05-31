# Review portal

A local web UI for triaging draft bites, navigating the active bite graph, and editing bite frontmatter — backed by the same lifecycle scripts the agent uses.

```text
/speckit.byte-sized.portal              # launches it (recommended)
bash scripts/bash/bites-portal.sh       # direct
pwsh -NoProfile -File scripts/powershell/bites-portal.ps1
```

After it boots, open [http://127.0.0.1:7821/](http://127.0.0.1:7821/) (or the port you passed). The server is **loopback-only** — it refuses to bind to non-`127.0.0.1` hosts.

## What it's for

When `/speckit.byte-sized.baseline` produces hundreds of draft stubs, scrolling through them with the agent is the wrong shape of interaction. The portal gives you:

- a filterable, multi-selectable list of every staged stub,
- inline edit of statement / domain / tags / rationale / edges before approving,
- a side-by-side "closest active bite" comparison so near-duplicates that survived the lexical dedup gate are obvious,
- bulk approve / bulk reject with a single keystroke,
- a force-directed graph (Cytoscape.js) of the active corpus with filters by domain, status, and edge type,
- in-place status / edge / frontmatter edits on existing bites,
- a deep-link to open any bite's `.md` file directly in VS Code.

## Architecture

```
Browser SPA  ──HTTP──▶  bites-portal.py (Python stdlib, 127.0.0.1 only)
                              │
                              ▼
                       subprocess: bash/pwsh wrappers
                              │
                              ▼
   bites-add | bites-link | bites-index | bites-promote
   bites-reject | bites-status | bites-edit
```

The Python server is a thin RPC layer. Every mutation is performed by an existing shell/PowerShell helper, so the on-disk result is identical whether you trigger it from the portal, from the CLI, or from an agent command.

## Configuration

Edit the `portal:` block in `.specify/extensions/byte-sized/byte-sized-config.yml` (created by `/speckit.byte-sized.init` from [config-template.yml](../config-template.yml)):

```yaml
portal:
  host: "127.0.0.1"     # loopback-only; non-loopback values are refused at startup
  port: 7821
  open_browser: true
  auto_handle:
    novel_below: 0.0    # auto-approve stubs whose closest-active overlap is BELOW this (0 = disabled)
    duplicate_above: 0.0 # auto-reject stubs whose closest-active overlap is AT OR ABOVE this
```

Both `auto_handle` values default to disabled. When you set them, the **Auto-handle…** button in the Drafts bulk bar becomes active — it will queue all eligible stubs for promotion or rejection and ask you to confirm before sending the bulk request.

## Drafts review

Layout:

| Pane          | Contents                                                                 |
|---------------|--------------------------------------------------------------------------|
| Left rail     | Filter bar + scrollable list of every stub grouped by draft file         |
| Center        | Editable form for the currently focused stub + closest-active diff strip |
| Bulk bar      | Selection count, bulk approve, bulk reject, auto-handle                  |

Per-stub badges:

- **new** (green) — no active bite shares any 3+ char tokens with this statement.
- **0.42** etc. — token-overlap score against the closest active bite. Anything above ~0.5 is worth eyeballing the diff strip; the lexical dedup gate is 0.7.

Filters compose: text contains, domain equals, tag contains, "closest-overlap ≤ X". Use the slider to hide obvious novels and focus on borderline cases.

**Approve flow:**

1. Click a stub (or `j`/`k` to move).
2. Edit statement / rationale / domain / tags / edges if needed.
3. Click **Approve →** (or press `a`).
4. The stub is popped from its draft file, piped through `bites-add` for id allocation + slug + index regen, and the next stub becomes current.

**Reject flow:** click **Reject** (or press `r`). You'll be prompted for an optional reason. The stub is appended to `.specify/bites/_drafts/_rejected/<original-filename>.yml` with `rejected: { at: <UTC ISO>, reason: "..." }`. Empty source files are deleted.

**Bulk operations:** check stubs with the per-row checkbox (or `x` on the current stub), then use the bulk bar. Bulk **approve** uses the on-disk stub as-is — no per-item overrides. Bulk **reject** uses a single reason for all items.

## Graph view

Cytoscape.js force-directed graph (`fcose` layout) of every bite in `index.json` whose status passes the filter.

- **Node color** = domain (deterministic palette by domain name).
- **Node shape** = status (circle = active, square = deprecated, triangle = superseded).
- **Edge color** = relation type (`relates_to` slate, `depends_on` cyan, `supersedes` amber, `conflicts_with` red).
- Click a node → quick-info tooltip with an **Open in Bite detail →** button.

## Bite detail

For one selected bite:

- Editable frontmatter: statement, domain, tags, status, rationale.
- Outgoing edges with a per-row remove button + an inline "add edge" form (with the right "supersedes will move target to _archive/" confirmation).
- Read-only body preview + a `vscode://file/<abs-path>` button to open the `.md` in your editor for full-body edits.
- Inverse edges (`related_by_others`, `depended_on_by`, etc.) listed in the sidebar.

**Status semantics & file locations** (enforced by `bites-status`):

| Status      | File location                            | Notes                                                       |
|-------------|------------------------------------------|-------------------------------------------------------------|
| active      | `.specify/bites/domains/<domain>/`       | Default.                                                    |
| deprecated  | `.specify/bites/domains/<domain>/`       | Excluded from default queries; file stays in place.         |
| superseded  | `.specify/bites/_archive/<domain>/`      | Auto-set when another bite adds a `supersedes` edge to it.  |

Demoting `superseded` → `active` clears the `source.superseded_by` field and moves the file back under `domains/<domain>/`.

## Keyboard shortcuts

| Key       | Action                                            |
|-----------|---------------------------------------------------|
| `j` / `k` | Next / previous stub (Drafts tab)                 |
| `a`       | Approve current stub                              |
| `r`       | Reject current stub                               |
| `x`       | Toggle selection of current stub                  |
| `e`       | Focus the statement editor                        |
| `g` `d`   | Switch to Drafts tab                              |
| `g` `g`   | Switch to Graph tab                               |
| `g` `r`   | Switch to Bite detail tab                         |
| `?`       | Show shortcuts help                               |
| `Esc`     | Close modals / blur focused field                 |

## Security

- Server binds to `127.0.0.1` only. Passing `--host 0.0.0.0` (or any non-loopback value) causes the process to exit with status 2.
- No authentication — this is a single-user local dev tool. Treat the port like you would a Jupyter notebook.
- All write endpoints shell out to `bash`/`pwsh` helpers that already enforce the same validation bites as the CLI/agent path. There is no separate write surface to audit.

## Rejected drafts

Rejected stubs live at `.specify/bites/_drafts/_rejected/<batch>.yml`. The portal lists rejected files by name and stub count in the Drafts tab's left rail (under the active drafts list), but does not yet provide a restore button — to revive a rejected stub today, move it back into a regular `_drafts/*.yml` file by hand and refresh the portal.

## Out of scope (v1)

- Multi-user / remote access (loopback-only).
- In-portal markdown body editing (use the **Open in VS Code** deep-link).
- Undo beyond the rejected-drafts audit trail.
- Graph image export.
