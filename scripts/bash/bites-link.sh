#!/usr/bin/env bash
# bites-link.sh — add or remove an edge between two existing bites.
#
# Usage:
#   bites-link.sh <from-id> <relation> <to-id> [--remove]
# Relations: relates_to | supersedes | depends_on | conflicts_with

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

REMOVE=0
POSITIONAL=()
while (( $# > 0 )); do
  case "$1" in
    --remove) REMOVE=1; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if (( ${#POSITIONAL[@]} != 3 )); then
  echo "bites-link: usage: <from-id> <relation> <to-id> [--remove]" >&2
  exit 2
fi
FROM="${POSITIONAL[0]}"
REL="${POSITIONAL[1]}"
TO="${POSITIONAL[2]}"

case "$REL" in
  relates_to|supersedes|depends_on|conflicts_with) ;;
  *) echo "bites-link: invalid relation '$REL'" >&2; exit 2 ;;
esac

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
bs_lock "$BITES_DIR/.index.lock"

from_path="$(jq -r --arg id "$FROM" '.bites[] | select(.id == $id) | .path // ""' "$INDEX")"
to_path="$(jq   -r --arg id "$TO"   '.bites[] | select(.id == $id) | .path // ""' "$INDEX")"
if [[ -z "$from_path" ]]; then echo "bites-link: $FROM not found" >&2; exit 1; fi
if [[ -z "$to_path" ]]; then echo "bites-link: $TO not found" >&2; exit 1; fi

abs="$ROOT/$from_path"
fm_yaml="$(bs_frontmatter "$abs")"
body="$(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f>=2{print}' "$abs")"

if (( REMOVE )); then
  new_fm="$(yq eval ".edges.$REL = ((.edges.$REL // []) | unique - [\"$TO\"])" - <<< "$fm_yaml")"
else
  new_fm="$(yq eval ".edges.$REL = ((.edges.$REL // []) + [\"$TO\"] | unique)" - <<< "$fm_yaml")"
fi

{
  echo "---"
  printf '%s\n' "$new_fm"
  echo "---"
  printf '%s\n' "$body"
} > "$abs"

# When supersedes is added, auto-flip target status to superseded + record superseded_by.
if [[ "$REL" == "supersedes" && $REMOVE -eq 0 ]]; then
  target="$ROOT/$to_path"
  tgt_fm="$(bs_frontmatter "$target")"
  tgt_body="$(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f>=2{print}' "$target")"
  new_tgt="$(yq eval ".status = \"superseded\" | .source.superseded_by = \"$FROM\"" - <<< "$tgt_fm")"
  {
    echo "---"
    printf '%s\n' "$new_tgt"
    echo "---"
    printf '%s\n' "$tgt_body"
  } > "$target"
fi

"$SCRIPT_DIR/bites-index.sh" >/dev/null
echo "byte-sized: ${REMOVE:+removed }${FROM} -[$REL]-> ${TO}"
