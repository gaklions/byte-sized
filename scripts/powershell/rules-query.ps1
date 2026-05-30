# rules-query.ps1 — token-efficient projection from the rules index.

[CmdletBinding()]
param(
    [string]$Text,
    [string]$Tags,
    [string]$Domain,
    [string]$Status = 'active',
    [int]$Limit = 0,
    [switch]$IncludeDrafts,
    [string]$Ids
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'
$cfg = Get-BsConfigPath -Root $root

if (-not (Test-Path $index)) { Write-Output '[]'; return }

if ($Limit -le 0) { $Limit = [int](Get-BsCfg -Cfg $cfg -Path '.relevance.max_results' -Default '12') }
$minScore = [double](Get-BsCfg -Cfg $cfg -Path '.relevance.min_score' -Default '0.2')

$tokens = @()
if ($Text) {
    $tokens = ($Text.ToLowerInvariant() -split '[^a-z0-9]+') | Where-Object { $_.Length -ge 3 } | Sort-Object -Unique
}
$tokensJson = ($tokens | ConvertTo-Json -Compress)
if (-not $tokensJson) { $tokensJson = '[]' }

$draftsJson = '[]'
if ($IncludeDrafts) {
    $draftsDir = Join-Path $rulesDir (Get-BsCfg -Cfg $cfg -Path '.extraction.drafts_dir' -Default '_drafts')
    if (Test-Path $draftsDir) {
        $stubs = @()
        Get-ChildItem -Path $draftsDir -Recurse -Include *.yml,*.yaml -ErrorAction SilentlyContinue | ForEach-Object {
            $json = & yq eval -o=json '.' $_.FullName
            $stubs += ($json | & jq 'if type == "array" then . else [.] end')
        }
        if ($stubs.Count -gt 0) {
            $draftsJson = ($stubs -join ',') | ForEach-Object { "[$_]" } | & jq 'add | map(. + {status: "draft", path: ""})'
        }
    }
}

$filter = @'
def split_csv($s): if ($s | length) == 0 then [] else ($s | split(",") | map(. | ascii_downcase | gsub("^\\s+|\\s+$"; ""))) end;
($idx[0].rules + $drafts) as $all
| split_csv($tags_csv)     as $want_tags
| split_csv($domains_csv)  as $want_domains
| split_csv($statuses_csv) as $want_statuses
| split_csv($ids_csv)      as $want_ids
| $all
| map(
    . as $r
    | (($r.tags // []) | map(ascii_downcase)) as $rt
    | (($r.domain // "") | ascii_downcase)    as $rd
    | (($r.status // "active") | ascii_downcase) as $rs
    | (($r.statement // "") | ascii_downcase
        | gsub("[^a-z0-9 ]"; " ") | split(" ") | map(select(length >= 3))) as $sw
    | ([$sw, $rt] | add) as $bag
    | (if ($tokens | length) > 0
         then ([$tokens[] | select(. as $t | $bag | index($t)) ] | length) / ($tokens | length)
         else 0.0
       end) as $text_score
    | (if ($want_tags | length) > 0
         then ([$want_tags[] | select(. as $t | $rt | index($t))] | length) / ($want_tags | length)
         else 0.0
       end) as $tag_score
    | (if ($want_domains | length) > 0
         then (if ($want_domains | index($rd)) then 1.0 else 0.0 end)
         else 0.0
       end) as $domain_score
    | ($text_score * 0.6 + $tag_score * 0.3 + $domain_score * 0.1) as $score
    | $r + { score: $score, _rs: $rs, _rd: $rd, _rt: $rt })
| map(select(
    (($want_statuses | length) == 0 or ($want_statuses | index(._rs)))
    and (($want_domains | length) == 0 or ($want_domains | index(._rd)))
    and (($want_tags | length) == 0 or (any(._rt[]; . as $t | $want_tags | index($t))))
    and (($want_ids | length) == 0 or ($want_ids | index(.id | ascii_downcase)))))
| map(select(
    ($tokens | length) == 0 and ($want_tags | length) == 0 and ($want_domains | length) == 0
    or .score >= $min_score))
| sort_by(-.score)
| .[:$limit]
| map({id, statement, domain, tags, status, score: (.score | . * 1000 | floor) / 1000})
'@

& jq -n `
    --slurpfile idx $index `
    --argjson drafts $draftsJson `
    --argjson tokens $tokensJson `
    --arg tags_csv ($Tags ?? '') `
    --arg domains_csv ($Domain ?? '') `
    --arg statuses_csv $Status `
    --arg ids_csv ($Ids ?? '') `
    --argjson min_score $minScore `
    --argjson limit $Limit `
    $filter
