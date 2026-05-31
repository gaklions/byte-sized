# rules-validate.ps1 — check graph integrity.

[CmdletBinding()]
param()

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'
$cfg = Get-BsConfigPath -Root $root

if (-not (Test-Path $index)) {
    & "$PSScriptRoot/rules-index.ps1" | Out-Null
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$domains = & yq eval -o=json '.domains // []' $cfg

$rulesJson = & jq -c '.rules[]' $index
foreach ($r in ($rulesJson -split "`n" | Where-Object { $_ })) {
    $id = (& jq -r '.id // ""' --argjson r $r -n '$r').Trim()
    foreach ($f in 'id','statement','domain','status') {
        $v = (& jq -r --arg f $f '.[$f] // ""' --argjson r $r -n '$r').Trim()
        if (-not $v) { [void]$errors.Add("missing field '$f' in rule $(if($id){$id}else{'<unknown>'})") }
    }
    $st = (& jq -r '.status' --argjson r $r -n '$r').Trim()
    if ($st -notin @('active','draft','superseded','deprecated')) { [void]$errors.Add("invalid status '$st' in $id") }
    $dom = (& jq -r '.domain' --argjson r $r -n '$r').Trim()
    $inWl = (& jq -e --arg d $dom 'index($d)' --argjson w $domains -n '$w') 2>$null
    if (-not $?) { [void]$warnings.Add("$id uses domain '$dom' not in config.domains") }
}

$dupes = & jq -r '.rules | group_by(.id) | map(select(length>1)) | .[].[0].id' $index
foreach ($d in ($dupes -split "`n" | Where-Object { $_ })) { [void]$errors.Add("duplicate id: $d") }

$allIds = (& jq -r '.rules[].id' $index) -split "`n" | Where-Object { $_ } | Sort-Object -Unique
foreach ($r in ($rulesJson -split "`n" | Where-Object { $_ })) {
    $id = (& jq -r '.id' --argjson r $r -n '$r').Trim()
    foreach ($rel in 'relates_to','supersedes','depends_on','conflicts_with') {
        $targets = (& jq -r --arg k $rel '.edges[$k] // [] | .[]' --argjson r $r -n '$r') -split "`n" | Where-Object { $_ }
        foreach ($t in $targets) {
            if ($allIds -notcontains $t) { [void]$errors.Add("${id} -[${rel}]-> ${t}: target missing") }
        }
    }
    $sb = (& jq -r '.source.superseded_by // ""' --argjson r $r -n '$r').Trim()
    $st = (& jq -r '.status' --argjson r $r -n '$r').Trim()
    if ($st -eq 'superseded' -and -not $sb) { [void]$warnings.Add("$id is 'superseded' but source.superseded_by is empty") }
}

$report = [pscustomobject]@{
    errors   = @($errors)
    warnings = @($warnings)
    ok       = ($errors.Count -eq 0)
}
$report | ConvertTo-Json -Depth 4
if (-not $report.ok) { exit 1 }
