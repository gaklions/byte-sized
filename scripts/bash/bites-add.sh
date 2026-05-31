#!/usr/bin/env bash
# rules-add.sh — create a new rule file from a YAML stub on stdin or flags.
#
# Usage (flag form):
#   rules-add.sh --statement "..." --domain auth --rationale "..." \
#                --tags tag1,tag2 --status active --source-feature 002-foo \
#                --source-spec specs/002-foo/spec.md#FR-1 [--id BR-AUTH-007]
#
# Usage (stdin form):
#   cat candidate.yml | rules-add.sh --from-stdin
#
# Allocates the next id in the chosen domain unless --id is provided, writes the file,
# updates index.json, and emits the new rule id + path to stdout (JSON).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

STATEMENT=""
RATIONALE=""
DOMAIN=""
TAGS=""
STATUS="active"
ID=""
SRC_FEATURE=""
SRC_SPEC=""
FROM_STDIN=0

while (( $# > 0 )); do
  case "$1" in
    --statement) STATEMENT="$2"; shift 2 ;;
    --rationale) RATIONALE="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --tags) TAGS="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --id) ID="$2"; shift 2 ;;
    --source-feature) SRC_FEATURE="$2"; shift 2 ;;
    --source-spec) SRC_SPEC="$2"; shift 2 ;;
    --from-stdin) FROM_STDIN=1; shift ;;
    *) echo "rules-add: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(bs_repo_root)"
RULES_DIR="$(bs_rules_dir "$ROOT")"
CFG="$(bs_config_path "$ROOT")"
ID_PREFIX="$(bs_cfg "$CFG" '.storage.id_prefix' 'BR')"
bs_lock "$RULES_DIR/.index.lock"

if (( FROM_STDIN )); then
  stdin_json="$(yq eval -o=json '.' - )"
  STATEMENT="${STATEMENT:-$(jq -r '.statement // ""' <<< "$stdin_json")}"
  RATIONALE="${RATIONALE:-$(jq -r '.rationale // ""' <<< "$stdin_json")}"
  DOMAIN="${DOMAIN:-$(jq -r '.domain // ""' <<< "$stdin_json")}"
  STATUS="${STATUS:-$(jq -r '.status // "active"' <<< "$stdin_json")}"
  if [[ -z "$TAGS" ]]; then
    TAGS="$(jq -r '(.tags // []) | join(",")' <<< "$stdin_json")"
  fi
  if [[ -z "$SRC_FEATURE" ]]; then
    SRC_FEATURE="$(jq -r '.source.feature // ""' <<< "$stdin_json")"
  fi
  if [[ -z "$SRC_SPEC" ]]; then
    SRC_SPEC="$(jq -r '.source.spec // ""' <<< "$stdin_json")"
  fi
  if [[ -z "$ID" ]]; then
    ID="$(jq -r '.id // ""' <<< "$stdin_json")"
  fi
fi

if [[ -z "$STATEMENT" || -z "$DOMAIN" ]]; then
  echo "rules-add: --statement and --domain are required" >&2
  exit 2
fi

domain_upper="$(printf '%s' "$DOMAIN" | tr 'a-z' 'A-Z')"
domain_lower="$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z')"
domain_path="$RULES_DIR/domains/$domain_lower"
mkdir -p "$domain_path"

# Allocate id if not provided.
if [[ -z "$ID" ]]; then
  next=1
  if [[ -f "$RULES_DIR/index.json" ]]; then
    used="$(jq -r --arg p "${ID_PREFIX}-${domain_upper}-" '
      .rules | map(.id // "") | map(select(startswith($p))) | map(. | sub($p; "") | tonumber? // 0) | max // 0
    ' "$RULES_DIR/index.json")"
    next=$(( used + 1 ))
  fi
  ID="$(printf '%s-%s-%03d' "$ID_PREFIX" "$domain_upper" "$next")"
fi

# Reject duplicate id.
if [[ -f "$RULES_DIR/index.json" ]] && \
   [[ "$(jq -r --arg id "$ID" '.rules | map(select(.id == $id)) | length' "$RULES_DIR/index.json")" != "0" ]]; then
  echo "rules-add: id $ID already exists" >&2
  exit 1
fi

slug="$(bs_slugify "$STATEMENT")"
file="$domain_path/${ID}-${slug:0:48}.md"
today="$(bs_today)"

# Build frontmatter JSON, then convert to YAML.
tags_json="$(printf '%s' "$TAGS" | tr ',' '\n' | awk 'NF' | jq -R . | jq -s '.')"
fm_json="$(jq -n \
  --arg id "$ID" \
  --arg st "$STATEMENT" \
  --arg ra "$RATIONALE" \
  --arg dom "$domain_lower" \
  --argjson tags "$tags_json" \
  --arg status "$STATUS" \
  --arg feat "$SRC_FEATURE" \
  --arg spec "$SRC_SPEC" \
  --arg today "$today" '
  {
    id: $id,
    statement: $st,
    rationale: $ra,
    domain: $dom,
    tags: $tags,
    status: $status,
    source: { feature: $feat, spec: $spec, created: $today, superseded_by: null },
    edges: { relates_to: [], supersedes: [], depends_on: [], conflicts_with: [] }
  }')"

{
  echo "---"
  yq eval -P '.' - <<< "$fm_json"
  echo "---"
  echo
  echo "## Context"
  echo
  echo "_To be filled in._"
  echo
  echo "## Implications"
  echo
  echo "_To be filled in._"
} > "$file"

# Rebuild index.
"$SCRIPT_DIR/rules-index.sh" >/dev/null

jq -n --arg id "$ID" --arg path "${file#"$ROOT/"}" '{id: $id, path: $path}'
