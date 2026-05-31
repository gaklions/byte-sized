# rules-status.ps1 — change a rule's status; physically move file between
# domains/<domain>/ and _archive/<domain>/ as needed; regenerate index.
#
# Usage:
#   rules-status.ps1 -Id <BR-...> -Status <active|deprecated|superseded> [-Reason <text>]
#
# Location rule:
#   active | deprecated → domains/<domain>/
#   superseded         → _archive/<domain>/
#
# Demoting `superseded` back to `active` clears source.superseded_by.
# Filename is preserved across moves so external links / git history stay stable.
#
# Emits JSON: { id, new_status, old_path, new_path }.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$Id,
    [Parameter(Mandatory=$true)] [ValidateSet('active','deprecated','superseded')] [string]$Status,
    [string]$Reason = ''
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'

Invoke-BsWithLock -LockPath (Join-Path $rulesDir '.index.lock') -Action {
    $oldPath = (& jq -r --arg id $Id '.rules[] | select(.id == $id) | .path // ""' $index).Trim()
    if (-not $oldPath) { throw "rules-status: $Id not found" }
    $oldAbs = Join-Path $root $oldPath

    $fmYaml = Get-BsFrontmatter -File $oldAbs
    $body = Get-BsBody -File $oldAbs
    $fmJson = $fmYaml | & yq eval -o=json -I=0 '.' -
    $domain = ($fmJson | & jq -r '.domain // ""').Trim()
    if (-not $domain) { throw "rules-status: $Id has no domain" }

    if ($Status -eq 'active') {
        $fmJson = $fmJson | & jq -c '.status = "active" | .source.superseded_by = null'
    } else {
        $fmJson = $fmJson | & jq -c --arg s $Status '.status = $s'
    }
    # Join multi-line yq output with LF; here-string $OFS would otherwise collapse it.
    $newFm = ($fmJson | & yq eval -P '.' -) -join "`n"

    $filename = Split-Path $oldAbs -Leaf
    if ($Status -eq 'superseded') {
        $targetDir = Join-Path $rulesDir "_archive/$domain"
    } else {
        $targetDir = Join-Path $rulesDir "domains/$domain"
    }
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    $newAbs = Join-Path $targetDir $filename

    @"
---
$newFm
---
$body
"@ | Set-Content -LiteralPath $newAbs -Encoding utf8

    if ($oldAbs -ne $newAbs) { Remove-Item -LiteralPath $oldAbs -Force }

    & "$PSScriptRoot/rules-index.ps1" | Out-Null

    [pscustomobject]@{
        id = $Id
        new_status = $Status
        old_path = ($oldAbs.Substring($root.Length + 1)).Replace('\','/')
        new_path = ($newAbs.Substring($root.Length + 1)).Replace('\','/')
    } | ConvertTo-Json -Compress
}
