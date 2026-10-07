# Rehearsal on an anvil fork of Base Sepolia: the full CRE -> receiver -> real UMA OOv3 -> pool path, with the forwarder impersonated.
# Prereqs: `anvil --fork-url https://sepolia.base.org --chain-id 84532 --port 8546`, DeployV1Base.s.sol broadcast to it with UMA_OOV3 set,
# and the deployer address funded with `anvil_setBalance`. Nothing touches the real network.
param(
  [string]$Rpc = "http://127.0.0.1:8546",
  [Parameter(Mandatory)] [string]$Deployer,
  [Parameter(Mandatory)] [string]$Forwarder,
  [Parameter(Mandatory)] [string]$Bead,
  [Parameter(Mandatory)] [string]$Pool,
  [Parameter(Mandatory)] [string]$Registry,
  [Parameter(Mandatory)] [string]$Resolver,
  [Parameter(Mandatory)] [string]$Receiver,
  [string]$Oracle = "0x0F7fC5E6482f096380db6158f978167b57388deE",
  [string]$BondToken = "0x7E6d9618Ba8a87421609352d6e711958A97e2512",
  [string]$ChainSelector = "10344971235874465080"
)

$ErrorActionPreference = "Stop"
$env:Path += ";$env:USERPROFILE\.foundry\bin"

$a1 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
$a2 = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

function Send($from, $to, $sig, [string[]]$callArgs) {
  $out = cast send $to $sig @callArgs --from $from --unlocked --rpc-url $Rpc --json | ConvertFrom-Json
  if (-not $out.transactionHash -or ($out.status -ne "0x1" -and $out.status -ne 1 -and $out.status -ne "success")) { throw "tx failed: $sig" }
  $out
}
function Call($to, $sig, [string[]]$callArgs) { (cast call $to $sig @callArgs --rpc-url $Rpc).Split(" ")[0] }
function Warp($seconds) { cast rpc evm_increaseTime $seconds --rpc-url $Rpc | Out-Null; cast rpc evm_mine --rpc-url $Rpc | Out-Null }

$ether = [decimal]"1000000000000000000"
$thousand = "1000000000000000000000"
$cap = "100000000000000000000000"

Write-Host "0. Impersonate deployer (receiver owner) and the forwarder"
foreach ($acct in @($Deployer, $Forwarder)) {
  cast rpc anvil_impersonateAccount $acct --rpc-url $Rpc | Out-Null
  cast rpc anvil_setBalance $acct 0x56BC75E2D63100000 --rpc-url $Rpc | Out-Null
}

Write-Host "1. Create match #1, both sides stake 1000 BEAD"
Send $a1 $Bead "transfer(address,uint256)" @($Deployer, "2000000000000000000000") | Out-Null
$ts = [int64](cast block latest --field timestamp --rpc-url $Rpc)
Send $Deployer $Bead "approve(address,uint256)" @($Registry, $thousand) | Out-Null
Send $Deployer $Registry "createMatch(uint256,uint256,string,string,uint256,uint256)" @("1", ($ts + 600), "North Red", "North White", $cap, $thousand) | Out-Null
Send $a1 $Bead "approve(address,uint256)" @($Pool, $thousand) | Out-Null
Send $a1 $Pool "deposit(uint256,uint8,uint256)" @("1", "1", $thousand) | Out-Null
Send $a2 $Bead "approve(address,uint256)" @($Pool, $thousand) | Out-Null
Send $a2 $Pool "deposit(uint256,uint8,uint256)" @("1", "2", $thousand) | Out-Null

Write-Host "2. Kickoff, lock, give the resolver bond currency"
Warp 700
Send $Deployer $Pool "lockMatch(uint256)" @("1") | Out-Null
Send $a1 $BondToken "allocateTo(address,uint256)" @($Resolver, "1000000000000000000") | Out-Null

Write-Host "3. Owner requests the result; the workflow would answer this event"
$req = Send $Deployer $Receiver "requestMatchResult(uint256,string)" @("1", "1234")
$topic0 = cast keccak "MatchResolutionRequested(uint256,uint256,string)"
if (-not ($req.logs | Where-Object { $_.topics[0] -eq $topic0 })) { throw "MatchResolutionRequested was not emitted with the topic the workflow listens for" }

Write-Host "4. Mock DON: read the event, fetch fixture 1234 (a draw) from the mock API-Football, deliver the report via the forwarder"
$creDir = Join-Path $PSScriptRoot "..\..\cre\resolve-match"
$env:Path += ";$env:USERPROFILE\.node"
$env:MOCK_API_PORT = "8787"
$api = Start-Process node -ArgumentList "mock/api-football-server.ts" -WorkingDirectory $creDir -PassThru -WindowStyle Hidden
try {
  Start-Sleep -Seconds 2
  Push-Location $creDir
  node mock/don-relay.ts --rpc $Rpc --tx $req.transactionHash --receiver $Receiver --forwarder $Forwarder --api "http://127.0.0.1:8787" --key "mock-api-football-key" --chain-selector $ChainSelector
  if ($LASTEXITCODE -ne 0) { throw "mock DON relay failed" }
  Pop-Location
} finally { Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue }
if ((Call $Resolver "assertionOf(uint256)(bytes32)" @("1")) -match "^0x0+$") { throw "no UMA assertion was created" }
$report = cast abi-encode "f(uint64,uint256,uint256,uint8)" $ChainSelector 1 1 3

Write-Host "5. Replayed report and a non-forwarder caller must both fail"
$replayed = $true
try { Send $Forwarder $Receiver "onReport(bytes,bytes)" @("0x", $report) | Out-Null } catch { $replayed = $false }
if ($replayed) { throw "replayed report was accepted" }
$intruder = $true
try { Send $a2 $Receiver "onReport(bytes,bytes)" @("0x", $report) | Out-Null } catch { $intruder = $false }
if ($intruder) { throw "non-forwarder was accepted" }

Write-Host "6. Wait out the 30 minute UMA window, settle the assertion on OOv3, finalize, claim"
Warp 1801
$id = Call $Resolver "assertionOf(uint256)(bytes32)" @("1")
Send $Deployer $Oracle "settleAssertion(bytes32)" @($id) | Out-Null
Send $Deployer $Pool "finalizeSettlement(uint256)" @("1") | Out-Null
cast rpc anvil_mine 0x40 --rpc-url $Rpc | Out-Null
$b1 = [decimal](Call $Bead "balanceOf(address)(uint256)" @($a1))
$b2 = [decimal](Call $Bead "balanceOf(address)(uint256)" @($a2))
Send $a1 $Pool "claimSettlement(uint256,uint8)" @("1", "1") | Out-Null
Send $a2 $Pool "claimSettlement(uint256,uint8)" @("1", "2") | Out-Null
$g1 = ([decimal](Call $Bead "balanceOf(address)(uint256)" @($a1)) - $b1) / $ether
$g2 = ([decimal](Call $Bead "balanceOf(address)(uint256)" @($a2)) - $b2) / $ether
Write-Host "Red fan received $g1 BEAD, White fan received $g2 BEAD (expect 1490 each)"
if ($g1 -ne 1490 -or $g2 -ne 1490) { throw "unexpected payout" }
Write-Host "Fork rehearsal passed."
