#!/usr/bin/env bash
# Shared helpers for byte-sized scripts.
# Sourced (not executed) by every other script in this directory.

set -euo pipefail

# ---------- Path resolution ----------

# Repo root = directory containing .specify/
bs_repo_root() {
  local dir
  dir="$(pwd -P)"
  while [[ "$dir" != "/" && "$dir" != "" ]]; do
    if [[ -d "$dir/.specify" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "byte-sized: error: not inside a spec-kit project (.specify/ not found)" >&2
  return 1
}

# Locate the extension's config file (project, then user, then template).
bs_config_path() {
  local root="$1"
  local candidate
  candidate="$root/.specify/extensions/byte-sized/byte-sized-config.yml"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  # Fall back to the bundled template (read-only defaults).
  candidate="$root/.specify/extensions/byte-sized/config-template.yml"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  echo "byte-sized: error: no config file found under .specify/extensions/byte-sized/" >&2
  return 1
}

# Read a scalar config value via yq. Args: <config-path> <yq-path> [default]
bs_cfg() {
  local cfg="$1" path="$2" default="${3:-}"
  local val
  val="$(yq eval "$path // \"\"" "$cfg" 2>/dev/null || echo "")"
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$val"
  fi
}

# Resolve the absolute rules_dir. Args: <repo-root>
bs_rules_dir() {
  local root="$1"
  local cfg
  cfg="$(bs_config_path "$root")" || return 1
  local rel
  rel="$(bs_cfg "$cfg" '.storage.rules_dir' '.specify/rules')"
  printf '%s\n' "$root/$rel"
}

# ---------- Frontmatter parsing ----------

# Extract YAML frontmatter from a markdown file to stdout (just the YAML body).
bs_frontmatter() {
  local file="$1"
  awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f==1{print} f==2{exit}' "$file"
}

# Parse frontmatter and emit a single-line JSON object. Args: <md-file>
bs_frontmatter_json() {
  local file="$1"
  bs_frontmatter "$file" | yq eval -o=json -I=0 '.' -
}

# ---------- File locking (best-effort) ----------

# Acquire an exclusive lock on a path; releases on script exit.
# Args: <lock-path>
bs_lock() {
  local lock="$1"
  mkdir -p "$(dirname "$lock")"
  exec 9>"$lock"
  if command -v flock >/dev/null 2>&1; then
    flock -x 9
  fi
}

# ---------- Misc ----------

bs_slugify() {
  local s="${1:-}"
  s="${s,,}"                         # lowercase
  s="$(printf '%s' "$s" | tr -c 'a-z0-9' '-')"
  s="$(printf '%s' "$s" | sed -E 's/-+/-/g; s/^-//; s/-$//')"
  printf '%s\n' "${s:-rule}"
}

bs_today() {
  date -u +%Y-%m-%d
}

bs_now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

bs_require_tools() {
  local missing=()
  for t in "$@"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      missing+=("$t")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "byte-sized: missing required tools: ${missing[*]}" >&2
    return 1
  fi
}
