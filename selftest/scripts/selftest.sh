#!/usr/bin/env bash
# selftest.sh — exercise the byte-sized script library end-to-end against a temp sandbox.
# Runs in CI on Ubuntu (and is mirrored by selftest.ps1 for Windows).

set -euo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_ROOT="$(cd "$SELFTEST_DIR/../.." && pwd)"
SCRIPTS="$EXT_ROOT/scripts/bash"

# Sandbox: pretend to be a spec-kit project.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/.specify/extensions/byte-sized"
cp "$EXT_ROOT/config-template.yml" "$SANDBOX/.specify/extensions/byte-sized/config-template.yml"

cd "$SANDBOX"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1" >&2; exit 1; }

echo "==> 1. init"
"$SCRIPTS/bites-init.sh" >/dev/null
[[ -d .specify/bites/domains ]] || fail "init did not create domains/"
[[ -f .specify/bites/index.json ]] || fail "init did not create index.json"
pass "init scaffolded storage"

echo "==> 2. add"
out="$("$SCRIPTS/bites-add.sh" \
  --statement "MFA is required for all admin accounts." \
  --domain auth --tags "security,admin,mfa" \
  --rationale "Mitigates credential theft." \
  --source-feature 001-test --source-spec specs/001-test/spec.md#FR-1)"
id1="$(jq -r '.id' <<< "$out")"
[[ "$id1" == "BB-AUTH-001" ]] || fail "expected BB-AUTH-001, got $id1"
pass "added $id1"

out="$("$SCRIPTS/bites-add.sh" \
  --statement "Admin sessions must always expire after 30 minutes of inactivity." \
  --domain auth --tags "security,admin,session")"
id2="$(jq -r '.id' <<< "$out")"
[[ "$id2" == "BB-AUTH-002" ]] || fail "expected BB-AUTH-002, got $id2"
pass "added $id2"

echo "==> 3. link"
"$SCRIPTS/bites-link.sh" "$id1" relates_to "$id2" >/dev/null
grep -q "$id2" ".specify/bites/domains/auth/${id1}"-*.md || fail "edge not written to $id1"
pass "linked $id1 relates_to $id2"

echo "==> 4. query"
q="$("$SCRIPTS/bites-query.sh" --text "admin mfa security" --limit 5)"
[[ "$(jq 'length' <<< "$q")" -ge 1 ]] || fail "query returned nothing"
[[ "$(jq -r --arg id "$id1" 'any(.[]; .id == $id)' <<< "$q")" == "true" ]] || fail "query missing $id1"
pass "query returned $(jq 'length' <<< "$q") result(s)"

echo "==> 5. get with neighbours"
g="$("$SCRIPTS/bites-get.sh" "$id1" --neighbors 1)"
[[ "$(jq 'length' <<< "$g")" -ge 2 ]] || fail "neighbour expansion did not include $id2"
pass "get returned $(jq 'length' <<< "$g") bite(s)"

echo "==> 6. validate"
v="$("$SCRIPTS/bites-validate.sh")" || fail "validate failed: $v"
[[ "$(jq -r '.ok' <<< "$v")" == "true" ]] || fail "validate not ok"
pass "validate ok"

echo "==> 7. extract"
mkdir -p specs/001-test
cat > specs/001-test/clarify.md <<'EOF'
## Q&A
Q: What about read-only audit accounts?
A: Audit accounts must not have write access. They also must have an annual access review.
EOF
extract_out="$(printf -- '- statement: "Audit accounts must not have write access."\n  domain: auth\n  tags: [security, audit, readonly]\n- statement: "Audit accounts must undergo an annual access review."\n  domain: compliance\n  tags: [audit, review]\n' \
  | "$SCRIPTS/bites-extract.sh" --source-file specs/001-test/clarify.md --feature 001-test)"
drafts_file="$(jq -r '.drafts_file' <<< "$extract_out")"
[[ -f "$drafts_file" ]] || fail "drafts file not created"
pass "staged $(jq -r '.kept' <<< "$extract_out") draft(s) -> $drafts_file"

echo "==> 8. coverage"
mkdir -p specs/001-test
cat > specs/001-test/spec.md <<'EOF'
# Test spec
## Requirements
- FR-1: Admin login uses MFA. [BB-AUTH-001]
- FR-2: Sessions expire on idle. (no bite cite)
EOF
# Inject FR-1 reference into BB-AUTH-001 body so coverage detects it.
echo "Covers FR-1." >> ".specify/bites/domains/auth/${id1}"-*.md
"$SCRIPTS/bites-index.sh" >/dev/null
cov="$("$SCRIPTS/bites-coverage.sh" --file specs/001-test/spec.md)"
[[ "$(jq -r --arg id "$id1" '.coverage["FR-1"] | index($id) != null' <<< "$cov")" == "true" ]] || fail "FR-1 not covered"
[[ "$(jq -r '.uncovered | index("FR-2") != null' <<< "$cov")" == "true" ]] || fail "FR-2 should be uncovered"
pass "coverage report consistent"

echo "==> 9. conflict (synthetic)"
"$SCRIPTS/bites-add.sh" --statement "Admin sessions must never expire." --domain auth --tags "security,admin,session" >/dev/null
con="$("$SCRIPTS/bites-conflict.sh")"
[[ "$(jq 'length' <<< "$con")" -ge 1 ]] || fail "expected at least one conflict candidate"
pass "conflict detection flagged $(jq 'length' <<< "$con") pair(s)"

echo "==> 10. promote draft"
prom="$("$SCRIPTS/bites-promote.sh" --from-file "$drafts_file" --index 0)"
prom_id="$(jq -r '.id' <<< "$prom")"
prom_path="$(jq -r '.path' <<< "$prom")"
[[ -n "$prom_id" ]] || fail "promote did not return an id"
[[ -f "$prom_path" ]] || fail "promoted file missing at $prom_path"
[[ "$(jq -r --arg id "$prom_id" '.bites | any(.id == $id)' .specify/bites/index.json)" == "true" ]] || fail "promoted bite missing from index"
pass "promoted draft -> $prom_id ($(jq -r '.remaining_stubs' <<< "$prom") stub(s) left)"

echo "==> 11. reject draft"
rej="$("$SCRIPTS/bites-reject.sh" --from-file "$drafts_file" --index 0 --reason "self-test rejection")"
rej_into="$(jq -r '.rejected_into' <<< "$rej")"
[[ -f "$rej_into" ]] || fail "rejected file missing at $rej_into"
[[ "$(yq eval -r '.[0].rejected.reason' "$rej_into")" == "self-test rejection" ]] || fail "rejected stub missing reason"
[[ "$(jq -r '.remaining_stubs' <<< "$rej")" == "0" ]] || fail "expected 0 remaining stubs"
[[ ! -f "$drafts_file" ]] || fail "empty draft file should have been deleted"
pass "rejected draft -> $rej_into"

echo "==> 12. status change (archive + restore)"
st="$("$SCRIPTS/bites-status.sh" --id "$id2" --status superseded)"
new_path="$(jq -r '.new_path' <<< "$st")"
[[ "$new_path" == .specify/bites/_archive/auth/* ]] || fail "superseded bite not in _archive: $new_path"
[[ -f "$new_path" ]] || fail "moved file missing at $new_path"
restore="$("$SCRIPTS/bites-status.sh" --id "$id2" --status active)"
restored="$(jq -r '.new_path' <<< "$restore")"
[[ "$restored" == .specify/bites/domains/auth/* ]] || fail "restored bite not in domains: $restored"
[[ "$(jq -r --arg id "$id2" '.bites[] | select(.id == $id) | .source.superseded_by' .specify/bites/index.json)" == "null" ]] || fail "superseded_by not cleared on restore"
pass "status round-trip ok"

echo "==> 13. edit (tags)"
ed="$("$SCRIPTS/bites-edit.sh" --id "$id1" --tags-csv "security,admin,mfa,rotated")"
[[ "$(jq -r '.changed | index("tags") != null' <<< "$ed")" == "true" ]] || fail "edit did not record tags change"
grep -q "rotated" ".specify/bites/domains/auth/${id1}"-*.md || fail "edited tag missing in file"
pass "edited tags on $id1"

echo "==> selftest passed"
