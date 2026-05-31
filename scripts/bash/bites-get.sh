#!/usr/bin/env bash
# bites-get.sh — fetch one or more bites by id, optionally with N-hop neighbours.
#
# Usage: bites-get.sh <id> [<id> ...] [--neighbors N] [--format json|markdown]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

NEIGHBORS=0
FORMAT="json"
IDS=()

while (( $# > 0 )); do
  case "$1" in
    --neighbors) NEIGHBORS="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --*) echo "bites-get: unknown flag: $1" >&2; exit 2 ;;
    *) IDS+=("$1"); shift ;;
  esac
done

if (( ${#IDS[@]} == 0 )); then
  echo "bites-get: at least one id is required" >&2
  exit 2
fi

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
if [[ ! -f "$INDEX" ]]; then
  echo "byte-sized: index missing; run bites-index.sh" >&2
  exit 1
fi

# Expand to include neighbours up to NEIGHBORS hops.
ids_json="$(printf '%s\n' "${IDS[@]}" | jq -R . | jq -s 'unique')"
expanded="$ids_json"
hop=0
while (( hop < NEIGHBORS )); do
  expanded="$(jq --slurpfile idx "$INDEX" --argjson seeds "$expanded" '
    ($idx[0].bites) as $all
    | ($seeds + (
        $all | map(select(.id as $i | $seeds | index($i)))
             | map(.edges // {})
             | map([
                 (.relates_to // []),
                 (.depends_on // []),
                 (.supersedes // []),
                 (.conflicts_with // []),
                 (.related_by_others // []),
                 (.depended_on_by // []),
                 (.superseded_by_others // []),
                 (.conflicts_with_others // [])
               ] | add)
             | add // []
      )) | unique
  ' <<< "$expanded")"
  hop=$((hop + 1))
done

# Resolve each id to its file path via the index, then assemble output.
results='[]'
for id in $(jq -r '.[]' <<< "$expanded"); do
  path="$(jq -r --arg id "$id" '.bites[] | select(.id == $id) | .path // ""' "$INDEX")"
  if [[ -z "$path" || ! -f "$ROOT/$path" ]]; then
    echo "bites-get: id '$id' not found in index" >&2
    continue
  fi
  fm_json="$(bs_frontmatter_json "$ROOT/$path")"
  body="$(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f>=2{print}' "$ROOT/$path")"
  rec="$(jq -n --argjson fm "$fm_json" --arg body "$body" --arg path "$path" '$fm + {body: $body, path: $path}')"
  results="$(jq --argjson r "$rec" '. + [$r]' <<< "$results")"
done

if [[ "$FORMAT" == "markdown" ]]; then
  jq -r '.[] | "---\n" + (del(.body, .path) | tojson) + "\n---\n\n" + (.body // "") + "\n\n"' <<< "$results"
else
  printf '%s\n' "$results"
fi
