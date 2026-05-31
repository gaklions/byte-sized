# rules-link.ps1 — add or remove an edge between two existing rules.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)] [string]$From,
    [Parameter(Mandatory=$true, Position=1)] [ValidateSet('relates_to','supersedes','depends_on','conflicts_with')]
    [string]$Relation,
    [Parameter(Mandatory=$true, Position=2)] [string]$To,
    [switch]$Remove
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'

Invoke-BsWithLock -LockPath (Join-Path $rulesDir '.index.lock') -Action {
    $fromPath = (& jq -r --arg id $From '.rules[] | select(.id == $id) | .path // ""' $index).Trim()
    $toPath   = (& jq -r --arg id $To   '.rules[] | select(.id == $id) | .path // ""' $index).Trim()
    if (-not $fromPath) { throw "rules-link: $From not found" }
    if (-not $toPath)   { throw "rules-link: $To not found" }

    $abs = Join-Path $root $fromPath
    $fmYaml = Get-BsFrontmatter -File $abs
    $body = Get-BsBody -File $abs

    if ($Remove) {
        $newFm = ($fmYaml | & yq eval ".edges.$Relation = ((.edges.$Relation // []) | unique - [`"$To`"])" -) -join "`n"
    } else {
        $newFm = ($fmYaml | & yq eval ".edges.$Relation = ((.edges.$Relation // []) + [`"$To`"] | unique)" -) -join "`n"
    }

    @"
---
$newFm
---
$body
"@ | Set-Content -LiteralPath $abs -Encoding utf8

    if ($Relation -eq 'supersedes' -and -not $Remove) {
        $target = Join-Path $root $toPath
        $tgtFm = Get-BsFrontmatter -File $target
        $tgtBody = Get-BsBody -File $target
        $newTgt = ($tgtFm | & yq eval ".status = `"superseded`" | .source.superseded_by = `"$From`"" -) -join "`n"
        @"
---
$newTgt
---
$tgtBody
"@ | Set-Content -LiteralPath $target -Encoding utf8
    }

    & "$PSScriptRoot/rules-index.ps1" | Out-Null
    $verb = if ($Remove) { 'removed' } else { 'added' }
    [Console]::Error.WriteLine("byte-sized: $verb $From -[$Relation]-> $To")
}
