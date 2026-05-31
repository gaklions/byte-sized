# bites-reject.ps1 — reject one draft stub; move it into _drafts/_rejected/<basename>
# with audit fields ({ rejected: { at, reason } }) appended.
#
# Usage:
#   bites-reject.ps1 -FromFile <_drafts/foo.yml> -Index <N> [-Reason <text>]
#
# Emits JSON: { rejected_into, remaining_stubs }.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$FromFile,
    [Parameter(Mandatory=$true)] [int]$Index,
    [string]$Reason = ''
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$bitesDir = Get-BsBitesDir -Root $root
$cfg = Get-BsConfigPath -Root $root
$draftsRel = Get-BsCfg -Cfg $cfg -Path '.extraction.drafts_dir' -Default '_drafts'
$draftsDir = Join-Path $bitesDir $draftsRel
$rejectedDir = Join-Path $draftsDir '_rejected'
if (-not (Test-Path $rejectedDir)) { New-Item -ItemType Directory -Path $rejectedDir -Force | Out-Null }

$absFrom = $FromFile
if (-not [System.IO.Path]::IsPathRooted($absFrom)) { $absFrom = Join-Path $root $FromFile }
if (-not (Test-Path $absFrom)) { throw "bites-reject: file not found: $absFrom" }

$stubsJson = & yq eval -o=json -I=0 '.' $absFrom
$type = ($stubsJson | & jq -r 'type').Trim()
if ($type -ne 'array') { throw "bites-reject: $absFrom is not a YAML array" }
$total = [int]($stubsJson | & jq 'length').Trim()
if ($Index -lt 0 -or $Index -ge $total) {
    throw "bites-reject: index $Index out of range (have $total)"
}

$stub = $stubsJson | & jq -c --argjson i $Index '.[$i]'
$now = Get-BsNowIso
$audited = $stub | & jq -c --arg at $now --arg r $Reason '. + {rejected: {at: $at, reason: $r}}'

$baseName = Split-Path $absFrom -Leaf
$rejectedFile = Join-Path $rejectedDir $baseName
$existing = '[]'
if (Test-Path $rejectedFile) {
    $existing = & yq eval -o=json -I=0 '.' $rejectedFile 2>$null
    if (-not $existing) { $existing = '[]' }
    $t = ($existing | & jq -r 'type').Trim()
    if ($t -ne 'array') { $existing = '[]' }
}
$updated = $existing | & jq -c --argjson s $audited '. + [$s]'
$updated | & yq eval -P '.' - | Set-Content -LiteralPath $rejectedFile -Encoding utf8

$remaining = $stubsJson | & jq -c --argjson i $Index 'del(.[$i])'
$remainingLen = [int]($remaining | & jq 'length').Trim()
if ($remainingLen -eq 0) {
    Remove-Item -LiteralPath $absFrom -Force
} else {
    $remaining | & yq eval -P '.' - | Set-Content -LiteralPath $absFrom -Encoding utf8
}

$rel = ($rejectedFile.Substring($root.Length + 1)).Replace('\','/')
[pscustomobject]@{
    rejected_into = $rel
    remaining_stubs = $remainingLen
} | ConvertTo-Json -Compress
