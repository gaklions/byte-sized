# selftest.ps1 — Windows mirror of selftest.sh.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SelftestDir = Split-Path $PSCommandPath -Parent
$ExtRoot     = Resolve-Path (Join-Path $SelftestDir '../..')
$Scripts     = Join-Path $ExtRoot 'scripts/powershell'

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("rg-selftest-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$extDir = Join-Path $sandbox '.specify/extensions/byte-sized'
New-Item -ItemType Directory -Path $extDir | Out-Null
Copy-Item (Join-Path $ExtRoot 'config-template.yml') (Join-Path $extDir 'config-template.yml')

try {
    Push-Location $sandbox

    function Test-Pass([string]$m) { Write-Host "  PASS: $m" }
    function Test-Fail([string]$m) { Write-Error "  FAIL: $m"; exit 1 }

    Write-Host "==> 1. init"
    & "$Scripts/bites-init.ps1" | Out-Null
    if (-not (Test-Path '.specify/bites/domains')) { Test-Fail "init did not create domains/" }
    if (-not (Test-Path '.specify/bites/index.json')) { Test-Fail "init did not create index.json" }
    Test-Pass "init scaffolded storage"

    Write-Host "==> 2. add"
    $out1 = & "$Scripts/bites-add.ps1" -Statement "MFA is required for all admin accounts." -Domain auth -Tags "security,admin,mfa" -Rationale "Mitigates credential theft." -SourceFeature 001-test -SourceSpec "specs/001-test/spec.md#FR-1"
    $id1 = ($out1 | & jq -r '.id').Trim()
    if ($id1 -ne 'BB-AUTH-001') { Test-Fail "expected BB-AUTH-001, got $id1" }
    Test-Pass "added $id1"

    $out2 = & "$Scripts/bites-add.ps1" -Statement "Admin sessions must always expire after 30 minutes of inactivity." -Domain auth -Tags "security,admin,session"
    $id2 = ($out2 | & jq -r '.id').Trim()
    if ($id2 -ne 'BB-AUTH-002') { Test-Fail "expected BB-AUTH-002, got $id2" }
    Test-Pass "added $id2"

    Write-Host "==> 3. link"
    & "$Scripts/bites-link.ps1" -From $id1 -Relation relates_to -To $id2 | Out-Null
    $linkFile = Get-ChildItem ".specify/bites/domains/auth" -Filter "$id1-*.md" | Select-Object -First 1
    if (-not (Select-String -Path $linkFile.FullName -Pattern $id2 -Quiet)) { Test-Fail "edge not written" }
    Test-Pass "linked $id1 relates_to $id2"

    Write-Host "==> 4. query"
    $q = & "$Scripts/bites-query.ps1" -Text "admin mfa security" -Limit 5
    if (([int]($q | & jq 'length').Trim()) -lt 1) { Test-Fail "query returned nothing" }
    if (($q | & jq -r --arg id $id1 'any(.[]; .id == $id)').Trim() -ne 'true') { Test-Fail "query missing $id1" }
    Test-Pass "query returned $(($q | & jq 'length').Trim()) result(s)"

    Write-Host "==> 5. get with neighbours"
    $g = & "$Scripts/bites-get.ps1" $id1 -Neighbors 1
    if (([int]($g | & jq 'length').Trim()) -lt 2) { Test-Fail "neighbour expansion did not include $id2" }
    Test-Pass "get returned $(($g | & jq 'length').Trim()) bite(s)"

    Write-Host "==> 6. validate"
    $v = & "$Scripts/bites-validate.ps1"
    if (($v | & jq -r '.ok').Trim() -ne 'true') { Test-Fail "validate not ok" }
    Test-Pass "validate ok"

    Write-Host "==> 7. extract"
    New-Item -ItemType Directory -Path 'specs/001-test' -Force | Out-Null
    @"
## Q&A
Q: What about read-only audit accounts?
A: Audit accounts must not have write access. They also must have an annual access review.
"@ | Set-Content -Path 'specs/001-test/clarify.md' -Encoding utf8

    $candidates = @"
- statement: "Audit accounts must not have write access."
  domain: auth
  tags: [security, audit, readonly]
- statement: "Audit accounts must undergo an annual access review."
  domain: compliance
  tags: [audit, review]
"@
    $extractOut = $candidates | & pwsh -NoProfile -File "$Scripts/bites-extract.ps1" -SourceFile 'specs/001-test/clarify.md' -Feature '001-test'
    $draftsFile = ($extractOut | & jq -r '.drafts_file').Trim()
    if (-not (Test-Path $draftsFile)) { Test-Fail "drafts file not created" }
    Test-Pass "staged $(($extractOut | & jq -r '.kept').Trim()) draft(s) -> $draftsFile"

    Write-Host "==> 8. coverage"
    @"
# Test spec
## Requirements
- FR-1: Admin login uses MFA. [BB-AUTH-001]
- FR-2: Sessions expire on idle. (no bite cite)
"@ | Set-Content -Path 'specs/001-test/spec.md' -Encoding utf8
    $bite1 = Get-ChildItem ".specify/bites/domains/auth" -Filter "$id1-*.md" | Select-Object -First 1
    Add-Content -Path $bite1.FullName -Value "Covers FR-1."
    & "$Scripts/bites-index.ps1" | Out-Null
    $cov = & "$Scripts/bites-coverage.ps1" -File 'specs/001-test/spec.md'
    if (($cov | & jq -r --arg id $id1 '.coverage["FR-1"] | index($id) != null').Trim() -ne 'true') { Test-Fail "FR-1 not covered" }
    if (($cov | & jq -r '.uncovered | index("FR-2") != null').Trim() -ne 'true') { Test-Fail "FR-2 should be uncovered" }
    Test-Pass "coverage report consistent"

    Write-Host "==> 9. conflict (synthetic)"
    & "$Scripts/bites-add.ps1" -Statement "Admin sessions must never expire." -Domain auth -Tags "security,admin,session" | Out-Null
    $con = & "$Scripts/bites-conflict.ps1"
    if (([int]($con | & jq 'length').Trim()) -lt 1) { Test-Fail "expected at least one conflict candidate" }
    Test-Pass "conflict detection flagged $(($con | & jq 'length').Trim()) pair(s)"

    Write-Host "==> 10. promote draft"
    $prom = & "$Scripts/bites-promote.ps1" -FromFile $draftsFile -Index 0
    $promId   = ($prom | & jq -r '.id').Trim()
    $promPath = ($prom | & jq -r '.path').Trim()
    if (-not $promId) { Test-Fail "promote did not return an id" }
    if (-not (Test-Path $promPath)) { Test-Fail "promoted file missing at $promPath" }
    $idxJson = Get-Content -LiteralPath '.specify/bites/index.json' -Raw
    if (($idxJson | & jq -r --arg id $promId '.bites | any(.id == $id)').Trim() -ne 'true') { Test-Fail "promoted bite missing from index" }
    Test-Pass "promoted draft -> $promId ($(($prom | & jq -r '.remaining_stubs').Trim()) stub(s) left)"

    Write-Host "==> 11. reject draft"
    $rej = & "$Scripts/bites-reject.ps1" -FromFile $draftsFile -Index 0 -Reason "self-test rejection"
    $rejInto = ($rej | & jq -r '.rejected_into').Trim()
    if (-not (Test-Path $rejInto)) { Test-Fail "rejected file missing at $rejInto" }
    if ((& yq eval -r '.[0].rejected.reason' $rejInto).Trim() -ne 'self-test rejection') { Test-Fail "rejected stub missing reason" }
    if (($rej | & jq -r '.remaining_stubs').Trim() -ne '0') { Test-Fail "expected 0 remaining stubs" }
    if (Test-Path $draftsFile) { Test-Fail "empty draft file should have been deleted" }
    Test-Pass "rejected draft -> $rejInto"

    Write-Host "==> 12. status change (archive + restore)"
    $st = & "$Scripts/bites-status.ps1" -Id $id2 -Status superseded
    $newPath = ($st | & jq -r '.new_path').Trim()
    if (-not $newPath.StartsWith('.specify/bites/_archive/auth/')) { Test-Fail "superseded bite not in _archive: $newPath" }
    if (-not (Test-Path $newPath)) { Test-Fail "moved file missing at $newPath" }
    $restore = & "$Scripts/bites-status.ps1" -Id $id2 -Status active
    $restored = ($restore | & jq -r '.new_path').Trim()
    if (-not $restored.StartsWith('.specify/bites/domains/auth/')) { Test-Fail "restored bite not in domains: $restored" }
    $idxJson = Get-Content -LiteralPath '.specify/bites/index.json' -Raw
    if (($idxJson | & jq -r --arg id $id2 '.bites[] | select(.id == $id) | .source.superseded_by').Trim() -ne 'null') { Test-Fail "superseded_by not cleared on restore" }
    Test-Pass "status round-trip ok"

    Write-Host "==> 13. edit (tags)"
    $ed = & "$Scripts/bites-edit.ps1" -Id $id1 -TagsCsv "security,admin,mfa,rotated"
    if (($ed | & jq -r '.changed | index("tags") != null').Trim() -ne 'true') { Test-Fail "edit did not record tags change" }
    $editedFile = Get-ChildItem ".specify/bites/domains/auth" -Filter "$id1-*.md" | Select-Object -First 1
    if (-not (Select-String -Path $editedFile.FullName -Pattern 'rotated' -Quiet)) { Test-Fail "edited tag missing in file" }
    Test-Pass "edited tags on $id1"

    Write-Host "==> selftest passed"
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
