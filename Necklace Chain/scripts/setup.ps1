# Installs project dependencies on a new machine after Foundry, Node and the CRE CLI are installed (see requirements.txt).
# Native tools write warnings to stderr; failures are caught by the explicit exit-code checks below.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$env:Path += ";$env:USERPROFILE\.foundry\bin;$env:USERPROFILE\.node;$env:USERPROFILE\.cre\bin"
if (-not $env:NODE_OPTIONS) { $env:NODE_OPTIONS = "--use-system-ca" }

foreach ($tool in "forge", "node", "npm") {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found on PATH. Install it first (see requirements.txt)." }
}
if (-not (Get-Command cre -ErrorAction SilentlyContinue)) { Write-Warning "cre CLI not found: only needed for workflow simulate/deploy." }
if ([int]((node --version).TrimStart("v").Split(".")[0]) -lt 24) { throw "Node 24 or newer is required." }

$lib = Join-Path $root "contracts\lib"
$libs = @{ "forge-std" = "foundry-rs/forge-std@v1.17.0"; "openzeppelin-contracts" = "OpenZeppelin/openzeppelin-contracts@v5.7.0";
           "openzeppelin-contracts-upgradeable" = "OpenZeppelin/openzeppelin-contracts-upgradeable@v5.7.0" }
foreach ($name in $libs.Keys) {
  if (-not (Test-Path (Join-Path $lib $name))) {
    Write-Host "== forge install $name"
    Push-Location (Join-Path $root "contracts")
    try { forge install $libs[$name] --no-git; if ($LASTEXITCODE -ne 0) { throw "forge install $name failed" } } finally { Pop-Location }
  }
}

foreach ($dir in "webapp", "cre\resolve-match") {
  Write-Host "== npm ci ($dir)"
  Push-Location (Join-Path $root $dir)
  try { npm ci; if ($LASTEXITCODE -ne 0) { throw "npm ci failed in $dir" } } finally { Pop-Location }
}

# contracts/.env is NOT created here: Foundry auto-loads it, and the example values would change what the tests see. Create it only when deploying.
foreach ($pair in @(@("cre\.env.example", "cre\.env"), @("webapp\.env.example", "webapp\.env.local"))) {
  $src = Join-Path $root $pair[0]; $dst = Join-Path $root $pair[1]
  if ((Test-Path $src) -and -not (Test-Path $dst)) { Copy-Item $src $dst; Write-Host "created $($pair[1]) from the example: fill it in" }
}

Write-Host "Setup done. Verify with: ./scripts/verify-all.ps1"
