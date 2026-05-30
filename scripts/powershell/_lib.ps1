# Shared helpers for byte-sized PowerShell scripts.
# Dot-source this file from every other script in this directory.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BsRepoRoot {
    $dir = (Get-Location).Path
    while ($dir -and (Split-Path $dir -Parent) -ne $dir) {
        if (Test-Path (Join-Path $dir '.specify')) { return $dir }
        $dir = Split-Path $dir -Parent
    }
    throw "byte-sized: error: not inside a spec-kit project (.specify/ not found)"
}

function Get-BsConfigPath {
    param([string]$Root)
    $candidates = @(
        (Join-Path $Root '.specify/extensions/byte-sized/byte-sized-config.yml'),
        (Join-Path $Root '.specify/extensions/byte-sized/config-template.yml')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw "byte-sized: error: no config file found under .specify/extensions/byte-sized/"
}

function Get-BsCfg {
    param([string]$Cfg, [string]$Path, [string]$Default = '')
    $val = & yq eval "$Path // `"`"" $Cfg 2>$null
    if (-not $val -or $val -eq 'null' -or $val -eq '') { return $Default }
    return $val.Trim()
}

function Get-BsRulesDir {
    param([string]$Root)
    $cfg = Get-BsConfigPath -Root $Root
    $rel = Get-BsCfg -Cfg $cfg -Path '.storage.rules_dir' -Default '.specify/rules'
    return (Join-Path $Root $rel)
}

function Get-BsFrontmatter {
    param([string]$File)
    $lines = Get-Content -LiteralPath $File
    $state = 0
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $lines) {
        if ($ln -match '^---\s*$') {
            $state++
            if ($state -ge 2) { break } else { continue }
        }
        if ($state -eq 1) { [void]$out.Add($ln) }
    }
    return ($out -join "`n")
}

function Get-BsFrontmatterJson {
    param([string]$File)
    $yaml = Get-BsFrontmatter -File $File
    return ($yaml | & yq eval -o=json -I=0 '.' -)
}

function Get-BsBody {
    param([string]$File)
    $lines = Get-Content -LiteralPath $File
    $state = 0
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $lines) {
        if ($ln -match '^---\s*$') { $state++; continue }
        if ($state -ge 2) { [void]$out.Add($ln) }
    }
    return ($out -join "`n")
}

function Invoke-BsWithLock {
    param([string]$LockPath, [scriptblock]$Action)
    $dir = Split-Path $LockPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($LockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        & $Action
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

function ConvertTo-BsSlug {
    param([string]$Text)
    $s = ($Text ?? '').ToLowerInvariant()
    $s = ($s -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $s) { return 'rule' }
    return $s
}

function Get-BsToday { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
function Get-BsNowIso { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Assert-BsTools {
    param([string[]]$Tools)
    $missing = @()
    foreach ($t in $Tools) {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { $missing += $t }
    }
    if ($missing.Count -gt 0) {
        throw "byte-sized: missing required tools: $($missing -join ', ')"
    }
}
