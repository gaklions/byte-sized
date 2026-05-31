# rules-conflict.ps1 — flag candidate conflicts between rules.

[CmdletBinding()]
param(
    [string]$Id,
    [string]$Stub
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'
$cfg = Get-BsConfigPath -Root $root

if (-not (Test-Path $index)) { Write-Output '[]'; return }

$rules = & jq -c '[.rules[] | select(.status == "active") | {id, statement, domain, tags}]' $index
if ($Stub -and (Test-Path $Stub)) {
    $stubJson = & yq eval -o=json -I=0 '.' $Stub
    $rules = $rules | & jq -c --argjson s $stubJson '. + [($s + {id: ($s.id // "STUB")})]'
}

$antonyms = & yq eval -o=json -I=0 '.conflict_detection.antonym_pairs // []' $cfg

$filter = @'
def low($s): ($s // "" | ascii_downcase);
def contains_phrase($haystack; $needle):
  (low($haystack) | test("\\b" + $needle + "\\b"));

[ range(0; $rs | length) as $i
  | range($i+1; $rs | length) as $j
  | $rs[$i] as $a | $rs[$j] as $b
  | select(($only | length) == 0 or $a.id == $only or $b.id == $only)
  | select($a.domain == $b.domain)
  | select(([$a.tags // [], $b.tags // []] | add | group_by(.) | map(select(length>1)) | length) > 0)
  | ( $ant | map(. as $p
      | select( (contains_phrase($a.statement; $p[0]) and contains_phrase($b.statement; $p[1]))
             or (contains_phrase($a.statement; $p[1]) and contains_phrase($b.statement; $p[0])) )
      | { pair: $p }) ) as $triggers
  | select(($triggers | length) > 0)
  | { from: $a.id, to: $b.id, domain: $a.domain, triggers: $triggers } ]
'@

# Multi-line jq filter mangled when passed as native arg on Windows; use -f.
$filterFile = New-TemporaryFile
try {
    $filter | Set-Content -LiteralPath $filterFile -Encoding utf8
    & jq -n --argjson rs $rules --argjson ant $antonyms --arg only ($Id ?? '') -f $filterFile
}
finally {
    Remove-Item -LiteralPath $filterFile -Force -ErrorAction SilentlyContinue
}
