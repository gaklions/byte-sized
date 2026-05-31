---
description: "Author a business bite in plain English (or structured form); the agent classifies it, runs a conflict pre-check, and updates the graph index."
scripts:
  sh: ../../scripts/bash/bites-add.sh
  ps: ../../scripts/powershell/bites-add.ps1
  conflict_sh: ../../scripts/bash/bites-conflict.sh
  conflict_ps: ../../scripts/powershell/bites-conflict.ps1
---

# /speckit.byte-sized.add

Capture a new business bite into the graph. The primary input mode is **plain English** — type the rule and the agent classifies it (domain + tags) and places the file. A structured-form shortcut is available for power users.

## User Input

$ARGUMENTS

## Steps

1. **Load the configured domain list.** Read `.specify/extensions/byte-sized/byte-sized-config.yml` and capture the `domains:` array. This is the allow-list the agent classifies against. If the file is missing, stop and tell the user to run `/speckit.byte-sized.init` first.

2. **Parse `$ARGUMENTS`.** Two input modes are supported:
   - **Free-form (primary):** A natural-language sentence describing the rule, e.g. `Admins must use MFA for production access`. Go to step 3.
   - **Structured (power-user shortcut):** One or more `key=value` pairs from `statement=...`, `domain=...`, `tags=...`, `rationale=...`. Use the supplied values verbatim, fill any missing required field (`statement`, `domain`) by inference per step 3, and go straight to step 4.

3. **Classify autonomously.** From the free-form input, infer:
   - `statement`: rewrite the user's sentence as a single declarative line using "must / must not / always / never". Preserve the user's intent and concrete nouns; do not soften or generalise.
   - `domain`: pick the single best match from the configured domain list by topical fit against the statement's salient nouns and verbs. If no configured domain is a confident match, take the **novel-domain branch** (step 3a).
   - `tags`: 3–6 lowercase tokens drawn from the statement's salient terms (nouns, qualifiers, technologies). Dedupe, drop stop-words, prefer single tokens over phrases.
   - `rationale`: leave empty unless the user explicitly supplied one. **Never invent rationale text.**

   3a. **Novel-domain branch.** If no configured domain is a confident match, surface the top 1–2 closest existing domains from the allow-list and ask the user exactly one question: pick one of the suggestions, supply a different existing domain verbatim, or supply a brand-new domain name. If the user supplies a brand-new value, accept it for this bite but tell them that `bites-validate` will warn until they add it to the `domains:` list in `byte-sized-config.yml` and re-run validation.

4. **Confirm once.** Present the proposed bite as a single block:
   ```
   statement: <inferred>
   domain:    <inferred>
   tags:      [<inferred>]
   rationale: <user-supplied or empty>
   ```
   Ask exactly one question: **"Add this bite? (yes / no / edit)"**. On `yes` proceed to step 5. On `no` abort with no file changes. On `edit` collect the user's overrides for any of the four fields, then re-confirm.

5. **Build the YAML stub:**
   ```yaml
   statement: "..."
   rationale: "..."
   domain: "..."
   tags: ["...","..."]
   status: "active"
   ```

6. Write the stub to a scratch file under `.specify/bites/.tmp-byte-sized/<slug>.yml` (the directory is pre-created by `/speckit.byte-sized.init`; **never write scratch files at the repo root**) and run the conflict pre-check:
   - Bash: `{SCRIPT_CONFLICT_SH} --stub .specify/bites/.tmp-byte-sized/<slug>.yml`
   - PowerShell: `{SCRIPT_CONFLICT_PS} -Stub .specify/bites/.tmp-byte-sized/<slug>.yml`
   If the result contains any candidate conflicts, **stop** and show them to the user. Ask whether to proceed anyway, refine the statement, or link the new bite with `conflicts_with` after creation.

7. Once approved, invoke the add script via stdin:
   - Bash: `cat .specify/bites/.tmp-byte-sized/<slug>.yml | {SCRIPT_SH} --from-stdin`
   - PowerShell: `Get-Content .specify/bites/.tmp-byte-sized/<slug>.yml | {SCRIPT_PS} -FromStdin`
   Delete the scratch file after a successful add; on failure, leave it in place for inspection.

8. The script prints `{id, path}`. Echo this and offer next steps:
   - `/speckit.byte-sized.show <id>` to view the new bite.
   - `/speckit.byte-sized.link <id> <relation> <other-id>` to wire it into the graph.

## Examples

**Free-form (primary):**

```text
/speckit.byte-sized.add Admins must use MFA for production access
```

The agent classifies the input and shows a single confirmation:

```text
statement: Admins must use MFA for production access.
domain:    auth
tags:      [admin, mfa, production, access]
rationale:

Add this bite? (yes / no / edit)
```

On `yes`, the conflict pre-check runs and the bite is written.

**Structured (power-user shortcut):**

```text
/speckit.byte-sized.add statement="Admins must use MFA for production access" domain=auth tags=admin,mfa,production
```

Skips classification and goes straight to the confirmation gate.

## Output

The new bite id (e.g. `BB-AUTH-007`) and its file path. If a conflict was detected and the user chose to add anyway, also surface the conflicting bite ids.
