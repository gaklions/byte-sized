# rules-index.ps1 — rebuild .specify/rules/index.json from rule markdown files.

[CmdletBinding()]
param()

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq','yq')

$root = Get-BsRepoRoot
$rulesDir = Get-BsRulesDir -Root $root
$index = Join-Path $rulesDir 'index.json'

if (-not (Test-Path $rulesDir)) { New-Item -ItemType Directory -Path $rulesDir | Out-Null }

Invoke-BsWithLock -LockPath (Join-Path $rulesDir '.index.lock') -Action {
    $tmp = New-TemporaryFile
    '[]' | Set-Content -LiteralPath $tmp -Encoding utf8

    $searchRoots = @(
        (Join-Path $rulesDir 'domains'),
        (Join-Path $rulesDir '_archive')
    ) | Where-Object { Test-Path $_ }

    $files = @()
    if ($searchRoots.Count -gt 0) {
        $files = Get-ChildItem -Path $searchRoots -Recurse -Filter *.md -ErrorAction SilentlyContinue
    }

    foreach ($f in $files) {
        $fmJson = Get-BsFrontmatterJson -File $f.FullName
        if (-not $fmJson -or $fmJson -eq 'null') {
            Write-Warning "byte-sized: skipping $($f.FullName) (no frontmatter)"
            continue
        }
        $rel = ($f.FullName.Substring($root.Length + 1)).Replace('\','/')
        $enrichFilter = '{ id: .id, statement: .statement, domain: .domain, tags: (.tags // []), status: (.status // "active"), source: (.source // {}), edges: (.edges // {}), path: $path }'
        $enriched = $fmJson | & jq -c --arg path $rel $enrichFilter
        $current = Get-Content -LiteralPath $tmp -Raw
        $current | & jq -c --argjson r $enriched '. + [$r]' | Set-Content -LiteralPath $tmp -Encoding utf8
    }

    $rules = Get-Content -LiteralPath $tmp -Raw
    $inverseFilter = '. as $all | map(. as $r | .edges.related_by_others = [ $all[] | select(.id != $r.id) | select((.edges.relates_to // []) | index($r.id)) | .id ] | .edges.depended_on_by = [ $all[] | select(.id != $r.id) | select((.edges.depends_on // []) | index($r.id)) | .id ] | .edges.superseded_by_others = [ $all[] | select(.id != $r.id) | select((.edges.supersedes // []) | index($r.id)) | .id ] | .edges.conflicts_with_others = [ $all[] | select(.id != $r.id) | select((.edges.conflicts_with // []) | index($r.id)) | .id ])'
    $final = $rules | & jq -c $inverseFilter

    $ts = Get-BsNowIso
    $wrapFilter = '{ schema_version: "1.0", generated_at: $ts, rules: ($rules | sort_by(.id)) }'
    $final | & jq -n --arg ts $ts --argjson rules $final $wrapFilter | Set-Content -LiteralPath $index -Encoding utf8

    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $count = (Get-Content -LiteralPath $index -Raw | & jq '.rules | length').Trim()
    # Write status to stderr so captured stdout (used by callers like
    # rules-promote) stays clean. Write-Host bypasses `| Out-Null`.
    [Console]::Error.WriteLine("byte-sized: indexed $count rule(s) -> $index")
}
