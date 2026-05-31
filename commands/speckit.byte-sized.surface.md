---
description: "Hook-only entry point: surface a compact projection of relevant bites for the active phase."
scripts:
  sh: ../../scripts/bash/bites-query.sh
  ps: ../../scripts/powershell/bites-query.ps1
---

# /speckit.byte-sized.surface

**Hook-only.** Used by `before_specify`, `before_plan`, and `before_implement` to inject a tiny, relevance-ranked projection of business bites into the active phase's context. Not intended for direct user invocation (use `/speckit.byte-sized.query` instead).

## User Input

$ARGUMENTS

## Inputs

- `SPECIFY_FEATURE` env (set by spec-kit) — used to locate the current spec/plan/tasks file.
- `$ARGUMENTS` — phase hint, e.g. `"phase=before_plan"` or seed text for `before_specify`.

## Steps

1. Determine the **phase** from `$ARGUMENTS` (`before_specify` / `before_plan` / `before_implement`). Default to `before_specify` if not provided.
2. Determine the **domain hint** from `byte-sized-config.yml` under `phase_hints.<phase>`. Pass it as `--domain` (comma-separated).
3. Determine **seed text**:
   - `before_specify`: use the user's free-form prompt that initiated `/speckit.specify` (passed through `$ARGUMENTS`).
   - `before_plan`: read `specs/<feature>/spec.md` and use the first 4 KB.
   - `before_implement`: read `specs/<feature>/plan.md` then `tasks.md` and use the first 4 KB combined.
4. Run the query script with strict caps (no `--include-drafts`, `--status active`, default `--limit`):
   - Bash: `{SCRIPT_SH} --text "<seed>" --domain "<hint>" --status active`
   - PowerShell: `{SCRIPT_PS} -Text "<seed>" -Domain "<hint>" -Status active`
5. Emit the JSON array into the host command's context, wrapped in a short header:
   ```
   ## Relevant business bites (byte-sized projection)
   _Showing top N by relevance. Use `/speckit.byte-sized.show <id>` for details._
   <JSON>
   ```
6. **Do not** fetch any full bite bodies. Do not call `bites-get`. The host command (`specify`, `plan`, `implement`) is responsible for citing bite ids it actually uses with `[BB-...]` markers.
7. If the projection JSON exceeds `relevance.max_projection_kb` (config; default 8 KB), truncate to the first N entries and append a footer: `_(truncated; refine with --tags or --domain)_`.

## Output

A single fenced JSON block (the projection). No prose beyond the header and optional truncation footer. Keep output as small as possible — this runs on every gated phase.
