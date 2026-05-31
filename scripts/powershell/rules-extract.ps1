# rules-extract.ps1 — stage candidate rules for human review.

[CmdletBinding()]
param(
    [string]$SourceFile,
    [string]$Feature,
    [string]$Out
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$cfg = Get-BsConfigPath -Root $root
$draftsRel = Get-BsCfg -Cfg $cfg -Path '.extraction.drafts_dir' -Default '_drafts'
$draftsDir = Join-Path $rulesDir $draftsRel
if (-not (Test-Path $draftsDir)) { New-Item -ItemType Directory -Path $draftsDir | Out-Null }

$ts = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$feat = if ($Feature) { $Feature } else { 'unscoped' }
if (-not $Out) { $Out = Join-Path $draftsDir "$feat-$ts.yml" }

$stdin = [Console]::In.ReadToEnd()
if (-not $stdin) { throw "rules-extract: pipe a YAML array of candidate stubs to stdin" }

$candidates = $stdin | & yq eval -o=json '.' -
$type = ($candidates | & jq -r 'type').Trim()
if ($type -ne 'array') { throw "rules-extract: stdin must be a YAML array of stubs" }

$valid = $candidates | & jq -c '[ .[] | select((.statement // "") | length > 0) ]'

$index = Join-Path $rulesDir 'index.json'
if (Test-Path $index) {
    $dedupFilter = 'def tokens($s): ($s // "" | ascii_downcase | gsub("[^a-z0-9 ]"; " ") | split(" ") | map(select(length>=3))); def overlap($a; $b): if (($a + $b) | length) == 0 then 0 else ([$a[] | select(. as $t | $b | index($t))] | length) / (([$a, $b] | add | unique) | length) end; . as $cands | $idx[0].rules as $existing | $cands | map(. as $c | (tokens($c.statement)) as $ct | if any($existing[]; (tokens(.statement) as $et | overlap($ct; $et) >= 0.7)) then empty else $c end)'
    $surviving = $valid | & jq -c --slurpfile idx $index $dedupFilter
} else {
    $surviving = $valid
}

$enrichFilter = 'map(. + {status: "draft", source: ((.source // {}) + {feature: $f, spec: $src})})'
$surviving = $surviving | & jq -c --arg f $feat --arg src ($SourceFile ?? '') $enrichFilter

$surviving | & yq eval -P '.' - | Set-Content -LiteralPath $Out -Encoding utf8

$validLen = [int]($valid | & jq 'length').Trim()
$survLen  = [int]($surviving | & jq 'length').Trim()

[pscustomobject]@{
    drafts_file = ($Out.Substring($root.Length + 1)).Replace('\','/')
    kept = $survLen
    dropped_as_duplicate = ($validLen - $survLen)
} | ConvertTo-Json -Compress
