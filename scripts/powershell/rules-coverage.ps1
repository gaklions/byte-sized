# rules-coverage.ps1 — map functional requirements / tasks to covering rules.

[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$File)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

if (-not (Test-Path $File)) { throw "rules-coverage: $File does not exist" }

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'
if (-not (Test-Path $index)) { & "$PSScriptRoot/rules-index.ps1" | Out-Null }

$content = Get-Content -LiteralPath $File -Raw
$tokens = [regex]::Matches($content, '\b(FR|NFR|TASK)-[0-9]+\b') | ForEach-Object { $_.Value } | Sort-Object -Unique

$coverage = '{}'
foreach ($t in $tokens) {
    $hits = '[]'
    $paths = (& jq -r '.rules[].path // ""' $index) -split "`n" | Where-Object { $_ }
    foreach ($p in $paths) {
        $full = Join-Path $root $p
        if (-not (Test-Path $full)) { continue }
        if (Select-String -Path $full -Pattern "\b$t\b" -Quiet) {
            $id = (& jq -r --arg p $p '.rules[] | select(.path == $p) | .id' $index).Trim()
            if ($id) { $hits = $hits | & jq -c --arg id $id '. + [$id] | unique' }
        }
    }
    $coverage = $coverage | & jq -c --arg t $t --argjson h $hits '. + {($t): $h}'
}

$uncovered = $coverage | & jq -c 'to_entries | map(select((.value | length) == 0)) | map(.key)'
$orphan = & jq -c '[.rules[] | select(.status == "active") | select(((.source.spec // "") == "") and ((.source.feature // "") == "")) | .id]' $index

& jq -n --argjson cov $coverage --argjson un $uncovered --argjson orph $orphan `
    '{coverage: $cov, uncovered: $un, orphan_rules: $orph}'
