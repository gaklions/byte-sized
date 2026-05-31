#!/usr/bin/env bash
# bites-promote.sh — promote one draft stub to an active bite.
#
# Usage:
#   bites-promote.sh --from-file <_drafts/foo.yml> --index <N> [--overrides-json <json>]
#
# Reads stub N from the YAML-array draft file, merges optional overrides
# (a JSON object, deep-merged on top of the stub), pipes the result into
# bites-add.sh --from-stdin (which allocates the id, writes the .md, and
# regenerates the index). On success, removes stub N from the source draft;
# deletes the source file if it becomes empty.
#
# Emits JSON: { id, path, draft_file, remaining_stubs }.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

FROM_FILE=""
INDEX_N=""
OVERRIDES="{}"

while (( $# > 0 )); do
  case "$1" in
    --from-file) FROM_FILE="$2"; shift 2 ;;
    --index) INDEX_N="$2"; shift 2 ;;
    --overrides-json) OVERRIDES="$2"; shift 2 ;;
    *) echo "bites-promote: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$FROM_FILE" || -z "$INDEX_N" ]]; then
  echo "bites-promote: --from-file and --index are required" >&2
  exit 2
fi

ROOT="$(bs_repo_root)"
abs_from="$FROM_FILE"
if [[ "$abs_from" != /* ]]; then abs_from="$ROOT/$abs_from"; fi
[[ -f "$abs_from" ]] || { echo "bites-promote: file not found: $abs_from" >&2; exit 1; }

stubs_json="$(yq eval -o=json '.' "$abs_from")"
[[ "$(jq -r 'type' <<< "$stubs_json")" == "array" ]] \
  || { echo "bites-promote: $abs_from is not a YAML array" >&2; exit 1; }
total="$(jq 'length' <<< "$stubs_json")"
if (( INDEX_N < 0 || INDEX_N >= total )); then
  echo "bites-promote: index $INDEX_N out of range (have $total)" >&2
  exit 1
fi

stub="$(jq --argjson i "$INDEX_N" '.[$i]' <<< "$stubs_json")"
merged="$(jq -n --argjson s "$stub" --argjson o "$OVERRIDES" '$s * $o')"

# Hand the merged stub to bites-add. It owns id allocation, slug, and index regen.
result="$(yq eval -P '.' - <<< "$merged" | "$SCRIPT_DIR/bites-add.sh" --from-stdin)"

# Drop the promoted stub from the source draft.
remaining="$(jq --argjson i "$INDEX_N" 'del(.[$i])' <<< "$stubs_json")"
remaining_len="$(jq 'length' <<< "$remaining")"
if (( remaining_len == 0 )); then
  rm -f "$abs_from"
else
  yq eval -P '.' - <<< "$remaining" > "$abs_from"
fi

new_id="$(jq -r '.id' <<< "$result")"
new_path="$(jq -r '.path' <<< "$result")"
jq -n \
  --arg id "$new_id" \
  --arg path "$new_path" \
  --arg draft "${abs_from#"$ROOT/"}" \
  --argjson rem "$remaining_len" \
  '{id: $id, path: $path, draft_file: $draft, remaining_stubs: $rem}'
