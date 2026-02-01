// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/Rollup.sol";
import "../src/GasToken.sol";
import "../src/Bridge.sol";
import "../lib/forge-std/src/Test.sol";

abstract contract RollupTestBase is Test {
    Rollup rollup;
    GasToken gasToken;
    Bridge bridge;

    address sequencer = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public virtual {
        gasToken = new GasToken(address(this));
        rollup = new Rollup(sequencer, address(gasToken), bytes32(0));
        bridge = new Bridge(address(rollup), address(gasToken));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        gasToken.transferOwnership(address(bridge));
    }
}
