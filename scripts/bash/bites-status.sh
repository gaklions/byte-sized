#!/usr/bin/env bash
# bites-status.sh — change an existing bite's status; physically move the file
# between domains/<domain>/ and _archive/<domain>/ as needed; regenerate index.
#
# Usage:
#   bites-status.sh --id <BB-...> --status <active|deprecated|superseded> [--reason <text>]
#
# Location bite (mirrors what bites-index.sh already scans):
#   active | deprecated → domains/<domain>/
#   superseded         → _archive/<domain>/
#
# Demoting `superseded` back to `active` clears source.superseded_by.
# Filename is preserved across moves so external links / git history stay stable.
#
# Emits JSON: { id, new_status, old_path, new_path }.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

ID=""
STATUS=""
REASON=""

while (( $# > 0 )); do
  case "$1" in
    --id) ID="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    *) echo "bites-status: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ID" || -z "$STATUS" ]]; then
  echo "bites-status: --id and --status are required" >&2
  exit 2
fi
case "$STATUS" in
  active|deprecated|superseded) ;;
  *) echo "bites-status: invalid status '$STATUS' (active|deprecated|superseded)" >&2; exit 2 ;;
esac

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
bs_lock "$BITES_DIR/.index.lock"

old_path="$(jq -r --arg id "$ID" '.bites[] | select(.id == $id) | .path // ""' "$INDEX")"
[[ -n "$old_path" ]] || { echo "bites-status: $ID not found" >&2; exit 1; }
old_abs="$ROOT/$old_path"

fm_yaml="$(bs_frontmatter "$old_abs")"
body="$(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f>=2{print}' "$old_abs")"
fm_json="$(yq eval -o=json -I=0 '.' - <<< "$fm_yaml")"
domain="$(jq -r '.domain // ""' <<< "$fm_json")"
[[ -n "$domain" ]] || { echo "bites-status: $ID has no domain" >&2; exit 1; }

if [[ "$STATUS" == "active" ]]; then
  fm_json="$(jq '.status = "active" | .source.superseded_by = null' <<< "$fm_json")"
else
  fm_json="$(jq --arg s "$STATUS" '.status = $s' <<< "$fm_json")"
fi
new_fm="$(yq eval -P '.' - <<< "$fm_json")"

filename="$(basename "$old_abs")"
if [[ "$STATUS" == "superseded" ]]; then
  target_dir="$BITES_DIR/_archive/$domain"
else
  target_dir="$BITES_DIR/domains/$domain"
fi
mkdir -p "$target_dir"
new_abs="$target_dir/$filename"

{
  echo "---"
  printf '%s\n' "$new_fm"
  echo "---"
  printf '%s\n' "$body"
} > "$new_abs"

if [[ "$old_abs" != "$new_abs" ]]; then
  rm -f "$old_abs"
fi

"$SCRIPT_DIR/bites-index.sh" >/dev/null

jq -n \
  --arg id "$ID" \
  --arg s "$STATUS" \
  --arg old "${old_abs#"$ROOT/"}" \
  --arg new "${new_abs#"$ROOT/"}" \
  '{id: $id, new_status: $s, old_path: $old, new_path: $new}'
