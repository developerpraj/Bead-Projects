# Local end-to-end rehearsal against anvil: create match, stake both sides, settle through the oracle, claim.
# Prereqs: `anvil` running, and `forge script script/DeployV1Base.s.sol --rpc-url $Rpc --broadcast` already executed
# Uses anvil's unlocked dev accounts, so no private keys are involved.
param(
  [string]$Rpc = "http://127.0.0.1:8545",
  [string]$Bead = "0x5FbDB2315678afecb367f032d93F642f64180aa3",
  [string]$Pool = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
  [string]$Registry = "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707"
)

$ErrorActionPreference = "Stop"
$env:Path += ";$env:USERPROFILE\.foundry\bin"

# anvil accounts 0 (deployer, oracle), 1 (ecosystem wallet, Red fan), 2 (treasury wallet, White fan)
$k0 = $a0 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
$k1 = $a1 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
$k2 = $a2 = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

function Send($from, $to, $sig, [string[]]$callArgs) {
  $out = cast send $to $sig @callArgs --from $from --unlocked --rpc-url $Rpc --json | ConvertFrom-Json
  if (-not $out.transactionHash -or ($out.status -ne "0x1" -and $out.status -ne 1 -and $out.status -ne "success")) { throw "tx failed: $sig" }
}
function Call($to, $sig, [string[]]$callArgs) { (cast call $to $sig @callArgs --rpc-url $Rpc).Split(" ")[0] }
function Warp($seconds) { cast rpc evm_increaseTime $seconds --rpc-url $Rpc | Out-Null; cast rpc evm_mine --rpc-url $Rpc | Out-Null }

$ether = "1000000000000000000"
$thousand = "1000000000000000000000"
$cap = "100000000000000000000000"

Write-Host "1. Fund deployer with the reward pool from the ecosystem wallet"
Send $k1 $Bead "transfer(address,uint256)" @($a0, "2000000000000000000000")

Write-Host "2. Create match #1 (kickoff in 10 minutes), funding the pool atomically"
$ts = [int64](cast block latest --field timestamp --rpc-url $Rpc)
Send $k0 $Bead "approve(address,uint256)" @($Registry, $thousand)
Send $k0 $Registry "createMatch(uint256,uint256,string,string,uint256,uint256)" @("1", ($ts + 600), "North Red", "North White", $cap, $thousand)

Write-Host "3. Red fan and White fan each stake 1000 BEAD"
Send $k1 $Bead "approve(address,uint256)" @($Pool, $thousand)
Send $k1 $Pool "deposit(uint256,uint8,uint256)" @("1", "1", $thousand)
Send $k2 $Bead "approve(address,uint256)" @($Pool, $thousand)
Send $k2 $Pool "deposit(uint256,uint8,uint256)" @("1", "2", $thousand)

Write-Host "4. Kickoff, lock, oracle reports a draw, wait out the 30 minute challenge window, finalize"
Warp 700
Send $k0 $Pool "lockMatch(uint256)" @("1")
Send $k0 $Pool "reportOutcomeProvisional(uint256,uint8)" @("1", "3")
Warp 1801
Send $k0 $Pool "finalizeSettlement(uint256)" @("1")

Write-Host "5. Pass the 50 block hold and claim"
cast rpc anvil_mine 0x40 --rpc-url $Rpc | Out-Null
$before1 = Call $Bead "balanceOf(address)(uint256)" @($a1)
$before2 = Call $Bead "balanceOf(address)(uint256)" @($a2)
Send $k1 $Pool "claimSettlement(uint256,uint8)" @("1", "1")
Send $k2 $Pool "claimSettlement(uint256,uint8)" @("1", "2")
$after1 = Call $Bead "balanceOf(address)(uint256)" @($a1)
$after2 = Call $Bead "balanceOf(address)(uint256)" @($a2)

$gain1 = [decimal]$after1 - [decimal]$before1
$gain2 = [decimal]$after2 - [decimal]$before2
Write-Host "Red fan received  $($gain1 / [decimal]$ether) BEAD (expect 990 principal + 500 truce bonus = 1490)"
Write-Host "White fan received $($gain2 / [decimal]$ether) BEAD (expect 1490)"
if ($gain1 -ne 1490 * [decimal]$ether -or $gain2 -ne 1490 * [decimal]$ether) { throw "unexpected payout" }
Write-Host "Rehearsal passed."
