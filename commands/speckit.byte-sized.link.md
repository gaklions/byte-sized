---
description: "Add or remove an edge between two rules."
scripts:
  sh: ../../scripts/bash/rules-link.sh
  ps: ../../scripts/powershell/rules-link.ps1
---

# /speckit.byte-sized.link

Manage edges between business rules.

## User Input

$ARGUMENTS

## Steps

1. Parse `$ARGUMENTS` as `<from-id> <relation> <to-id> [--remove]`.
   - `<relation>` must be one of: `relates_to`, `supersedes`, `depends_on`, `conflicts_with`.
2. If any token is missing or invalid, ask the user a single clarifying question (do not guess relation semantics).
3. Run:
   - Bash: `{SCRIPT_SH} <from-id> <relation> <to-id> [--remove]`
   - PowerShell: `{SCRIPT_PS} -From <from-id> -Relation <relation> -To <to-id> [-Remove]`
4. When the relation is `supersedes` and `--remove` is **not** set, warn the user that the script will also flip the target's `status` to `superseded` and set `source.superseded_by`.

## Output

The script prints `byte-sized: added <from> -[<rel>]-> <to>` (or `removed`). Surface that verbatim and remind the user to run `/speckit.byte-sized.validate` if they made multiple link changes.
