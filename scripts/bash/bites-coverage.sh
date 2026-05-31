#!/usr/bin/env bash
# bites-coverage.sh — map functional requirements / tasks to covering bites.
#
# Usage: bites-coverage.sh --file <spec-or-tasks.md>
#
# Scans the file for FR-* / NFR-* / TASK-* tokens. For each token, queries the
# bites index for bites whose body or source.spec references the token.
# Output: JSON {coverage: {FR-1: [BB-...], ...}, uncovered: [...], orphan_bites: [...]}.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

FILE=""
while (( $# > 0 )); do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    *) echo "bites-coverage: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "bites-coverage: --file <existing-path> is required" >&2
  exit 2
fi

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
if [[ ! -f "$INDEX" ]]; then
  echo "bites-coverage: index missing; rebuilding..." >&2
  "$SCRIPT_DIR/bites-index.sh" >/dev/null
fi

# Tokens of interest.
mapfile -t tokens < <(grep -Eo '\b(FR|NFR|TASK)-[0-9]+\b' "$FILE" | sort -u || true)

coverage='{}'
for t in "${tokens[@]+"${tokens[@]}"}"; do
  hits='[]'
  # Scan each bite file body + source.spec for this token.
  while IFS= read -r path; do
    full="$ROOT/$path"
    [[ -f "$full" ]] || continue
    if grep -qE "\\b${t}\\b" "$full"; then
      id="$(jq -r --arg p "$path" '.bites[] | select(.path == $p) | .id' "$INDEX")"
      [[ -z "$id" ]] && continue
      hits="$(jq --arg id "$id" '. + [$id] | unique' <<< "$hits")"
    fi
  done < <(jq -r '.bites[].path // ""' "$INDEX")
  coverage="$(jq --arg t "$t" --argjson h "$hits" '. + {($t): $h}' <<< "$coverage")"
done

uncovered="$(jq -r 'to_entries | map(select((.value | length) == 0)) | map(.key)' <<< "$coverage")"

# Orphan bites: active bites whose source.spec/source.feature is empty.
orphan="$(jq '[.bites[] | select(.status == "active") | select(((.source.spec // "") == "") and ((.source.feature // "") == "")) | .id]' "$INDEX")"

jq -n --argjson cov "$coverage" --argjson un "$uncovered" --argjson orph "$orphan" \
  '{coverage: $cov, uncovered: $un, orphan_bites: $orph}'
