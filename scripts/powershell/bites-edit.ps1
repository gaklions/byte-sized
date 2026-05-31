# bites-edit.ps1 — edit frontmatter fields of an existing bite in place.
#
# Usage:
#   bites-edit.ps1 -Id <BB-...> [-Statement <s>] [-RationaleFile <path>]
#                  [-Domain <d>] [-TagsCsv <a,b,c>]
#
# Filenames are stable: editing the statement does NOT re-slug the filename.
# Changing the domain moves the file under the new domains/<domain>/ (or
# _archive/<domain>/ if the current status is superseded), preserving the
# filename. The markdown body is left untouched.
#
# Emits JSON: { id, old_path, new_path, changed }.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$Id,
    [string]$Statement,
    [string]$RationaleFile,
    [string]$Domain,
    [string]$TagsCsv
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$bitesDir = Get-BsBitesDir -Root $root
$index = Join-Path $bitesDir 'index.json'

$hasStatement = $PSBoundParameters.ContainsKey('Statement')
$hasRationale = $PSBoundParameters.ContainsKey('RationaleFile')
$hasDomain    = $PSBoundParameters.ContainsKey('Domain')
$hasTags      = $PSBoundParameters.ContainsKey('TagsCsv')

Invoke-BsWithLock -LockPath (Join-Path $bitesDir '.index.lock') -Action {
    $oldPath = (& jq -r --arg id $Id '.bites[] | select(.id == $id) | .path // ""' $index).Trim()
    if (-not $oldPath) { throw "bites-edit: $Id not found" }
    $oldAbs = Join-Path $root $oldPath

    $fmYaml = Get-BsFrontmatter -File $oldAbs
    $body = Get-BsBody -File $oldAbs
    $fmJson = $fmYaml | & yq eval -o=json -I=0 '.' -
    $status = ($fmJson | & jq -r '.status // "active"').Trim()
    $oldDomain = ($fmJson | & jq -r '.domain // ""').Trim()
    $newDomain = $oldDomain
    $changed = @()

    if ($hasStatement) {
        $fmJson = $fmJson | & jq -c --arg v $Statement '.statement = $v'
        $changed += 'statement'
    }
    if ($hasRationale) {
        if (-not (Test-Path $RationaleFile)) { throw "bites-edit: rationale file not found: $RationaleFile" }
        $rat = Get-Content -LiteralPath $RationaleFile -Raw
        $fmJson = $fmJson | & jq -c --arg v $rat '.rationale = $v'
        $changed += 'rationale'
    }
    if ($hasDomain) {
        $newDomain = $Domain.ToLowerInvariant()
        $fmJson = $fmJson | & jq -c --arg v $newDomain '.domain = $v'
        $changed += 'domain'
    }
    if ($hasTags) {
        $tagsArr = @($TagsCsv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $tagsJson = if ($tagsArr.Count -eq 0) { '[]' } else { ($tagsArr | ConvertTo-Json -Compress -AsArray) }
        $fmJson = $fmJson | & jq -c --argjson v $tagsJson '.tags = $v'
        $changed += 'tags'
    }

    # Join multi-line yq output with LF; here-string $OFS would otherwise collapse it.
    $newFm = ($fmJson | & yq eval -P '.' -) -join "`n"

    $newAbs = $oldAbs
    if ($newDomain -ne $oldDomain) {
        $filename = Split-Path $oldAbs -Leaf
        if ($status -eq 'superseded') {
            $targetDir = Join-Path $bitesDir "_archive/$newDomain"
        } else {
            $targetDir = Join-Path $bitesDir "domains/$newDomain"
        }
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        $newAbs = Join-Path $targetDir $filename
    }

    @"
---
$newFm
---
$body
"@ | Set-Content -LiteralPath $newAbs -Encoding utf8

    if ($oldAbs -ne $newAbs) { Remove-Item -LiteralPath $oldAbs -Force }

    & "$PSScriptRoot/bites-index.ps1" | Out-Null

    $changedJson = if ($changed.Count -eq 0) { '[]' } else { ($changed | ConvertTo-Json -Compress -AsArray) }
    [pscustomobject]@{
        id = $Id
        old_path = ($oldAbs.Substring($root.Length + 1)).Replace('\','/')
        new_path = ($newAbs.Substring($root.Length + 1)).Replace('\','/')
        changed = ($changedJson | ConvertFrom-Json)
    } | ConvertTo-Json -Compress
}
