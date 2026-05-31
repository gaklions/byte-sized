---
description: "Show a single bite plus optional N-hop neighbours."
scripts:
  sh: ../../scripts/bash/bites-get.sh
  ps: ../../scripts/powershell/bites-get.ps1
---

# /speckit.byte-sized.show

Display one or more bites in full, with optional graph-neighbour expansion.

## User Input

$ARGUMENTS

## Steps

1. Parse `$ARGUMENTS`. Tokens matching the bite id pattern (`^[A-Z]+-[A-Z]+-\d{3}$`) become positional ids. Recognise `--neighbors N` (default 0) and `--format markdown|json` (default `markdown`).
2. Invoke:
   - Bash: `{SCRIPT_SH} <id> [<id> ...] [--neighbors N] [--format markdown]`
   - PowerShell: `{SCRIPT_PS} <id> [<id> ...] -Neighbors N -Format markdown`
3. Render the markdown output verbatim to the user.
4. When neighbours were expanded, prepend a one-line summary: `Showing <N> bite(s): <id1>, <id2>, ... (expanded to <M> hops).`

## Output

Full markdown of each requested bite (frontmatter as JSON block + body). No re-formatting beyond what the script emits.
