#!/usr/bin/env bash
# bites-edit.sh — edit frontmatter fields of an existing bite in place.
#
# Usage:
#   bites-edit.sh --id <BB-...> [--statement <s>] [--rationale-file <path>]
#                  [--domain <d>] [--tags-csv <a,b,c>]
#
# Filenames are stable: editing the statement does NOT re-slug the filename
# (preserves git history and external links). Changing the domain moves the
# file under the new domains/<domain>/ (or _archive/<domain>/ if the current
# status is superseded), preserving the filename.
#
# The markdown body is left untouched.
#
# Emits JSON: { id, old_path, new_path, changed }.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

ID=""
STATEMENT=""
RATIONALE_FILE=""
DOMAIN=""
TAGS_CSV=""
HAS_STATEMENT=0
HAS_DOMAIN=0
HAS_TAGS=0
HAS_RATIONALE=0

while (( $# > 0 )); do
  case "$1" in
    --id) ID="$2"; shift 2 ;;
    --statement) STATEMENT="$2"; HAS_STATEMENT=1; shift 2 ;;
    --rationale-file) RATIONALE_FILE="$2"; HAS_RATIONALE=1; shift 2 ;;
    --domain) DOMAIN="$2"; HAS_DOMAIN=1; shift 2 ;;
    --tags-csv) TAGS_CSV="$2"; HAS_TAGS=1; shift 2 ;;
    *) echo "bites-edit: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ID" ]] || { echo "bites-edit: --id is required" >&2; exit 2; }

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
bs_lock "$BITES_DIR/.index.lock"

old_path="$(jq -r --arg id "$ID" '.bites[] | select(.id == $id) | .path // ""' "$INDEX")"
[[ -n "$old_path" ]] || { echo "bites-edit: $ID not found" >&2; exit 1; }
old_abs="$ROOT/$old_path"

fm_yaml="$(bs_frontmatter "$old_abs")"
body="$(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f>=2{print}' "$old_abs")"
fm_json="$(yq eval -o=json -I=0 '.' - <<< "$fm_yaml")"
status="$(jq -r '.status // "active"' <<< "$fm_json")"
old_domain="$(jq -r '.domain // ""' <<< "$fm_json")"
new_domain="$old_domain"

changed='[]'
if (( HAS_STATEMENT )); then
  fm_json="$(jq --arg v "$STATEMENT" '.statement = $v' <<< "$fm_json")"
  changed="$(jq '. + ["statement"]' <<< "$changed")"
fi
if (( HAS_RATIONALE )); then
  [[ -f "$RATIONALE_FILE" ]] || { echo "bites-edit: rationale file not found: $RATIONALE_FILE" >&2; exit 1; }
  rat="$(cat "$RATIONALE_FILE")"
  fm_json="$(jq --arg v "$rat" '.rationale = $v' <<< "$fm_json")"
  changed="$(jq '. + ["rationale"]' <<< "$changed")"
fi
if (( HAS_DOMAIN )); then
  new_domain="$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z')"
  fm_json="$(jq --arg v "$new_domain" '.domain = $v' <<< "$fm_json")"
  changed="$(jq '. + ["domain"]' <<< "$changed")"
fi
if (( HAS_TAGS )); then
  tags_json="$(printf '%s' "$TAGS_CSV" | tr ',' '\n' | awk 'NF' | jq -R . | jq -s '.')"
  fm_json="$(jq --argjson v "$tags_json" '.tags = $v' <<< "$fm_json")"
  changed="$(jq '. + ["tags"]' <<< "$changed")"
fi

new_fm="$(yq eval -P '.' - <<< "$fm_json")"

new_abs="$old_abs"
if [[ "$new_domain" != "$old_domain" ]]; then
  filename="$(basename "$old_abs")"
  if [[ "$status" == "superseded" ]]; then
    target_dir="$BITES_DIR/_archive/$new_domain"
  else
    target_dir="$BITES_DIR/domains/$new_domain"
  fi
  mkdir -p "$target_dir"
  new_abs="$target_dir/$filename"
fi

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
  --arg old "${old_abs#"$ROOT/"}" \
  --arg new "${new_abs#"$ROOT/"}" \
  --argjson changed "$changed" \
  '{id: $id, old_path: $old, new_path: $new, changed: $changed}'
