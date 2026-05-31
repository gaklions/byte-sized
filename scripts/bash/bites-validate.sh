#!/usr/bin/env bash
# bites-validate.sh — check graph integrity.
#
# Checks: id uniqueness, required frontmatter fields, broken edges,
# dangling supersession, status consistency, domain whitelist.
# Exits non-zero if any hard error is found. Warnings do not fail.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
CFG="$(bs_config_path "$ROOT")"

errors=()
warnings=()

if [[ ! -f "$INDEX" ]]; then
  echo "byte-sized: index missing; rebuilding..." >&2
  "$SCRIPT_DIR/bites-index.sh" >/dev/null
fi

domains_whitelist="$(yq eval -o=json '.domains // []' "$CFG")"

# Required fields per bite.
while IFS= read -r r; do
  id="$(jq -r '.id // ""' <<< "$r")"
  for f in id statement domain status; do
    v="$(jq -r --arg f "$f" '.[$f] // ""' <<< "$r")"
    if [[ -z "$v" ]]; then errors+=("missing field '$f' in bite ${id:-<unknown>}"); fi
  done
  st="$(jq -r '.status' <<< "$r")"
  case "$st" in
    active|draft|superseded|deprecated) ;;
    *) errors+=("invalid status '$st' in $id") ;;
  esac
  dom="$(jq -r '.domain' <<< "$r")"
  if ! jq -e --arg d "$dom" 'index($d)' <<< "$domains_whitelist" >/dev/null; then
    warnings+=("$id uses domain '$dom' not in config.domains")
  fi
done < <(jq -c '.bites[]' "$INDEX")

# Id uniqueness.
dupes="$(jq -r '.bites | group_by(.id) | map(select(length>1)) | .[].[0].id' "$INDEX")"
if [[ -n "$dupes" ]]; then
  while IFS= read -r d; do errors+=("duplicate id: $d"); done <<< "$dupes"
fi

# Broken edges + dangling supersession.
all_ids="$(jq -r '.bites[].id' "$INDEX" | sort -u)"
while IFS= read -r r; do
  id="$(jq -r '.id' <<< "$r")"
  for rel in relates_to supersedes depends_on conflicts_with; do
    while IFS= read -r tgt; do
      [[ -z "$tgt" ]] && continue
      if ! grep -qx -- "$tgt" <<< "$all_ids"; then
        errors+=("$id -[$rel]-> $tgt: target missing")
      fi
    done < <(jq -r --arg k "$rel" '.edges[$k] // [] | .[]' <<< "$r")
  done
  sb="$(jq -r '.source.superseded_by // ""' <<< "$r")"
  st="$(jq -r '.status' <<< "$r")"
  if [[ "$st" == "superseded" && -z "$sb" ]]; then
    warnings+=("$id is 'superseded' but source.superseded_by is empty")
  fi
done < <(jq -c '.bites[]' "$INDEX")

# Emit report.
report="$(jq -n \
  --argjson errors "$(printf '%s\n' "${errors[@]+"${errors[@]}"}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson warnings "$(printf '%s\n' "${warnings[@]+"${warnings[@]}"}" | jq -R . | jq -s 'map(select(. != ""))')" \
  '{errors: $errors, warnings: $warnings, ok: (($errors | length) == 0)}')"
printf '%s\n' "$report"

if [[ "$(jq -r '.ok' <<< "$report")" != "true" ]]; then
  exit 1
fi
