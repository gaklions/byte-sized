# rules-promote.ps1 — promote one draft stub to an active rule.
#
# Usage:
#   rules-promote.ps1 -FromFile <_drafts/foo.yml> -Index <N> [-OverridesJson <json>]
#
# Reads stub N from the YAML-array draft file, merges optional overrides
# (a JSON object, deep-merged on top of the stub), pipes the result into
# rules-add.ps1 -FromStdin via a child pwsh process so stdin actually flows
# (PowerShell's internal pipe carries objects, not bytes).
#
# Emits JSON: { id, path, draft_file, remaining_stubs }.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$FromFile,
    [Parameter(Mandatory=$true)] [int]$Index,
    [string]$OverridesJson = '{}'
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$absFrom = $FromFile
if (-not [System.IO.Path]::IsPathRooted($absFrom)) { $absFrom = Join-Path $root $FromFile }
if (-not (Test-Path $absFrom)) { throw "rules-promote: file not found: $absFrom" }

$stubsJson = & yq eval -o=json -I=0 '.' $absFrom
$type = ($stubsJson | & jq -r 'type').Trim()
if ($type -ne 'array') { throw "rules-promote: $absFrom is not a YAML array" }
$total = [int]($stubsJson | & jq 'length').Trim()
if ($Index -lt 0 -or $Index -ge $total) {
    throw "rules-promote: index $Index out of range (have $total)"
}

$stub = $stubsJson | & jq -c --argjson i $Index '.[$i]'
$merged = & jq -n -c --argjson s $stub --argjson o $OverridesJson '$s * $o'

# yq's multi-line output arrives as a string array; join with LF so we don't
# collapse it via $OFS when piping to the child pwsh below.
$yaml = ($merged | & yq eval -P '.' -) -join "`n"

# Spawn a child pwsh so the YAML reaches rules-add.ps1's [Console]::In.ReadToEnd().
$add = Join-Path $PSScriptRoot 'rules-add.ps1'
$result = $yaml | & pwsh -NoProfile -File $add -FromStdin

$remaining = $stubsJson | & jq -c --argjson i $Index 'del(.[$i])'
$remainingLen = [int]($remaining | & jq 'length').Trim()
if ($remainingLen -eq 0) {
    Remove-Item -LiteralPath $absFrom -Force
} else {
    $remaining | & yq eval -P '.' - | Set-Content -LiteralPath $absFrom -Encoding utf8
}

$newId   = ($result | & jq -r '.id').Trim()
$newPath = ($result | & jq -r '.path').Trim()
$draftRel = ($absFrom.Substring($root.Length + 1)).Replace('\','/')

[pscustomobject]@{
    id = $newId
    path = $newPath
    draft_file = $draftRel
    remaining_stubs = $remainingLen
} | ConvertTo-Json -Compress
