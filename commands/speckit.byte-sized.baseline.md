---
description: "Brownfield baseline pass: sweep the existing codebase and stage candidate business bites for review."
scripts:
  sh: ../../scripts/bash/bites-baseline.sh
  ps: ../../scripts/powershell/bites-baseline.ps1
---

# /speckit.byte-sized.baseline

One-shot adoption command. Sweep the existing repo (docs, specs, optionally code) and stage candidate business bites into `.specify/bites/_drafts/baseline-*.yml` for human review. Use this when adopting `byte-sized` on a brownfield project so the agent has an initial knowledge graph to navigate before any new spec is written.

This command is **human-gated**: nothing is added to the active graph until the user promotes drafts via `/speckit.byte-sized.add`.

## User Input

$ARGUMENTS

## Steps

1. **Parse flags** from `$ARGUMENTS` (all optional):
   - `--scope docs|specs|code|all|docs+specs` (default: `docs+specs`).
   - `--include "<csv-globs>"` overrides scope defaults.
   - `--exclude "<csv-globs>"` appends to the default exclude list (`node_modules`, `.git`, `dist`, build outputs, the bites dir itself, etc.).
   - `--max-files-per-batch N` (default: 12).
   - `--max-bytes-per-batch N` (default: 65536, i.e. 64 KB).
   - `--dry-run` (default: false) — run discovery only, do not propose or stage bites.

2. **Discover** candidate files:
   - Bash: `{SCRIPT_SH} --discover --scope <scope> [--include ...] [--exclude ...] [--max-files-per-batch N] [--max-bytes-per-batch N]`
   - PowerShell: `{SCRIPT_PS} -Mode discover -Scope <scope> [-Include ...] [-Exclude ...] [-MaxFilesPerBatch N] [-MaxBytesPerBatch N]`
   The script emits JSON `{scope, includes, excludes, totals, batches: [{id, file_count, total_bytes, files}]}`.

3. **Show the discovery summary** to the user: total files, total bytes, batch count, and a per-batch one-liner (`b01: 8 files, 12 KB`). Then ask:
   > "Proceed with extraction across all N batches? (`yes`, `no`, or a comma-separated batch list like `b01,b03`)"
   If the user picks `no` or `--dry-run` was set, stop here.

4. **For each selected batch**, do the following sequentially (do **not** run batches in parallel — keeps token usage predictable):
   1. Read the files in the batch via the standard file tools. Skip any individual file that exceeds 32 KB — instead, sample its first 8 KB and last 4 KB only.
   2. Propose candidate bites. Each candidate **must** be:
      - A single declarative sentence (uses "must", "must not", "always", "never", or equivalent).
      - Tagged with a `domain` value drawn from the configured domain list (`byte-sized-config.yml` → `domains`). Make a best-guess if the source domain is implicit.
      - Tagged with 3–6 lowercase `tags`.
      - Backed by a short `rationale` that quotes or paraphrases the originating evidence (file path + line/section).
      Aim for **at most 5 candidates per batch** — quality over quantity. Prefer bites that are *not already obvious from the spec* (e.g. an enforcement detail buried in a config file, an unwritten convention visible only in commit hooks or CI).
   3. Format the candidates as a YAML array:
      ```yaml
      - statement: "..."
        domain: "..."
        tags: ["...", "..."]
        rationale: |
          Evidence: <file-path>#<section-or-line>
          <one-sentence justification>
      ```
   4. Pipe the YAML to the stage command:
      - Bash: `printf '%s' "$candidates" | {SCRIPT_SH} --stage --batch <batch-id>`
      - PowerShell: `$candidates | {SCRIPT_PS} -Mode stage -Batch <batch-id>`

      **Scratch-file convention.** If your tooling cannot reliably inline a multi-line YAML payload through stdin (most agents will hit this), write the payload to `.specify/bites/.tmp-byte-sized/<batch-id>.yml` first, then `cat`/`Get-Content` that file into the stage command. **Never write scratch files at the repo root** — `.tmp-byte-sized/` belongs under `.specify/bites/` (the directory is pre-created by `/speckit.byte-sized.init`). Delete the scratch file after the stage call succeeds; if the batch fails, leave it in place for inspection.

      The stage call delegates to `bites-extract.sh` which de-duplicates against the existing index (statement token-overlap ≥ 0.7 → dropped) and writes survivors to `.specify/bites/_drafts/baseline-<batch>-<timestamp>.yml`.
   5. Capture the returned `{drafts_file, kept, dropped_as_duplicate}` and accumulate the counts.

5. **Emit the final summary**:
   ```
   ## Baseline pass complete

   - Scanned: <total_files> files across <batches> batches (<total_kb> KB).
   - Proposed: <P> candidates.
   - Staged: <K> drafts (after dedup) across <D> draft files.
   - Dropped as duplicate of existing bites: <X>.

   Drafts staged:
     - .specify/bites/_drafts/baseline-b01-<ts>.yml  (<n1> bites)
     - .specify/bites/_drafts/baseline-b02-<ts>.yml  (<n2> bites)
     ...

   Next steps:
     1. Review each drafts file.
     2. Promote with `/speckit.byte-sized.add` (one per accepted bite) — this allocates the real id and runs the conflict pre-check.
     3. Run `/speckit.byte-sized.analyze` once promoted, to surface coverage and conflicts.
   ```

## Notes

- This command is **not** a hook. It is intended to be run once (or a few times during onboarding); never wire it to a lifecycle hook.
- The discovery script never reads file contents itself — it returns the manifest, and the agent reads each batch via its own file tools. This keeps the script portable (no language-specific parsing) and lets the model judge what is bite-worthy.
- Code scope (`--scope code` or `all`) is **opt-in**. The default scope is `docs+specs` because most projects encode business bites in prose first; code-derived bites tend to be lower-signal and noisier.
- The conflict pre-check runs at *promotion* time (via `/speckit.byte-sized.add`), not at staging time. Staging is intentionally cheap.

## Output

The final summary block from step 5. Do not list every proposed bite — that volume defeats the token-efficiency contract. The user reviews the drafts files directly.
