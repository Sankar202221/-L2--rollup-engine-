// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RollupTestBase.sol";

contract ExecutionTest is RollupTestBase {
    function test_calculateFee_respectsFixedGas() public {
        Rollup.L2Tx memory l2 = Rollup.L2Tx({
            from: alice,
            to: bob,
            value: 1 ether,
            gasLimit: rollup.GAS_PER_TX(),
            maxFeePerGas: 1 gwei,
            nonce: 0
        });

        uint256 fee = rollup.calculateFee(l2);
        assertEq(fee, rollup.GAS_PER_TX() * 1 gwei);
    }

    function test_executeTx_chargesGas() public {
        Rollup.L2Tx memory l2 = Rollup.L2Tx({
            from: alice,
            to: bob,
            value: 1 ether,
            gasLimit: rollup.GAS_PER_TX(),
            maxFeePerGas: 1 gwei,
            nonce: 0
        });

        Rollup.Account memory sender = Rollup.Account(10 ether, 1 ether, 0);
        Rollup.Account memory receiver = Rollup.Account(0, 0, 0);
        Rollup.Account memory seq = Rollup.Account(0, 0, 0);

        (Rollup.Account memory newSender,, Rollup.Account memory newSeq) = rollup.executeTx(l2, sender, receiver, seq);

        uint256 expectedFee = rollup.GAS_PER_TX() * 1 gwei;

        assertEq(newSender.gasBalance, sender.gasBalance - expectedFee);
        assertEq(newSeq.gasBalance, expectedFee);
        assertEq(newSender.nonce, 1);
        assertEq(newSender.balance, sender.balance - l2.value);
    }
}
