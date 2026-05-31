# rules-add.ps1 — create a new rule file from a YAML stub on stdin or flags.

[CmdletBinding()]
param(
    [string]$Statement,
    [string]$Rationale,
    [string]$Domain,
    [string]$Tags,
    [string]$Status = 'active',
    [string]$Id,
    [string]$SourceFeature,
    [string]$SourceSpec,
    [switch]$FromStdin
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$cfg = Get-BsConfigPath -Root $root
$idPrefix = Get-BsCfg -Cfg $cfg -Path '.storage.id_prefix' -Default 'BR'

Invoke-BsWithLock -LockPath (Join-Path $rulesDir '.index.lock') -Action {
    if ($FromStdin) {
        $stdin = [Console]::In.ReadToEnd()
        $json = $stdin | & yq eval -o=json '.' -
        if (-not $Statement)     { $Statement     = (& jq -r '.statement // ""' --argjson s $json -n '$s' | Out-String).Trim() }
        if (-not $Rationale)     { $Rationale     = (& jq -r '.rationale // ""' --argjson s $json -n '$s' | Out-String).Trim() }
        if (-not $Domain)        { $Domain        = (& jq -r '.domain // ""'    --argjson s $json -n '$s' | Out-String).Trim() }
        if (-not $Tags)          { $Tags          = (& jq -r '(.tags // []) | join(",")' --argjson s $json -n '$s' | Out-String).Trim() }
        if (-not $SourceFeature) { $SourceFeature = (& jq -r '.source.feature // ""' --argjson s $json -n '$s' | Out-String).Trim() }
        if (-not $SourceSpec)    { $SourceSpec    = (& jq -r '.source.spec // ""'    --argjson s $json -n '$s' | Out-String).Trim() }
        if (-not $Id)            { $Id            = (& jq -r '.id // ""'           --argjson s $json -n '$s' | Out-String).Trim() }
    }

    if (-not $Statement -or -not $Domain) {
        throw "rules-add: -Statement and -Domain are required"
    }

    $domainUpper = $Domain.ToUpperInvariant()
    $domainLower = $Domain.ToLowerInvariant()
    $domainPath = Join-Path $rulesDir "domains/$domainLower"
    if (-not (Test-Path $domainPath)) { New-Item -ItemType Directory -Path $domainPath | Out-Null }

    $index = Join-Path $rulesDir 'index.json'
    if (-not $Id) {
        $next = 1
        if (Test-Path $index) {
            $prefix = "$idPrefix-$domainUpper-"
            $maxStr = (& jq -r --arg p $prefix '
                .rules | map(.id // "") | map(select(startswith($p)))
                | map(. | sub($p; "") | tonumber? // 0) | max // 0
            ' $index).Trim()
            $next = [int]$maxStr + 1
        }
        $Id = '{0}-{1}-{2:D3}' -f $idPrefix, $domainUpper, $next
    }

    if (Test-Path $index) {
        $dup = (& jq -r --arg id $Id '.rules | map(select(.id == $id)) | length' $index).Trim()
        if ($dup -ne '0') { throw "rules-add: id $Id already exists" }
    }

    $slug = ConvertTo-BsSlug -Text $Statement
    if ($slug.Length -gt 48) { $slug = $slug.Substring(0,48) }
    $file = Join-Path $domainPath "$Id-$slug.md"
    $today = Get-BsToday

    $tagsArr = @()
    if ($Tags) { $tagsArr = $Tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
    $tagsJson = ($tagsArr | ConvertTo-Json -Compress)
    if (-not $tagsJson) { $tagsJson = '[]' }
    if ($tagsArr.Count -eq 1) { $tagsJson = "[`"$($tagsArr[0])`"]" }

    $fmJson = & jq -n `
        --arg id $Id --arg st $Statement --arg ra $Rationale `
        --arg dom $domainLower --argjson tags $tagsJson `
        --arg status $Status --arg feat ($SourceFeature ?? '') `
        --arg spec ($SourceSpec ?? '') --arg today $today '
        {
            id: $id, statement: $st, rationale: $ra,
            domain: $dom, tags: $tags, status: $status,
            source: { feature: $feat, spec: $spec, created: $today, superseded_by: null },
            edges: { relates_to: [], supersedes: [], depends_on: [], conflicts_with: [] }
        }'

    $yaml = $fmJson | & yq eval -P '.' -

    $content = @"
---
$yaml
---

## Context

_To be filled in._

## Implications

_To be filled in._
"@
    $content | Set-Content -LiteralPath $file -Encoding utf8

    & "$PSScriptRoot/rules-index.ps1" | Out-Null

    [pscustomobject]@{
        id = $Id
        path = ($file.Substring($root.Length + 1)).Replace('\','/')
    } | ConvertTo-Json -Compress
}
