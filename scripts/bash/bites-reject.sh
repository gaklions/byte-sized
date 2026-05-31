#!/usr/bin/env bash
# bites-reject.sh — reject one draft stub; move it into _drafts/_rejected/<basename>
# with audit fields ({ rejected: { at, reason } }) appended.
#
# Usage:
#   bites-reject.sh --from-file <_drafts/foo.yml> --index <N> [--reason <text>]
#
# Emits JSON: { rejected_into, remaining_stubs }.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

FROM_FILE=""
INDEX_N=""
REASON=""

while (( $# > 0 )); do
  case "$1" in
    --from-file) FROM_FILE="$2"; shift 2 ;;
    --index) INDEX_N="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    *) echo "bites-reject: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$FROM_FILE" || -z "$INDEX_N" ]]; then
  echo "bites-reject: --from-file and --index are required" >&2
  exit 2
fi

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
CFG="$(bs_config_path "$ROOT")"
DRAFTS_REL="$(bs_cfg "$CFG" '.extraction.drafts_dir' '_drafts')"
DRAFTS_DIR="$BITES_DIR/$DRAFTS_REL"
REJECTED_DIR="$DRAFTS_DIR/_rejected"
mkdir -p "$REJECTED_DIR"

abs_from="$FROM_FILE"
if [[ "$abs_from" != /* ]]; then abs_from="$ROOT/$abs_from"; fi
[[ -f "$abs_from" ]] || { echo "bites-reject: file not found: $abs_from" >&2; exit 1; }

stubs_json="$(yq eval -o=json '.' "$abs_from")"
[[ "$(jq -r 'type' <<< "$stubs_json")" == "array" ]] \
  || { echo "bites-reject: $abs_from is not a YAML array" >&2; exit 1; }
total="$(jq 'length' <<< "$stubs_json")"
if (( INDEX_N < 0 || INDEX_N >= total )); then
  echo "bites-reject: index $INDEX_N out of range (have $total)" >&2
  exit 1
fi

stub="$(jq --argjson i "$INDEX_N" '.[$i]' <<< "$stubs_json")"
now="$(bs_now_iso)"
audited="$(jq --arg at "$now" --arg r "$REASON" '. + {rejected: {at: $at, reason: $r}}' <<< "$stub")"

basename="$(basename "$abs_from")"
rejected_file="$REJECTED_DIR/$basename"
existing='[]'
if [[ -f "$rejected_file" ]]; then
  existing="$(yq eval -o=json '.' "$rejected_file" 2>/dev/null || echo '[]')"
  if [[ "$(jq -r 'type' <<< "$existing")" != "array" ]]; then existing='[]'; fi
fi
updated="$(jq --argjson s "$audited" '. + [$s]' <<< "$existing")"
yq eval -P '.' - <<< "$updated" > "$rejected_file"

remaining="$(jq --argjson i "$INDEX_N" 'del(.[$i])' <<< "$stubs_json")"
remaining_len="$(jq 'length' <<< "$remaining")"
if (( remaining_len == 0 )); then
  rm -f "$abs_from"
else
  yq eval -P '.' - <<< "$remaining" > "$abs_from"
fi

jq -n \
  --arg into "${rejected_file#"$ROOT/"}" \
  --argjson rem "$remaining_len" \
  '{rejected_into: $into, remaining_stubs: $rem}'
