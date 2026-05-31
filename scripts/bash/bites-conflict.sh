#!/usr/bin/env bash
# bites-conflict.sh — flag candidate conflicts between bites.
#
# Heuristic: for each pair of active bites in the same domain with at least one
# shared tag, scan both statements for any configured antonym_pair (one side in
# bite A, the other side in bite B). Emit those pairs as candidate conflicts.
#
# Usage:
#   bites-conflict.sh                  # scan whole graph
#   bites-conflict.sh --id BB-AUTH-007 # restrict to pairs involving one id
#   bites-conflict.sh --stub <yaml>    # check a not-yet-added stub against existing

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

ONLY_ID=""
STUB_FILE=""
while (( $# > 0 )); do
  case "$1" in
    --id) ONLY_ID="$2"; shift 2 ;;
    --stub) STUB_FILE="$2"; shift 2 ;;
    *) echo "bites-conflict: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
CFG="$(bs_config_path "$ROOT")"

if [[ ! -f "$INDEX" ]]; then
  echo "[]"
  exit 0
fi

# Build the bites set, optionally appending a stub.
bites="$(jq '[.bites[] | select(.status == "active") | {id, statement, domain, tags}]' "$INDEX")"
if [[ -n "$STUB_FILE" && -f "$STUB_FILE" ]]; then
  stub_json="$(yq eval -o=json '.' "$STUB_FILE")"
  bites="$(jq --argjson s "$stub_json" '. + [($s + {id: ($s.id // "STUB")})]' <<< "$bites")"
fi

antonyms="$(yq eval -o=json '.conflict_detection.antonym_pairs // []' "$CFG")"

jq --argjson rs "$bites" \
   --argjson ant "$antonyms" \
   --arg only "$ONLY_ID" \
'
  def low($s): ($s // "" | ascii_downcase);
  def contains_phrase($haystack; $needle):
    (low($haystack) | test("\\b" + $needle + "\\b"));

  [ range(0; $rs | length) as $i
    | range($i+1; $rs | length) as $j
    | $rs[$i] as $a | $rs[$j] as $b
    | select(($only | length) == 0 or $a.id == $only or $b.id == $only)
    | select($a.domain == $b.domain)
    | select(([$a.tags // [], $b.tags // []] | add | group_by(.) | map(select(length>1)) | length) > 0)
    | ( $ant | map(. as $p
        | select( (contains_phrase($a.statement; $p[0]) and contains_phrase($b.statement; $p[1]))
               or (contains_phrase($a.statement; $p[1]) and contains_phrase($b.statement; $p[0])) )
        | { pair: $p }) ) as $triggers
    | select(($triggers | length) > 0)
    | { from: $a.id, to: $b.id, domain: $a.domain, triggers: $triggers }
  ]
' <<< null
