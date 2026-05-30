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
        $enriched = $fmJson | & jq --arg path $rel '{
            id: .id, statement: .statement, domain: .domain,
            tags: (.tags // []), status: (.status // "active"),
            source: (.source // {}), edges: (.edges // {}),
            path: $path
        }'
        $current = Get-Content -LiteralPath $tmp -Raw
        $current | & jq --argjson r $enriched '. + [$r]' | Set-Content -LiteralPath $tmp -Encoding utf8
    }

    $rules = Get-Content -LiteralPath $tmp -Raw
    $final = $rules | & jq '
        def edges_of($id; $key):
          [ .[] | select(.id != $id) | . as $r
              | (.edges[$key] // []) | map(select(. == $id))
              | length | select(. > 0) | $r.id ];
        map(. as $r
            | .edges.related_by_others       = edges_of($r.id; "relates_to")
            | .edges.depended_on_by          = edges_of($r.id; "depends_on")
            | .edges.superseded_by_others    = edges_of($r.id; "supersedes")
            | .edges.conflicts_with_others   = edges_of($r.id; "conflicts_with"))
    '

    $ts = Get-BsNowIso
    $final | & jq -n --arg ts $ts --argjson rules $final '
        { schema_version: "1.0", generated_at: $ts, rules: ($rules | sort_by(.id)) }
    ' | Set-Content -LiteralPath $index -Encoding utf8

    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $count = (Get-Content -LiteralPath $index -Raw | & jq '.rules | length').Trim()
    Write-Host "byte-sized: indexed $count rule(s) -> $index"
}
