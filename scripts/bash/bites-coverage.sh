#!/usr/bin/env bash
# rules-coverage.sh — map functional requirements / tasks to covering rules.
#
# Usage: rules-coverage.sh --file <spec-or-tasks.md>
#
# Scans the file for FR-* / NFR-* / TASK-* tokens. For each token, queries the
# rules index for rules whose body or source.spec references the token.
# Output: JSON {coverage: {FR-1: [BR-...], ...}, uncovered: [...], orphan_rules: [...]}.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

FILE=""
while (( $# > 0 )); do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    *) echo "rules-coverage: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "rules-coverage: --file <existing-path> is required" >&2
  exit 2
fi

ROOT="$(bs_repo_root)"
RULES_DIR="$(bs_rules_dir "$ROOT")"
INDEX="$RULES_DIR/index.json"
if [[ ! -f "$INDEX" ]]; then
  echo "rules-coverage: index missing; rebuilding..." >&2
  "$SCRIPT_DIR/rules-index.sh" >/dev/null
fi

# Tokens of interest.
mapfile -t tokens < <(grep -Eo '\b(FR|NFR|TASK)-[0-9]+\b' "$FILE" | sort -u || true)

coverage='{}'
for t in "${tokens[@]+"${tokens[@]}"}"; do
  hits='[]'
  # Scan each rule file body + source.spec for this token.
  while IFS= read -r path; do
    full="$ROOT/$path"
    [[ -f "$full" ]] || continue
    if grep -qE "\\b${t}\\b" "$full"; then
      id="$(jq -r --arg p "$path" '.rules[] | select(.path == $p) | .id' "$INDEX")"
      [[ -z "$id" ]] && continue
      hits="$(jq --arg id "$id" '. + [$id] | unique' <<< "$hits")"
    fi
  done < <(jq -r '.rules[].path // ""' "$INDEX")
  coverage="$(jq --arg t "$t" --argjson h "$hits" '. + {($t): $h}' <<< "$coverage")"
done

uncovered="$(jq -r 'to_entries | map(select((.value | length) == 0)) | map(.key)' <<< "$coverage")"

# Orphan rules: active rules whose source.spec/source.feature is empty.
orphan="$(jq '[.rules[] | select(.status == "active") | select(((.source.spec // "") == "") and ((.source.feature // "") == "")) | .id]' "$INDEX")"

jq -n --argjson cov "$coverage" --argjson un "$uncovered" --argjson orph "$orphan" \
  '{coverage: $cov, uncovered: $un, orphan_rules: $orph}'
