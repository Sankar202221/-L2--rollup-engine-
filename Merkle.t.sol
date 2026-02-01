// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RollupTestBase.sol";

contract MerkleTest is RollupTestBase {
    function test_verifyAccountProof_valid() public {
        Rollup.Account memory acct = Rollup.Account({balance: 10 ether, gasBalance: 1 ether, nonce: 0});

        bytes32 leaf = rollup.hashAccount(alice, acct);
        bytes32 sibling = keccak256("dummy");
        bytes32 root = keccak256(abi.encodePacked(leaf, sibling));

        Rollup.MerkleStep[] memory proof = new Rollup.MerkleStep[](1);
        proof[0] = Rollup.MerkleStep({sibling: sibling, isLeft: false});

        bool ok = rollup.verifyAccountProof(alice, acct, proof, root);
        assertTrue(ok);
    }

    function test_verifyAccountProof_invalid() public {
        Rollup.Account memory acct = Rollup.Account({balance: 1, gasBalance: 1, nonce: 0});
        bytes32 leaf = rollup.hashAccount(alice, acct);
        bytes32 sibling = keccak256("other");
        bytes32 root = keccak256(abi.encodePacked(leaf, sibling));

        Rollup.MerkleStep[] memory proof = new Rollup.MerkleStep[](1);
        proof[0] = Rollup.MerkleStep({sibling: keccak256("wrong"), isLeft: false});

        bool ok = rollup.verifyAccountProof(alice, acct, proof, root);
        assertTrue(!ok);
    }

    function test_verifyAccountProof_wrongDirection_reverts() public {
        Rollup.Account memory acct = Rollup.Account({balance: 10 ether, gasBalance: 1 ether, nonce: 0});
        bytes32 leaf = rollup.hashAccount(alice, acct);
        bytes32 sibling = keccak256("dummy");

        // correct order: hash(leaf, sibling)
        bytes32 correctRoot = keccak256(abi.encodePacked(leaf, sibling));

        Rollup.MerkleStep[] memory proofWrongDir = new Rollup.MerkleStep[](1);
        proofWrongDir[0] = Rollup.MerkleStep({sibling: sibling, isLeft: true});

        bool ok = rollup.verifyAccountProof(alice, acct, proofWrongDir, correctRoot);
        assertTrue(!ok);
    }
}
