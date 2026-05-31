# portal-smoke.ps1 — Windows mirror of portal-smoke.sh.
# Boots bites-portal.py against a sandbox, curls every public route, asserts 200.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SelftestDir = Split-Path $PSCommandPath -Parent
$ExtRoot     = Resolve-Path (Join-Path $SelftestDir '../..')
$Portal      = Join-Path $ExtRoot 'scripts/portal/bites-portal.py'

$python = $null
foreach ($candidate in @('python', 'python3', 'py')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $python = $candidate; break }
}
if (-not $python) {
    Write-Host "portal-smoke: python not on PATH; skipping."
    exit 0
}

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("bs-portal-smoke-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$extDir = Join-Path $sandbox '.specify/extensions/byte-sized'
New-Item -ItemType Directory -Path $extDir | Out-Null
Copy-Item (Join-Path $ExtRoot 'config-template.yml') (Join-Path $extDir 'config-template.yml')
New-Item -ItemType Directory -Path (Join-Path $sandbox '.specify/bites/domains') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $sandbox '.specify/bites/_drafts') -Force | Out-Null
'{"schema_version":"1.0","generated_at":"2026-05-30T00:00:00Z","bites":[]}' |
    Set-Content -LiteralPath (Join-Path $sandbox '.specify/bites/index.json') -Encoding utf8

$port = if ($env:BS_PORTAL_PORT) { [int]$env:BS_PORTAL_PORT } else { 7821 }
$outLog = Join-Path $sandbox 'portal.out.log'
$errLog = Join-Path $sandbox 'portal.err.log'

Push-Location $sandbox
$proc = Start-Process -FilePath $python `
    -ArgumentList @("`"$Portal`"", '--port', "$port", '--no-open') `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
    -PassThru -WindowStyle Hidden
Pop-Location

try {
    # Wait until /api/config responds (5 s budget).
    $ready = $false
    for ($i = 0; $i -lt 25; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/config" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $ready) {
        Write-Host '--- stdout ---'
        if (Test-Path $outLog) { Get-Content $outLog -Raw | Write-Host }
        Write-Host '--- stderr ---'
        if (Test-Path $errLog) { Get-Content $errLog -Raw | Write-Host }
        throw "portal-smoke: server never became ready on port $port"
    }

    function Assert-Route([string]$route) {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port$route" -UseBasicParsing -TimeoutSec 15
        if ($r.StatusCode -ne 200) { throw "portal-smoke: FAIL $route -> $($r.StatusCode)" }
        Write-Host "  PASS $route -> 200"
    }

    Write-Host "==> portal smoke @ http://127.0.0.1:$port"
    @('/', '/assets/styles.css', '/assets/app.js', '/assets/drafts.js',
      '/assets/graph.js', '/assets/detail.js',
      '/api/config', '/api/index', '/api/drafts'
    ) | ForEach-Object { Assert-Route $_ }

    Write-Host "==> loopback enforcement"
    $rc = (Start-Process -FilePath $python `
        -ArgumentList @("`"$Portal`"", '--host', '0.0.0.0', '--port', "$port", '--no-open', '--repo', "`"$sandbox`"") `
        -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc -eq 0) { throw "portal-smoke: FAIL non-loopback host was accepted" }
    Write-Host "  PASS non-loopback host refused (exit $rc)"

    Write-Host "==> portal-smoke passed"
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
