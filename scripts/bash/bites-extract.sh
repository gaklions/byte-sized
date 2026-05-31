#!/usr/bin/env bash
# bites-extract.sh — stage candidate bites for human review.
#
# Usage:
#   bites-extract.sh --source-file <path> --feature <id> [--out <path>] < candidates.yaml
#
# The actual extraction (statement / domain / tags / rationale) is performed by the
# *agent* in the calling command prompt. This script:
#   1. Reads a YAML array of candidate stubs on stdin.
#   2. Validates minimal shape ({statement, domain, [tags], [rationale]}).
#   3. Deduplicates against existing bites in the index by lexical similarity of statement.
#   4. Writes the survivors to <drafts_dir>/<feature>-<timestamp>.yml.
#   5. Prints the draft file path + a count summary as JSON.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

SOURCE_FILE=""
FEATURE=""
OUT=""
while (( $# > 0 )); do
  case "$1" in
    --source-file) SOURCE_FILE="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "bites-extract: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
CFG="$(bs_config_path "$ROOT")"
DRAFTS_REL="$(bs_cfg "$CFG" '.extraction.drafts_dir' '_drafts')"
DRAFTS_DIR="$BITES_DIR/$DRAFTS_REL"
mkdir -p "$DRAFTS_DIR"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
feat="${FEATURE:-unscoped}"
out="${OUT:-$DRAFTS_DIR/${feat}-${ts}.yml}"

candidates_json="$(yq eval -o=json '.' - || echo '[]')"
if [[ "$(jq -r 'type' <<< "$candidates_json")" != "array" ]]; then
  echo "bites-extract: stdin must be a YAML array of stubs" >&2
  exit 2
fi

# Filter out blank / invalid stubs.
valid="$(jq '[ .[] | select((.statement // "") | length > 0) ]' <<< "$candidates_json")"

# Dedup against index by statement token overlap >= 0.7.
INDEX="$BITES_DIR/index.json"
if [[ -f "$INDEX" ]]; then
  surviving="$(jq --slurpfile idx "$INDEX" '
    def tokens($s): ($s // "" | ascii_downcase | gsub("[^a-z0-9 ]"; " ") | split(" ") | map(select(length>=3)));
    def overlap($a; $b): if (($a + $b) | length) == 0 then 0
      else ([$a[] | select(. as $t | $b | index($t))] | length) /
           (([$a, $b] | add | unique) | length)
      end;
    . as $cands
    | $idx[0].bites as $existing
    | $cands
    | map(. as $c
        | (tokens($c.statement)) as $ct
        | if any($existing[]; (tokens(.statement) as $et | overlap($ct; $et) >= 0.7))
            then empty else $c end)
  ' <<< "$valid")"
else
  surviving="$valid"
fi

# Enrich with feature + source path metadata.
surviving="$(jq --arg f "$feat" --arg src "$SOURCE_FILE" '
  map(. + {
    status: "draft",
    source: ((.source // {}) + {feature: $f, spec: $src})
  })
' <<< "$surviving")"

yq eval -P '.' - <<< "$surviving" > "$out"

dropped=$(( $(jq 'length' <<< "$valid") - $(jq 'length' <<< "$surviving") ))
jq -n \
  --arg out "${out#"$ROOT/"}" \
  --argjson kept "$(jq 'length' <<< "$surviving")" \
  --argjson dropped "$dropped" \
  '{drafts_file: $out, kept: $kept, dropped_as_duplicate: $dropped}'
