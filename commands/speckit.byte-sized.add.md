---
description: "Add a new business rule (with conflict pre-check) and update the graph index."
scripts:
  sh: ../../scripts/bash/rules-add.sh
  ps: ../../scripts/powershell/rules-add.ps1
  conflict_sh: ../../scripts/bash/rules-conflict.sh
  conflict_ps: ../../scripts/powershell/rules-conflict.ps1
---

# /speckit.byte-sized.add

Capture a new business rule into the graph.

## User Input

$ARGUMENTS

## Steps

1. Parse `$ARGUMENTS`. Accept either a free-form natural-language description of the rule, or a structured form with `statement=...`, `domain=...`, `tags=...`, `rationale=...`. If the user gave only free-form text, ask **at most three** clarifying questions to fill in: `statement` (one sentence, declarative), `domain` (one of the configured domains), `tags` (3–6 lowercase tokens). Skip rationale if obvious from context — it can be edited later.
2. Build a YAML stub:
   ```yaml
   statement: "..."
   rationale: "..."
   domain: "..."
   tags: ["...","..."]
   status: "active"
   ```
3. Write the stub to a temp file and run the conflict pre-check:
   - Bash: `{SCRIPT_CONFLICT_SH} --stub <tmp.yml>`
   - PowerShell: `{SCRIPT_CONFLICT_PS} -Stub <tmp.yml>`
   If the result contains any candidate conflicts, **stop** and show them to the user. Ask whether to proceed anyway, refine the statement, or link the new rule with `conflicts_with` after creation.
4. Once approved, invoke the add script via stdin:
   - Bash: `cat <tmp.yml> | {SCRIPT_SH} --from-stdin`
   - PowerShell: `Get-Content <tmp.yml> | {SCRIPT_PS} -FromStdin`
5. The script prints `{id, path}`. Echo this and offer next steps:
   - `/speckit.byte-sized.show <id>` to view the new rule.
   - `/speckit.byte-sized.link <id> <relation> <other-id>` to wire it into the graph.

## Output

The new rule id (e.g. `BR-AUTH-007`) and its file path. If a conflict was detected and the user chose to add anyway, also surface the conflicting rule ids.
