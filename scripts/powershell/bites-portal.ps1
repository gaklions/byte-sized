# bites-portal.ps1 — launch the byte-sized review portal (local web UI).
#
# Usage:
#   bites-portal.ps1 [-Port <N>] [-PortalHost <addr>] [-NoOpen]
#
# Wraps `python3 scripts/portal/bites-portal.py`. Python 3.10+ is required
# (prefers `python` on Windows, falls back to `python3`). Server is
# loopback-only; non-127.0.0.1 hosts are refused.

[CmdletBinding()]
param(
    [int]$Port,
    [string]$PortalHost,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$ExtRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$Py = Join-Path $ExtRoot 'scripts/portal/bites-portal.py'

$python = $null
foreach ($candidate in @('python', 'python3', 'py')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $python = $candidate; break }
}
if (-not $python) {
    throw "byte-sized portal: python (>= 3.10) is required. Install it and retry."
}

$args = @()
if ($PSBoundParameters.ContainsKey('Port'))       { $args += @('--port', "$Port") }
if ($PSBoundParameters.ContainsKey('PortalHost')) { $args += @('--host', $PortalHost) }
if ($NoOpen)                                       { $args += '--no-open' }

& $python $Py @args
