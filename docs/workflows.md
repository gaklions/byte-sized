# Workflows

How the `byte-sized` extension participates in the Spec Kit lifecycle.

## Token-efficiency contract

The agent **never** loads the entire rules corpus. Every hook returns a *projection* — a JSON array of `{id, statement, domain, tags, status}` capped by `relevance.max_results` (default 12). The agent fetches a full rule body (`speckit.byte-sized.show <id>`) only when it decides it needs the rationale, examples, or neighbours to make a specific decision.

## Phase-by-phase flow

```
constitution  (no hook)
     │
     ▼
specify ──before──► surface  (compact list of rules whose tags/domain
     │              overlap with the seed prompt)
     │
     ▼  drafts the spec, citing relevant BR-* ids
     │
     ├──after──► extract  (optional: stage candidate rules to _drafts/)
     ▼
clarify
     │
     ├──after──► extract  (optional: stage rules captured from Q/A)
     ▼
plan ──before──► surface  (domain hint: architecture, tech)
     ▼
tasks  (no hook)
     ▼
analyze ──after──► analyze  (validate + coverage + conflict)
     ▼
implement ──before──► surface  (domain hint: code, compliance)
     ▼
done
```

## Surfacing rules (`before_*` hooks)

`speckit.byte-sized.surface` runs silently before each gated phase:

1. Reads `SPECIFY_FEATURE` (or the active feature directory) to locate the source artefact (spec/plan/tasks).
2. Extracts seed tokens from the artefact (or from `$ARGUMENTS` for `before_specify`).
3. Invokes `rules-query` with `--text <tokens> --domain <phase-hint> --status active --limit <max_results>`.
4. Emits a compact JSON block to the host command's context. Host commands are expected to cite matching rule ids using the format `[BR-AUTH-001]` in their generated artefacts.

## Capturing rules (`after_specify`, `after_clarify`)

`speckit.byte-sized.extract` is human-gated:

1. The agent reads the just-written spec/clarify file.
2. It proposes candidate rules (one-sentence statements + draft rationale + domain guess + tags).
3. Each candidate is written to `.specify/rules/_drafts/<feature>-<timestamp>.yml` as a YAML list.
4. The user reviews; approved drafts are promoted via `rules-add` (which allocates the real id, runs conflict pre-check, and updates `index.json`).
5. Rejected drafts stay in `_drafts/` for audit (or can be deleted manually).

## Analysing the graph (`after_analyze`)

`speckit.byte-sized.analyze` runs three passes and emits a single report:

1. **Validate** — ID uniqueness, frontmatter conformance, broken edges, dangling supersession.
2. **Coverage** — for each `FR-*` in the active feature's spec/tasks, list the covering rule ids. Flag uncovered FRs and orphan rules.
3. **Conflict** — for each active rule, check same-domain rules with overlapping tags for lexical opposition markers. Flag candidate conflicts for human review.

## Brownfield baseline

`/speckit.byte-sized.baseline` is a one-shot adoption command for existing projects:

1. The script walks the repo with configurable include/exclude globs, groups files into bounded batches (default: 12 files / 64 KB per batch), and returns a JSON manifest.
2. The agent shows the user the manifest and asks which batches to process.
3. For each accepted batch, the agent reads the files, proposes at most ~5 high-signal candidate rules (declarative, domain-tagged, evidence-cited), and pipes them to the same staging logic used by `extract`.
4. Drafts land in `.specify/rules/_drafts/baseline-<batch>-<ts>.yml` for human promotion via `/speckit.byte-sized.add`.

Default scope is `docs+specs` (READMEs, `docs/**`, `specs/**`, ADRs, CONTRIBUTING). `--scope all` adds source folders; `--include`/`--exclude` override the globs entirely.

## Manual entry points

Beyond the hooks, any of the commands can be invoked directly by the user:

- `/speckit.byte-sized.init` — once per project to scaffold storage.
- `/speckit.byte-sized.baseline` — once per project (brownfield adoption) to seed the graph from existing artefacts.
- `/speckit.byte-sized.add` — guided, conflict-checked rule creation.
- `/speckit.byte-sized.query <text>` — ad-hoc lookup from the agent.
- `/speckit.byte-sized.list` — human-facing summary.
- `/speckit.byte-sized.show BR-AUTH-001 --neighbors 2` — drill in.
- `/speckit.byte-sized.link BR-AUTH-001 depends_on BR-SEC-014` — manage edges.
- `/speckit.byte-sized.validate` — graph integrity only (cheaper than `analyze`).

## What this extension does **not** do (v1)

- No semantic / embedding-based search (lexical only).
- No external graph database or MCP server (everything runs from local scripts).
- No silent rule writes (extraction always stages to `_drafts/` for human review).
- No cross-repository rule sharing (one graph per project).
- No automatic supersession (use `link` + status flip explicitly).
