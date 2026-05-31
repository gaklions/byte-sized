#!/usr/bin/env bash
# rules-baseline.sh — discover candidate source files for a brownfield baseline pass.
#
# Modes:
#   --discover                      Walk the repo, group files into batches, emit JSON manifest.
#   --stage --batch <label>         Read a YAML array of candidate stubs on stdin and stage them
#                                   to _drafts/baseline-<label>-<timestamp>.yml (delegates to
#                                   rules-extract.sh's dedup logic).
#
# Common flags:
#   --include  <comma-glob-list>    Override default include globs.
#   --exclude  <comma-glob-list>    Append to default exclude globs.
#   --scope    docs|specs|code|all  Convenience presets (default: docs+specs).
#   --max-files-per-batch <N>       Group discovered files into batches of at most N (default: 12).
#   --max-bytes-per-batch  <N>      Also cap each batch by total bytes (default: 65536).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq find

MODE="discover"
INCLUDE=""
EXCLUDE=""
SCOPE="docs+specs"
MAX_FILES=12
MAX_BYTES=65536
BATCH=""

while (( $# > 0 )); do
  case "$1" in
    --discover) MODE="discover"; shift ;;
    --stage)    MODE="stage"; shift ;;
    --batch)    BATCH="$2"; shift 2 ;;
    --include)  INCLUDE="$2"; shift 2 ;;
    --exclude)  EXCLUDE="$2"; shift 2 ;;
    --scope)    SCOPE="$2"; shift 2 ;;
    --max-files-per-batch) MAX_FILES="$2"; shift 2 ;;
    --max-bytes-per-batch) MAX_BYTES="$2"; shift 2 ;;
    *) echo "rules-baseline: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(bs_repo_root)"
cd "$ROOT"

# ----- Default include/exclude per scope -----

default_includes() {
  case "$1" in
    docs)        echo "README*,docs/**,**/CONTRIBUTING.md,**/*.adr.md,**/ADR-*.md,**/ARCHITECTURE.md" ;;
    specs)       echo "specs/**/*.md,.specify/memory/**/*.md" ;;
    docs+specs)  echo "README*,docs/**,specs/**/*.md,.specify/memory/**/*.md,**/CONTRIBUTING.md,**/*.adr.md,**/ADR-*.md,**/ARCHITECTURE.md" ;;
    code)        echo "src/**,lib/**,app/**,packages/**" ;;
    all)         echo "README*,docs/**,specs/**/*.md,.specify/memory/**/*.md,**/CONTRIBUTING.md,**/*.adr.md,**/ADR-*.md,**/ARCHITECTURE.md,src/**,lib/**,app/**,packages/**" ;;
    *)           echo "$1" ;;  # treat as a literal glob list
  esac
}

DEFAULT_EXCLUDES="node_modules/**,.git/**,.venv/**,venv/**,dist/**,build/**,out/**,target/**,coverage/**,.specify/rules/**,.specify/extensions/**,_drafts/**,_archive/**"

includes_csv="${INCLUDE:-$(default_includes "$SCOPE")}"
excludes_csv="${DEFAULT_EXCLUDES}${EXCLUDE:+,$EXCLUDE}"

# ----- Stage mode: delegate to rules-extract.sh -----

if [[ "$MODE" == "stage" ]]; then
  if [[ -z "$BATCH" ]]; then
    echo "rules-baseline: --stage requires --batch <label>" >&2
    exit 2
  fi
  CFG="$(bs_config_path "$ROOT")"
  RULES_DIR="$(bs_rules_dir "$ROOT")"
  DRAFTS_REL="$(bs_cfg "$CFG" '.extraction.drafts_dir' '_drafts')"
  DRAFTS_DIR="$RULES_DIR/$DRAFTS_REL"
  mkdir -p "$DRAFTS_DIR"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  out="$DRAFTS_DIR/baseline-${BATCH}-${ts}.yml"
  # The extract script handles dedup; we pass the synthetic "feature" as baseline:<batch>.
  exec "$SCRIPT_DIR/rules-extract.sh" \
    --source-file "baseline:${BATCH}" \
    --feature "baseline-${BATCH}" \
    --out "$out"
fi

# ----- Discover mode -----

# Convert CSV globs to find -path patterns. We use a portable shell glob match.
IFS=',' read -r -a inc_arr <<< "$includes_csv"
IFS=',' read -r -a exc_arr <<< "$excludes_csv"

# Build a JSON list of all candidate files.
files_json='[]'
while IFS= read -r -d '' f; do
  rel="${f#./}"
  # Apply exclude patterns first.
  excluded=0
  for pat in "${exc_arr[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$rel" == $pat ]]; then excluded=1; break; fi
  done
  (( excluded )) && continue
  # Apply include patterns.
  included=0
  for pat in "${inc_arr[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$rel" == $pat ]]; then included=1; break; fi
  done
  (( included )) || continue
  bytes=$(wc -c < "$f" 2>/dev/null || echo 0)
  files_json="$(jq --arg p "$rel" --argjson b "$bytes" '. + [{path: $p, bytes: $b}]' <<< "$files_json")"
done < <(find . -type f -print0 2>/dev/null)

# Group into batches: each batch <= MAX_FILES files AND <= MAX_BYTES total bytes.
batches="$(jq -n --argjson files "$files_json" --argjson mf "$MAX_FILES" --argjson mb "$MAX_BYTES" '
  reduce ($files | sort_by(.path))[] as $f (
    {batches: [], cur: {files: [], bytes: 0}};
    if (.cur.files | length) >= $mf or (.cur.bytes + $f.bytes) > $mb and (.cur.files | length) > 0
    then { batches: (.batches + [.cur]), cur: {files: [$f], bytes: $f.bytes} }
    else { batches: .batches, cur: {files: (.cur.files + [$f]), bytes: (.cur.bytes + $f.bytes)} }
    end
  )
  | (if (.cur.files | length) > 0 then .batches + [.cur] else .batches end)
  | to_entries | map({
      id: ("b" + (((.key + 1) | tostring) | if length == 1 then "0" + . else . end)),
      file_count: (.value.files | length),
      total_bytes: .value.bytes,
      files: (.value.files | map(.path))
    })
')"

total_files="$(jq 'length' <<< "$files_json")"
total_bytes="$(jq 'map(.bytes) | add // 0' <<< "$files_json")"
total_batches="$(jq 'length' <<< "$batches")"

jq -n \
  --arg scope "$SCOPE" \
  --arg includes "$includes_csv" \
  --arg excludes "$excludes_csv" \
  --argjson total_files "$total_files" \
  --argjson total_bytes "$total_bytes" \
  --argjson total_batches "$total_batches" \
  --argjson batches "$batches" \
  '{
    scope: $scope,
    includes: ($includes | split(",")),
    excludes: ($excludes | split(",")),
    totals: { files: $total_files, bytes: $total_bytes, batches: $total_batches },
    batches: $batches
  }'
