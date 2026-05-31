# rules-get.ps1 — fetch one or more rules by id, optionally with N-hop neighbours.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Ids,
    [int]$Neighbors = 0,
    [ValidateSet('json','markdown')]
    [string]$Format = 'json'
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

# Separate flags accidentally caught by ValueFromRemainingArguments.
$cleanIds = @()
$i = 0
while ($i -lt $Ids.Count) {
    $a = $Ids[$i]
    switch ($a) {
        '--neighbors' { $Neighbors = [int]$Ids[$i+1]; $i += 2 }
        '--format'    { $Format = $Ids[$i+1]; $i += 2 }
        default       { $cleanIds += $a; $i++ }
    }
}
if ($cleanIds.Count -eq 0) { throw "rules-get: at least one id is required" }

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'
if (-not (Test-Path $index)) { throw "byte-sized: index missing; run rules-index.ps1" }

$expanded = ($cleanIds | ConvertTo-Json -Compress)
if ($cleanIds.Count -eq 1) { $expanded = "[`"$($cleanIds[0])`"]" }

for ($h = 0; $h -lt $Neighbors; $h++) {
    $expanded = & jq --slurpfile idx $index --argjson seeds $expanded '
        ($idx[0].rules) as $all
        | ($seeds + (
            $all | map(select(.id as $i | $seeds | index($i)))
                 | map(.edges // {})
                 | map([
                     (.relates_to // []),
                     (.depends_on // []),
                     (.supersedes // []),
                     (.conflicts_with // []),
                     (.related_by_others // []),
                     (.depended_on_by // []),
                     (.superseded_by_others // []),
                     (.conflicts_with_others // [])
                   ] | add)
                 | add // []
          )) | unique
    '
}

$results = '[]'
foreach ($id in (& jq -r '.[]' --argjson e $expanded -n '$e')) {
    $path = (& jq -r --arg id $id '.rules[] | select(.id == $id) | .path // ""' $index).Trim()
    if (-not $path) { Write-Warning "rules-get: id '$id' not found"; continue }
    $abs = Join-Path $root $path
    $fmJson = Get-BsFrontmatterJson -File $abs
    $body = Get-BsBody -File $abs
    $rec = & jq -n --argjson fm $fmJson --arg body $body --arg path $path '$fm + {body: $body, path: $path}'
    $results = $results | & jq --argjson r $rec '. + [$r]'
}

if ($Format -eq 'markdown') {
    $results | & jq -r '.[] | "---\n" + (del(.body, .path) | tojson) + "\n---\n\n" + (.body // "") + "\n\n"'
} else {
    Write-Output $results
}
