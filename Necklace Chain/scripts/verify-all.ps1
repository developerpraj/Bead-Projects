# One-command verification: contracts, CRE workflow, webapp. Run from anywhere: ./scripts/verify-all.ps1
# Native tools write warnings to stderr; failures are caught by the exit-code check in Step.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$env:Path += ";$env:USERPROFILE\.foundry\bin;$env:USERPROFILE\.node"
$env:NODE_OPTIONS = "--use-system-ca"

# Deploy/rehearsal variables left in the shell change what the deploy-script test sees.
foreach ($n in "PRIVATE_KEY","UMA_OOV3","BOND_AMOUNT","BOND_CURRENCY","CRE_CHAIN_SELECTOR","CRE_FORWARDER","CRE_WORKFLOW_ID",
  "CRE_WORKFLOW_OWNER","CRE_KEEPER","TRANSFER_RECEIVER_OWNERSHIP","COUNCIL_EXECUTOR","SMART_WALLET_FACTORY","ENTRY_POINT",
  "GENESIS_GAS_FLOAT","PAYMASTER_STAKE","MOCK_API_PORT") { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }

function Step($name, $dir, [scriptblock]$cmd) {
  Write-Host "== $name"
  Push-Location (Join-Path $root $dir)
  try { & $cmd; if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" } } finally { Pop-Location }
}

Step "forge test (unit, fuzz, invariants)" "contracts" { forge test }
Step "CRE workflow type-check" "cre/resolve-match" { npm run typecheck }
Step "CRE workflow tests" "cre/resolve-match" { npm test }
Step "CRE npm audit" "cre/resolve-match" { npm audit }
Step "webapp build" "webapp" { npm run build }
Step "webapp npm audit" "webapp" { npm audit }

Write-Host "All checks passed."
