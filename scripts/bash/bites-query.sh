#!/usr/bin/env bash
# bites-query.sh — token-efficient projection from the bites index.
#
# Usage:
#   bites-query.sh [--text "free text"] [--tags tag1,tag2] [--domain d1,d2]
#                  [--status active,draft] [--limit N] [--include-drafts]
#                  [--ids id1,id2]
#
# Emits a JSON array of {id, statement, domain, tags, status, score}.
# Lexical score = (token overlap with --text on statement+tags) + tag/domain bonuses.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

bs_require_tools jq yq

TEXT=""
TAGS=""
DOMAINS=""
STATUSES="active"
LIMIT=""
INCLUDE_DRAFTS=0
IDS=""

while (( $# > 0 )); do
  case "$1" in
    --text) TEXT="$2"; shift 2 ;;
    --tags) TAGS="$2"; shift 2 ;;
    --domain) DOMAINS="$2"; shift 2 ;;
    --status) STATUSES="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --include-drafts) INCLUDE_DRAFTS=1; shift ;;
    --ids) IDS="$2"; shift 2 ;;
    *) echo "bites-query: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(bs_repo_root)"
BITES_DIR="$(bs_bites_dir "$ROOT")"
INDEX="$BITES_DIR/index.json"
CFG="$(bs_config_path "$ROOT")"

if [[ ! -f "$INDEX" ]]; then
  echo "byte-sized: no index found. Run /speckit.byte-sized.init or speckit.byte-sized.validate." >&2
  echo "[]"
  exit 0
fi

if [[ -z "$LIMIT" ]]; then
  LIMIT="$(bs_cfg "$CFG" '.relevance.max_results' '12')"
fi
MIN_SCORE="$(bs_cfg "$CFG" '.relevance.min_score' '0.2')"
MAX_KB="$(bs_cfg "$CFG" '.relevance.max_projection_kb' '8')"

# Tokenise --text into a JSON array of lowercase words (3+ chars).
TEXT_TOKENS_JSON="$(printf '%s' "$TEXT" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '\n' \
  | awk 'length($0) >= 3' | jq -R . | jq -s 'unique')"

# Drafts: optionally include staged drafts from _drafts/*.yml as virtual entries.
DRAFTS_JSON='[]'
if (( INCLUDE_DRAFTS )); then
  drafts_dir="$BITES_DIR/$(bs_cfg "$CFG" '.extraction.drafts_dir' '_drafts')"
  if [[ -d "$drafts_dir" ]]; then
    DRAFTS_JSON="$(find "$drafts_dir" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 \
      | xargs -0 -I {} yq eval -o=json '. | (.[] // .)' {} 2>/dev/null \
      | jq -s 'map(. + {status: "draft", path: ""})' || echo '[]')"
  fi
fi

jq -n \
  --slurpfile idx "$INDEX" \
  --argjson drafts "$DRAFTS_JSON" \
  --argjson tokens "$TEXT_TOKENS_JSON" \
  --arg tags_csv "$TAGS" \
  --arg domains_csv "$DOMAINS" \
  --arg statuses_csv "$STATUSES" \
  --arg ids_csv "$IDS" \
  --argjson min_score "$MIN_SCORE" \
  --argjson limit "$LIMIT" \
'
  def split_csv($s): if ($s | length) == 0 then [] else ($s | split(",") | map(. | ascii_downcase | gsub("^\\s+|\\s+$"; ""))) end;

  ($idx[0].bites + $drafts) as $all
  | split_csv($tags_csv)     as $want_tags
  | split_csv($domains_csv)  as $want_domains
  | split_csv($statuses_csv) as $want_statuses
  | split_csv($ids_csv)      as $want_ids

  | $all
  | map(
      . as $r
      | (($r.tags // []) | map(ascii_downcase)) as $rt
      | (($r.domain // "") | ascii_downcase)    as $rd
      | (($r.status // "active") | ascii_downcase) as $rs
      | (($r.statement // "") | ascii_downcase
          | gsub("[^a-z0-9 ]"; " ") | split(" ") | map(select(length >= 3))) as $sw
      | ([$sw, $rt] | add) as $bag
      | (if ($tokens | length) > 0
           then ([$tokens[] | select(. as $t | $bag | index($t)) ] | length) / ($tokens | length)
           else 0.0
         end) as $text_score
      | (if ($want_tags | length) > 0
           then ([$want_tags[] | select(. as $t | $rt | index($t))] | length) / ($want_tags | length)
           else 0.0
         end) as $tag_score
      | (if ($want_domains | length) > 0
           then (if ($want_domains | index($rd)) then 1.0 else 0.0 end)
           else 0.0
         end) as $domain_score
      | ($text_score * 0.6 + $tag_score * 0.3 + $domain_score * 0.1) as $score
      | $r + { score: $score, _rs: $rs, _rd: $rd, _rt: $rt }
    )
  | map(select(
      (($want_statuses | length) == 0 or (._rs | IN($want_statuses[])))
      and (($want_domains | length) == 0 or (._rd | IN($want_domains[])))
      and (($want_tags | length) == 0 or (any(._rt[]; . as $t | $want_tags | index($t))))
      and (($want_ids | length) == 0 or ((.id | ascii_downcase) | IN($want_ids[])))
    ))
  | map(select(
      ($tokens | length) == 0 and ($want_tags | length) == 0 and ($want_domains | length) == 0
      or .score >= $min_score
    ))
  | sort_by(-.score)
  | .[:$limit]
  | map({id, statement, domain, tags, status, score: ((.score | . * 1000 | floor) / 1000)})
'
