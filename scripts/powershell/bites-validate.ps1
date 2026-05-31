# bites-validate.ps1 — check graph integrity.

[CmdletBinding()]
param()

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$bitesDir = Get-BsBitesDir -Root $root
$index = Join-Path $bitesDir 'index.json'
$cfg = Get-BsConfigPath -Root $root

if (-not (Test-Path $index)) {
    & "$PSScriptRoot/bites-index.ps1" | Out-Null
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$domains = & yq eval -o=json -I=0 '.domains // []' $cfg

# jq -c '.bites[]' returns one compact JSON object per line; PS captures them
# as an [object[]] of strings. Don't `-split "`n"` it (that joins via $OFS).
# Native output on Windows can have trailing CRs; trim each element.
$bitesJson = @(& jq -c '.bites[]' $index) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
foreach ($r in $bitesJson) {
    if (-not $r) { continue }
    $id = ($r | & jq -r '.id // ""').Trim()
    foreach ($f in 'id','statement','domain','status') {
        $v = ($r | & jq -r --arg f $f '.[$f] // ""').Trim()
        if (-not $v) { [void]$errors.Add("missing field '$f' in bite $(if($id){$id}else{'<unknown>'})") }
    }
    $st = ($r | & jq -r '.status').Trim()
    if ($st -notin @('active','draft','superseded','deprecated')) { [void]$errors.Add("invalid status '$st' in $id") }
    $dom = ($r | & jq -r '.domain').Trim()
    & jq -e --arg d $dom 'index($d)' --argjson w $domains -n '$w' >$null 2>&1
    if ($LASTEXITCODE -ne 0) { [void]$warnings.Add("$id uses domain '$dom' not in config.domains") }
}

$dupes = @(& jq -r '.bites | group_by(.id) | map(select(length>1)) | .[].[0].id' $index)
foreach ($d in $dupes) {
    if ($d) { [void]$errors.Add("duplicate id: $d") }
}

$allIds = @(& jq -r '.bites[].id' $index) | Where-Object { $_ } | Sort-Object -Unique
foreach ($r in $bitesJson) {
    if (-not $r) { continue }
    $id = ($r | & jq -r '.id').Trim()
    foreach ($rel in 'relates_to','supersedes','depends_on','conflicts_with') {
        $targets = @($r | & jq -r --arg k $rel '.edges[$k] // [] | .[]') | Where-Object { $_ }
        foreach ($t in $targets) {
            if ($allIds -notcontains $t) { [void]$errors.Add("${id} -[${rel}]-> ${t}: target missing") }
        }
    }
    $sb = ($r | & jq -r '.source.superseded_by // ""').Trim()
    $st = ($r | & jq -r '.status').Trim()
    if ($st -eq 'superseded' -and -not $sb) { [void]$warnings.Add("$id is 'superseded' but source.superseded_by is empty") }
}

$report = [pscustomobject]@{
    errors   = @($errors)
    warnings = @($warnings)
    ok       = ($errors.Count -eq 0)
}
$report | ConvertTo-Json -Depth 4
if (-not $report.ok) { exit 1 }
