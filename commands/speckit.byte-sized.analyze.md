---
description: "Run validate + coverage + conflict detection across the graph."
scripts:
  sh: ../../scripts/bash/rules-validate.sh
  ps: ../../scripts/powershell/rules-validate.ps1
  coverage_sh: ../../scripts/bash/rules-coverage.sh
  coverage_ps: ../../scripts/powershell/rules-coverage.ps1
  conflict_sh: ../../scripts/bash/rules-conflict.sh
  conflict_ps: ../../scripts/powershell/rules-conflict.ps1
---

# /speckit.byte-sized.analyze

Full analysis pass over the rules graph: integrity + coverage of the active feature + cross-rule conflicts.

## User Input

$ARGUMENTS

## Steps

1. **Validate** — run:
   - Bash: `{SCRIPT_SH}`
   - PowerShell: `{SCRIPT_PS}`
   Capture the JSON `{errors, warnings, ok}`.
2. **Coverage** — resolve the target file:
   - If `$ARGUMENTS` contains `--file <path>`, use it.
   - Else use `SPECIFY_FEATURE` to locate the active feature's `tasks.md` (preferred) or `spec.md`. If neither exists, skip coverage and note it in the report.
   Then run:
   - Bash: `{SCRIPT_COVERAGE_SH} --file <path>`
   - PowerShell: `{SCRIPT_COVERAGE_PS} -File <path>`
3. **Conflict** — run across the whole graph:
   - Bash: `{SCRIPT_CONFLICT_SH}`
   - PowerShell: `{SCRIPT_CONFLICT_PS}`
4. Render a single markdown report:
   ```
   ## Rules graph analysis

   ### Integrity
   - errors: <N>; warnings: <M>
   - (list each)

   ### Coverage of <file>
   - Uncovered FR/NFR/TASK ids: <list>
   - Orphan rules (no source): <list>
   - Per-requirement coverage: <table>

   ### Conflicts
   - <from> ↔ <to> (domain=<d>) — triggered by: <antonym pair>
   ```
5. If integrity errors exist, exit non-zero so the calling phase (e.g. `after_analyze`) knows to flag the user.

## Output

The markdown report. Do not auto-fix anything; this is a read-only analysis.
