---
description: "Check graph integrity (ID uniqueness, broken edges, frontmatter conformance)."
scripts:
  sh: ../../scripts/bash/bites-validate.sh
  ps: ../../scripts/powershell/bites-validate.ps1
---

# /speckit.byte-sized.validate

Quick integrity check of the bites graph. Cheaper than `analyze` — no coverage or conflict scan.

## User Input

$ARGUMENTS

## Steps

1. Run:
   - Bash: `{SCRIPT_SH}`
   - PowerShell: `{SCRIPT_PS}`
2. Parse the JSON `{errors, warnings, ok}`.
3. If `ok == true` and `warnings == []`, print `Bites graph is healthy.` and exit.
4. Otherwise, list errors first (one per line, prefixed `ERROR`) then warnings (`WARN`). End with the count summary.
5. Do not attempt automatic fixes. Suggest the relevant manual command for each error class (e.g. "broken edge → `/speckit.byte-sized.link <from> <relation> <to> --remove`").

## Output

A short report. Non-zero exit when errors are present (let the host phase decide whether to abort).
