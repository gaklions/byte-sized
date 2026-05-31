# bites-coverage.ps1 — map functional requirements / tasks to covering bites.

[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$File)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

if (-not (Test-Path $File)) { throw "bites-coverage: $File does not exist" }

$root = Get-BsRepoRoot
$bitesDir = Get-BsBitesDir -Root $root
$index = Join-Path $bitesDir 'index.json'
if (-not (Test-Path $index)) { & "$PSScriptRoot/bites-index.ps1" | Out-Null }

$content = Get-Content -LiteralPath $File -Raw
$tokens = [regex]::Matches($content, '\b(FR|NFR|TASK)-[0-9]+\b') | ForEach-Object { $_.Value } | Sort-Object -Unique

$coverage = '{}'
foreach ($t in $tokens) {
    $hits = '[]'
    $paths = (& jq -r '.bites[].path // ""' $index) -split "`n" | Where-Object { $_ }
    foreach ($p in $paths) {
        $full = Join-Path $root $p
        if (-not (Test-Path $full)) { continue }
        if (Select-String -Path $full -Pattern "\b$t\b" -Quiet) {
            $id = (& jq -r --arg p $p '.bites[] | select(.path == $p) | .id' $index).Trim()
            if ($id) { $hits = $hits | & jq -c --arg id $id '. + [$id] | unique' }
        }
    }
    $coverage = $coverage | & jq -c --arg t $t --argjson h $hits '. + {($t): $h}'
}

$uncovered = $coverage | & jq -c 'to_entries | map(select((.value | length) == 0)) | map(.key)'
$orphan = & jq -c '[.bites[] | select(.status == "active") | select(((.source.spec // "") == "") and ((.source.feature // "") == "")) | .id]' $index

& jq -n --argjson cov $coverage --argjson un $uncovered --argjson orph $orphan `
    '{coverage: $cov, uncovered: $un, orphan_bites: $orph}'
