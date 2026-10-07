// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BeadToken} from "../src/BeadToken.sol";
import {TreasuryForwarder} from "../src/TreasuryForwarder.sol";
import {FactionToken} from "../src/FactionToken.sol";
import {EkecheiriaPool} from "../src/EkecheiriaPool.sol";
import {MatchRegistry} from "../src/MatchRegistry.sol";
import {CosmicNecklace} from "../src/CosmicNecklace.sol";
import {TierStaking} from "../src/TierStaking.sol";
import {Faction} from "../src/interfaces/PoolTypes.sol";

abstract contract NecklaceBase is Test {
    address internal constant PUBLIC_GOODS = address(0xBEEF);

    address internal council = makeAddr("council");
    address internal oracle = makeAddr("oracle");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    BeadToken public bead;
    TreasuryForwarder internal forwarder;
    EkecheiriaPool public pool;
    FactionToken internal factionImpl;
    MatchRegistry internal registry;
    CosmicNecklace public necklace;
    TierStaking internal staking;

    uint256 public constant MATCH_ID = 1;
    uint256 internal constant CAP = 100_000 ether;
    uint256 internal constant REWARD = 1_000 ether;
    uint256 public kickoff;

    address public homeToken;
    address public awayToken;

    function setUp() public virtual {
        address[5] memory recipients = [address(this), makeAddr("treasury"), makeAddr("team"), makeAddr("liq"), makeAddr("seed")];
        bead = new BeadToken(address(this), recipients);
        forwarder = new TreasuryForwarder(address(bead), PUBLIC_GOODS);
        bead.setTreasuryForwarder(address(forwarder));

        pool = new EkecheiriaPool(address(bead), address(forwarder), council);
        factionImpl = new FactionToken();
        registry = new MatchRegistry(address(pool), address(bead), address(factionImpl), council);
        necklace = new CosmicNecklace(address(registry), address(pool));
        staking = new TierStaking(address(bead), address(forwarder));
        pool.wire(address(registry), address(necklace), _makeOracle());

        bead.setFeeExempt(address(pool), true);
        bead.setFeeExempt(address(staking), true);
        bead.setFeeExempt(address(this), true);

        bead.transfer(alice, 100_000 ether);
        bead.transfer(bob, 100_000 ether);
        bead.transfer(carol, 100_000 ether);
        bead.setFeeExempt(address(this), false);

        kickoff = block.timestamp + 1 days;
        bead.approve(address(registry), type(uint256).max);
        (homeToken, awayToken) = registry.createMatch(MATCH_ID, kickoff, "North Red", "North White", CAP, REWARD);
    }

    function _makeOracle() internal virtual returns (address) {
        return oracle;
    }

    function _deposit(address user, Faction side, uint256 amount) internal {
        vm.startPrank(user);
        bead.approve(address(pool), amount);
        pool.deposit(MATCH_ID, side, amount);
        vm.stopPrank();
    }
}
