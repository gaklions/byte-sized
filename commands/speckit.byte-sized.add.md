---
description: "Add a new business bite (with conflict pre-check) and update the graph index."
scripts:
  sh: ../../scripts/bash/bites-add.sh
  ps: ../../scripts/powershell/bites-add.ps1
  conflict_sh: ../../scripts/bash/bites-conflict.sh
  conflict_ps: ../../scripts/powershell/bites-conflict.ps1
---

# /speckit.byte-sized.add

Capture a new business bite into the graph.

## User Input

$ARGUMENTS

## Steps

1. Parse `$ARGUMENTS`. Accept either a free-form natural-language description of the bite, or a structured form with `statement=...`, `domain=...`, `tags=...`, `rationale=...`. If the user gave only free-form text, ask **at most three** clarifying questions to fill in: `statement` (one sentence, declarative), `domain` (one of the configured domains), `tags` (3–6 lowercase tokens). Skip rationale if obvious from context — it can be edited later.
2. Build a YAML stub:
   ```yaml
   statement: "..."
   rationale: "..."
   domain: "..."
   tags: ["...","..."]
   status: "active"
   ```
3. Write the stub to a scratch file under `.specify/bites/.tmp-byte-sized/<slug>.yml` (the directory is pre-created by `/speckit.byte-sized.init`; **never write scratch files at the repo root**) and run the conflict pre-check:
   - Bash: `{SCRIPT_CONFLICT_SH} --stub .specify/bites/.tmp-byte-sized/<slug>.yml`
   - PowerShell: `{SCRIPT_CONFLICT_PS} -Stub .specify/bites/.tmp-byte-sized/<slug>.yml`
   If the result contains any candidate conflicts, **stop** and show them to the user. Ask whether to proceed anyway, refine the statement, or link the new bite with `conflicts_with` after creation.
4. Once approved, invoke the add script via stdin:
   - Bash: `cat .specify/bites/.tmp-byte-sized/<slug>.yml | {SCRIPT_SH} --from-stdin`
   - PowerShell: `Get-Content .specify/bites/.tmp-byte-sized/<slug>.yml | {SCRIPT_PS} -FromStdin`
   Delete the scratch file after a successful add; on failure, leave it in place for inspection.
5. The script prints `{id, path}`. Echo this and offer next steps:
   - `/speckit.byte-sized.show <id>` to view the new bite.
   - `/speckit.byte-sized.link <id> <relation> <other-id>` to wire it into the graph.

## Output

The new bite id (e.g. `BB-AUTH-007`) and its file path. If a conflict was detected and the user chose to add anyway, also surface the conflicting bite ids.
