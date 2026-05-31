---
description: "Scaffold the .specify/bites/ business bites graph for this project."
scripts:
  sh: ../../scripts/bash/bites-init.sh
  ps: ../../scripts/powershell/bites-init.ps1
---

# /speckit.byte-sized.init

Initialise the `byte-sized` knowledge graph in this Spec Kit project.

## User Input

$ARGUMENTS

## Steps

1. Run the init script to scaffold storage:
   - Bash: `{SCRIPT_SH}`
   - PowerShell: `{SCRIPT_PS}`
2. Report the created paths back to the user (`bites_dir`, `extension_dir`, `initialized`).
3. If `$ARGUMENTS` is non-empty, treat it as the user's preferred starting domain set and append any new entries (lowercase) to `.specify/extensions/byte-sized/byte-sized-config.yml` under `domains:` (only if not already present). Do not duplicate.
4. Show the user the slim catalog with `speckit.byte-sized.list` (it will be empty on first init).

## Output

A one-line confirmation listing the bites directory and a hint to run `/speckit.byte-sized.add` to capture the first bite.
