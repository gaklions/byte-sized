---
description: "Search the rules graph and return a compact, token-efficient projection."
scripts:
  sh: ../../scripts/bash/rules-query.sh
  ps: ../../scripts/powershell/rules-query.ps1
---

# /speckit.byte-sized.query

Search the business rules graph.

## User Input

$ARGUMENTS

## Steps

1. Parse `$ARGUMENTS` for optional flags:
   - free-text query (everything not matching a `--flag`) becomes `--text`
   - `--tags a,b`, `--domain x,y`, `--status active,draft`, `--limit N`, `--include-drafts`, `--ids id1,id2`
2. Run the query script:
   - Bash: `{SCRIPT_SH} [--text "..."] [--tags ...] [--domain ...] [--status ...] [--limit ...]`
   - PowerShell: `{SCRIPT_PS} -Text "..." -Tags "..." -Domain "..." -Status "..." -Limit N`
3. The script returns a JSON array. Display it as a compact table: `id | statement (truncated to 100 chars) | domain | tags | score`.
4. **Do not** auto-fetch full rule bodies. If the user asks for details, suggest `/speckit.byte-sized.show <id>`.
5. If the projection appears to be truncated (more than `--limit` matches exist), tell the user how to narrow it (more specific `--tags`, `--domain`, or a longer `--text` query).

## Output

A compact list — one line per rule — ordered by score descending. No bodies, no rationale; just the projection fields.
