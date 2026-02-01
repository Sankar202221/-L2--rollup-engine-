// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RollupTestBase.sol";

contract FraudProofTest is RollupTestBase {
    Rollup.Account sender;
    Rollup.Account receiver;
    Rollup.Account seqAcct;

    bytes32 senderLeaf;
    bytes32 receiverLeaf;
    bytes32 seqLeaf;
    bytes32 pairLeaf;
    bytes32 preRoot;

    Rollup.MerkleStep[] senderProof;
    Rollup.MerkleStep[] receiverProof;
    Rollup.MerkleStep[] seqProof;

    function setUp() public override {
        gasToken = new GasToken(address(this));

        sender = Rollup.Account(10 ether, 1 ether, 0);
        receiver = Rollup.Account(0, 0, 0);
        seqAcct = Rollup.Account(0, 0, 0);

        senderLeaf = _hashAccount(alice, sender);
        receiverLeaf = _hashAccount(bob, receiver);
        seqLeaf = _hashAccount(sequencer, seqAcct);
        pairLeaf = _hashPair(senderLeaf, receiverLeaf);
        preRoot = _hashPair(pairLeaf, seqLeaf);

        rollup = new Rollup(sequencer, address(gasToken), preRoot);
        bridge = new Bridge(address(rollup), address(gasToken));

        senderProof = new Rollup.MerkleStep[](2);
        senderProof[0] = Rollup.MerkleStep({sibling: receiverLeaf, isLeft: false});
        senderProof[1] = Rollup.MerkleStep({sibling: seqLeaf, isLeft: false});

        receiverProof = new Rollup.MerkleStep[](2);
        receiverProof[0] = Rollup.MerkleStep({sibling: senderLeaf, isLeft: true});
        receiverProof[1] = Rollup.MerkleStep({sibling: seqLeaf, isLeft: false});

        seqProof = new Rollup.MerkleStep[](1);
        seqProof[0] = Rollup.MerkleStep({sibling: pairLeaf, isLeft: true});

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        gasToken.transferOwnership(address(bridge));
    }

    function test_fraudProof_detectsWrongPostRoot() public {
        Rollup.L2Tx memory l2 = Rollup.L2Tx({
            from: alice,
            to: bob,
            value: 1 ether,
            gasLimit: rollup.GAS_PER_TX(),
            maxFeePerGas: 1 gwei,
            nonce: 0
        });

        // Sequencer submits incorrect post root
        vm.prank(sequencer);
        rollup.submitBatch(preRoot, bytes32(uint256(999)), keccak256(abi.encode(l2)));

        rollup.proveInvalidTx(
            0,
            l2,
            sender,
            receiver,
            seqAcct,
            senderProof,
            receiverProof,
            seqProof
        );

        assertTrue(rollup.batchReverted(0));
        assertEq(rollup.stateRoot(), preRoot);
    }

    function _hashAccount(address user, Rollup.Account memory acct) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, acct.balance, acct.gasBalance, acct.nonce));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
