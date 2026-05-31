---
description: "Launch the byte-sized review portal — a local web UI for triaging drafts and navigating the bite graph."
scripts:
  sh: ../../scripts/bash/bites-portal.sh
  ps: ../../scripts/powershell/bites-portal.ps1
---

# /speckit.byte-sized.portal

Start the local review portal. The portal is a **human-initiated** tool — never auto-invoke it from a lifecycle hook.

## User Input

$ARGUMENTS

## When to use this

Use the portal whenever a human needs to:

- triage a large backlog of draft stubs (especially after `/speckit.byte-sized.baseline`),
- navigate the active bite graph visually,
- change a bite's status / edges / frontmatter without opening individual `.md` files,
- review what's been rejected and why.

For one-off, agent-driven mutations, prefer the existing `add` / `link` / `extract` / `analyze` commands — they already produce the same on-disk changes.

## Requirements

- Python `>= 3.10` on the user's PATH (the portal is a single-file stdlib server).
- All existing requirements (`jq`, `yq`, the byte-sized helper scripts).

## Steps

1. Confirm Python is installed (`python3 --version` or `python --version`). If it is not, instruct the user to install it and stop — do **not** attempt to install a runtime on their behalf.
2. Launch the wrapper:
   - Bash: `{SCRIPT_SH}` (optionally `--port <N>`, `--no-open`)
   - PowerShell: `{SCRIPT_PS}` (optionally `-Port <N>`, `-NoOpen`)
3. Report the URL back to the user (`http://127.0.0.1:<port>/`) and tell them the server is loopback-only.
4. Wait for the user to finish; do not poll the API yourself, and do not request mutations on their behalf — the portal exists so the human can drive review directly.
5. When the user reports they're done, instruct them to stop the server with `Ctrl+C` in the launching terminal.

## Output

A single line with the portal URL and a reminder that the server is local-only.

## Notes

- The portal shells out to the same `bites-add` / `bites-link` / `bites-index` / `bites-promote` / `bites-reject` / `bites-status` / `bites-edit` scripts the agent would use. There is no separate lifecycle path.
- Every mutation regenerates `index.json`, so the agent's next `query`/`surface` call already sees the new state.
- Rejected draft stubs are moved to `.specify/bites/_drafts/_rejected/<original-filename>.yml` with `rejected: { at, reason }` audit fields appended.
