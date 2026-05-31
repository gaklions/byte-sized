# bites-baseline.ps1 — discover candidate source files for a brownfield baseline pass.
#
# Mirrors bites-baseline.sh. See its header for full flag docs.

[CmdletBinding()]
param(
    [ValidateSet('discover','stage')]
    [string]$Mode = 'discover',
    [string]$Include,
    [string]$Exclude,
    [string]$Scope = 'docs+specs',
    [int]$MaxFilesPerBatch = 12,
    [int]$MaxBytesPerBatch = 65536,
    [string]$Batch
)

. "$PSScriptRoot/_lib.ps1"
Assert-BsTools -Tools @('jq')

$root = Get-BsRepoRoot
Push-Location $root
try {
    function Get-DefaultIncludes([string]$s) {
        switch ($s) {
            'docs'       { return 'README*,docs/**,**/CONTRIBUTING.md,**/*.adr.md,**/ADR-*.md,**/ARCHITECTURE.md' }
            'specs'      { return 'specs/**/*.md,.specify/memory/**/*.md' }
            'docs+specs' { return 'README*,docs/**,specs/**/*.md,.specify/memory/**/*.md,**/CONTRIBUTING.md,**/*.adr.md,**/ADR-*.md,**/ARCHITECTURE.md' }
            'code'       { return 'src/**,lib/**,app/**,packages/**' }
            'all'        { return 'README*,docs/**,specs/**/*.md,.specify/memory/**/*.md,**/CONTRIBUTING.md,**/*.adr.md,**/ADR-*.md,**/ARCHITECTURE.md,src/**,lib/**,app/**,packages/**' }
            default      { return $s }
        }
    }

    $defaultExcludes = 'node_modules/**,.git/**,.venv/**,venv/**,dist/**,build/**,out/**,target/**,coverage/**,.specify/bites/**,.specify/extensions/**,_drafts/**,_archive/**'
    $includesCsv = if ($Include) { $Include } else { Get-DefaultIncludes -s $Scope }
    $excludesCsv = if ($Exclude) { "$defaultExcludes,$Exclude" } else { $defaultExcludes }

    if ($Mode -eq 'stage') {
        if (-not $Batch) { throw "bites-baseline: -Stage requires -Batch <label>" }
        $cfg = Get-BsConfigPath -Root $root
        $bitesDir = Get-BsBitesDir -Root $root
        $draftsRel = Get-BsCfg -Cfg $cfg -Path '.extraction.drafts_dir' -Default '_drafts'
        $draftsDir = Join-Path $bitesDir $draftsRel
        if (-not (Test-Path $draftsDir)) { New-Item -ItemType Directory -Path $draftsDir | Out-Null }
        $ts = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
        $out = Join-Path $draftsDir "baseline-$Batch-$ts.yml"
        $extract = Join-Path $PSScriptRoot 'bites-extract.ps1'
        # PowerShell pipes objects, not bytes, between cmdlets/scripts, so a child
        # .ps1 invoked via `& $script` never sees stdin. Spawn a child pwsh process
        # (a native executable from PS's perspective) so the piped string is written
        # to its real stdin and bites-extract.ps1 can ReadToEnd() it.
        $stdin = [Console]::In.ReadToEnd()
        $stdin | & pwsh -NoProfile -File $extract -SourceFile "baseline:$Batch" -Feature "baseline-$Batch" -Out $out
        return
    }

    # ----- Discover mode -----
    $incArr = $includesCsv -split ','
    $excArr = $excludesCsv -split ','

    function Test-GlobMatch {
        param([string]$Path, [string]$Pattern)
        # Convert glob pattern to regex: ** -> .*, * -> [^/]*, ? -> .
        $rx = [regex]::Escape($Pattern) `
              -replace '\\\*\\\*', '.*' `
              -replace '\\\*', '[^/]*' `
              -replace '\\\?', '.'
        return ($Path -match ('^' + $rx + '$'))
    }

    $files = Get-ChildItem -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length + 1).Replace('\','/')
        $excluded = $false
        foreach ($p in $excArr) { if (Test-GlobMatch -Path $rel -Pattern $p) { $excluded = $true; break } }
        if ($excluded) { return }
        $included = $false
        foreach ($p in $incArr) { if (Test-GlobMatch -Path $rel -Pattern $p) { $included = $true; break } }
        if (-not $included) { return }
        [pscustomobject]@{ path = $rel; bytes = $_.Length }
    } | Where-Object { $_ } | Sort-Object path

    $batches = @()
    $curFiles = @()
    $curBytes = 0
    foreach ($f in $files) {
        if (($curFiles.Count -ge $MaxFilesPerBatch) -or (($curBytes + $f.bytes) -gt $MaxBytesPerBatch -and $curFiles.Count -gt 0)) {
            $batches += ,@{ files = $curFiles; bytes = $curBytes }
            $curFiles = @()
            $curBytes = 0
        }
        $curFiles += $f
        $curBytes += $f.bytes
    }
    if ($curFiles.Count -gt 0) { $batches += ,@{ files = $curFiles; bytes = $curBytes } }

    $batchObjs = for ($i = 0; $i -lt $batches.Count; $i++) {
        [pscustomobject]@{
            id          = ('b{0:D2}' -f ($i + 1))
            file_count  = $batches[$i].files.Count
            total_bytes = $batches[$i].bytes
            files       = @($batches[$i].files | ForEach-Object { $_.path })
        }
    }

    [pscustomobject]@{
        scope    = $Scope
        includes = $incArr
        excludes = $excArr
        totals   = @{
            files   = $files.Count
            bytes   = ($files | Measure-Object -Property bytes -Sum).Sum
            batches = $batchObjs.Count
        }
        batches  = @($batchObjs)
    } | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
