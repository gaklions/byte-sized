#!/usr/bin/env bash
# bites-index.sh — rebuild .specify/bites/index.json from bite markdown files.
#
# Usage: bites-index.sh
#
# Walks all *.md files under <bites_dir>/domains/** and <bites_dir>/_archive/**,
# parses YAML frontmatter, emits a slim catalog as index.json.
# Inverse edges are materialised so navigation works either direction.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools yq jq

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
mkdir -p "$BITES_DIR"
bs_lock "$BITES_DIR/.index.lock"

tmp_bites="$(mktemp)"
trap 'rm -f "$tmp_bites"' EXIT

echo '[]' > "$tmp_bites"

# Collect every bite file (domains + archive). Drafts are excluded.
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
  jq --argjson r "$enriched" '. + [$r]' "$tmp_bites" > "$tmp_bites.next"
  mv "$tmp_bites.next" "$tmp_bites"
done < <(find "$BITES_DIR/domains" "$BITES_DIR/_archive" -type f -name '*.md' -print0 2>/dev/null || true)

# Materialise inverse edges so the agent can traverse either way.
final="$(jq '
  . as $all
  | map(. as $r
      | .edges.related_by_others       = [ $all[] | select(.id != $r.id) | select((.edges.relates_to     // []) | index($r.id)) | .id ]
      | .edges.depended_on_by          = [ $all[] | select(.id != $r.id) | select((.edges.depends_on     // []) | index($r.id)) | .id ]
      | .edges.superseded_by_others    = [ $all[] | select(.id != $r.id) | select((.edges.supersedes     // []) | index($r.id)) | .id ]
      | .edges.conflicts_with_others   = [ $all[] | select(.id != $r.id) | select((.edges.conflicts_with // []) | index($r.id)) | .id ]
  )
' "$tmp_bites")"

generated_at="$(bs_now_iso)"
jq -n --arg ts "$generated_at" --argjson bites "$final" '
  { schema_version: "1.0", generated_at: $ts, bites: $bites }
' > "$INDEX"

# Stable sort by id for deterministic diffs.
tmp_idx="$(mktemp)"
jq '.bites |= sort_by(.id)' "$INDEX" > "$tmp_idx"
mv "$tmp_idx" "$INDEX"

count="$(jq '.bites | length' "$INDEX")"
echo "byte-sized: indexed $count bite(s) -> $INDEX"
