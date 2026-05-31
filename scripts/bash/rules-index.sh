#!/usr/bin/env bash
# rules-index.sh — rebuild .specify/rules/index.json from rule markdown files.
#
# Usage: rules-index.sh
#
# Walks all *.md files under <rules_dir>/domains/** and <rules_dir>/_archive/**,
# parses YAML frontmatter, emits a slim catalog as index.json.
# Inverse edges are materialised so navigation works either direction.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools yq jq

ROOT="$(bs_repo_root)"
RULES_DIR="$(bs_rules_dir "$ROOT")"
INDEX="$RULES_DIR/index.json"
mkdir -p "$RULES_DIR"
bs_lock "$RULES_DIR/.index.lock"

tmp_rules="$(mktemp)"
trap 'rm -f "$tmp_rules"' EXIT

echo '[]' > "$tmp_rules"

# Collect every rule file (domains + archive). Drafts are excluded.
while IFS= read -r -d '' f; do
  fm_json="$(bs_frontmatter_json "$f" 2>/dev/null || echo '')"
  if [[ -z "$fm_json" || "$fm_json" == "null" ]]; then
    echo "byte-sized: skipping $f (no frontmatter)" >&2
    continue
  fi
  rel_path="${f#"$ROOT/"}"
  enriched="$(jq --arg path "$rel_path" '
    {
      id: .id,
      statement: .statement,
      domain: .domain,
      tags: (.tags // []),
      status: (.status // "active"),
      source: (.source // {}),
      edges: (.edges // {}),
      path: $path
    }
  ' <<< "$fm_json")"
  jq --argjson r "$enriched" '. + [$r]' "$tmp_rules" > "$tmp_rules.next"
  mv "$tmp_rules.next" "$tmp_rules"
done < <(find "$RULES_DIR/domains" "$RULES_DIR/_archive" -type f -name '*.md' -print0 2>/dev/null || true)

# Materialise inverse edges so the agent can traverse either way.
final="$(jq '
  . as $all
  | map(. as $r
      | .edges.related_by_others       = [ $all[] | select(.id != $r.id) | select((.edges.relates_to     // []) | index($r.id)) | .id ]
      | .edges.depended_on_by          = [ $all[] | select(.id != $r.id) | select((.edges.depends_on     // []) | index($r.id)) | .id ]
      | .edges.superseded_by_others    = [ $all[] | select(.id != $r.id) | select((.edges.supersedes     // []) | index($r.id)) | .id ]
      | .edges.conflicts_with_others   = [ $all[] | select(.id != $r.id) | select((.edges.conflicts_with // []) | index($r.id)) | .id ]
  )
' "$tmp_rules")"

generated_at="$(bs_now_iso)"
jq -n --arg ts "$generated_at" --argjson rules "$final" '
  { schema_version: "1.0", generated_at: $ts, rules: $rules }
' > "$INDEX"

# Stable sort by id for deterministic diffs.
tmp_idx="$(mktemp)"
jq '.rules |= sort_by(.id)' "$INDEX" > "$tmp_idx"
mv "$tmp_idx" "$INDEX"

count="$(jq '.rules | length' "$INDEX")"
echo "byte-sized: indexed $count rule(s) -> $INDEX"
