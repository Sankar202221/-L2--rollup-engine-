// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RollupTestBase.sol";

contract BridgeTest is RollupTestBase {
    function test_depositAsset_locksFunds() public {
        uint256 beforeLocked = bridge.totalAssetLocked();
        bridge.depositAsset{value: 1 ether}(alice);
        assertEq(bridge.totalAssetLocked(), beforeLocked + 1 ether);
    }

    function test_withdraw_withoutProof_reverts() public {
        // ensure a batch exists and challenge window passed
        vm.prank(sequencer);
        rollup.submitBatch(rollup.stateRoot(), rollup.stateRoot(), keccak256("empty"));
        vm.warp(block.timestamp + rollup.CHALLENGE_PERIOD() + 1);
        rollup.finalizeBatch(0);

        Rollup.Account memory acct = Rollup.Account(10 ether, 0, 0);
        Rollup.MerkleStep[] memory proof;

        vm.expectRevert(bytes("INVALID_PROOF"));
        bridge.withdraw(alice, 1 ether, acct, proof);
    }

    function test_withdraw_beforeFinalization_reverts() public {
        vm.prank(sequencer);
        rollup.submitBatch(rollup.stateRoot(), rollup.stateRoot(), keccak256("empty"));

        Rollup.Account memory acct = Rollup.Account(10 ether, 0, 0);
        Rollup.MerkleStep[] memory proof;

        vm.expectRevert(bytes("BATCH_NOT_FINAL"));
        bridge.withdraw(alice, 1 ether, acct, proof);
    }
}
