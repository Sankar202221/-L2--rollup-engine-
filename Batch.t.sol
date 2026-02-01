// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RollupTestBase.sol";

contract BatchTest is RollupTestBase {
    function test_submitBatch_invalidPreRoot_reverts() public {
        vm.prank(sequencer);
        vm.expectRevert(bytes("INVALID_PRE_ROOT"));
        rollup.submitBatch(bytes32(uint256(123)), bytes32(uint256(456)), keccak256("txs"));
    }

    function test_submitBatch_updatesState() public {
        bytes32 preRoot = rollup.stateRoot();
        bytes32 postRoot = keccak256("next");

        vm.prank(sequencer);
        rollup.submitBatch(preRoot, postRoot, keccak256("txs"));

        assertEq(rollup.stateRoot(), postRoot);
        (bytes32 storedPre, bytes32 storedPost,,) = rollup.batches(0);
        assertEq(storedPre, preRoot);
        assertEq(storedPost, postRoot);
    }
}
