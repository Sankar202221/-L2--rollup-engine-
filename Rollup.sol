// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GasToken.sol";

contract Rollup {
    struct MerkleStep {
        bytes32 sibling;
        bool isLeft;
    }

    struct Account {
        uint256 balance;
        uint256 gasBalance;
        uint256 nonce;
    }

    struct L2Tx {
        address from;
        address to;
        uint256 value;
        uint256 gasLimit;
        uint256 maxFeePerGas;
        uint256 nonce;
    }

    struct Batch {
        bytes32 preStateRoot;
        bytes32 postStateRoot;
        bytes32 txsHash;
        uint256 timestamp;
    }

    bytes32 public stateRoot;
    uint256 public batchCount;
    mapping(uint256 => Batch) public batches;
    mapping(uint256 => bool) public batchReverted;
    mapping(uint256 => bool) public finalized;

    address public sequencer;
    GasToken public immutable gasToken;
    address public bridge;

    // Simplified constant gas model for demonstrative rollup
    uint256 public constant GAS_PER_TX = 21_000;
    uint256 public constant CHALLENGE_PERIOD = 7 days;

    mapping(address => uint256) public pendingDeposits;
    uint256 public pendingDepositsTotal;

    event BatchSubmitted(uint256 indexed id, bytes32 preRoot, bytes32 postRoot, bytes32 txsHash);
    event BatchRevert(uint256 indexed id, bytes32 restoredRoot);
    event BatchFinalized(uint256 indexed id);
    event DepositNoted(address indexed user, uint256 amount);
    event DepositConsumed(address indexed user, uint256 amount);

    constructor(address _sequencer, address _gasToken, bytes32 _genesisRoot) {
        require(_sequencer != address(0), "SEQ_ZERO");
        require(_gasToken != address(0), "GASTOKEN_ZERO");
        sequencer = _sequencer;
        gasToken = GasToken(_gasToken);
        stateRoot = _genesisRoot;
    }

    /*//////////////////////////////////////////////////////////////
                                MERKLE
    //////////////////////////////////////////////////////////////*/

    function hashAccount(address user, Account memory acct) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, acct.balance, acct.gasBalance, acct.nonce));
    }

    function verifyAccountProof(
        address user,
        Account memory acct,
        MerkleStep[] calldata proof,
        bytes32 root
    ) public pure returns (bool) {
        bytes32 computed = hashAccount(user, acct);
        uint256 len = proof.length;
        for (uint256 i; i < len; ) {
            computed = _hashPair(computed, proof[i].sibling, proof[i].isLeft);
            unchecked {
                ++i;
            }
        }
        return computed == root;
    }

    function computeNewRoot(
        bytes32 oldRoot,
        bytes32 oldLeaf,
        bytes32 newLeaf,
        MerkleStep[] calldata proof
    ) public pure returns (bytes32) {
        bytes32 computedOld = oldLeaf;
        uint256 len = proof.length;
        for (uint256 i; i < len; ) {
            computedOld = _hashPair(computedOld, proof[i].sibling, proof[i].isLeft);
            unchecked {
                ++i;
            }
        }
        require(computedOld == oldRoot, "PROOF_MISMATCH");

        bytes32 computedNew = newLeaf;
        for (uint256 i; i < len; ) {
            computedNew = _hashPair(computedNew, proof[i].sibling, proof[i].isLeft);
            unchecked {
                ++i;
            }
        }
        return computedNew;
    }

    /*//////////////////////////////////////////////////////////////
                              BATCHING
    //////////////////////////////////////////////////////////////*/

    struct DepositDelta {
        address user;
        uint256 amount;
    }

    function submitBatch(bytes32 preRoot, bytes32 postRoot, bytes32 txsHash) external {
        require(msg.sender == sequencer, "NOT_SEQUENCER");
        require(preRoot == stateRoot, "INVALID_PRE_ROOT");
        require(pendingDepositsTotal == 0, "PENDING_DEPOSITS");

        batches[batchCount] = Batch(preRoot, postRoot, txsHash, block.timestamp);
        stateRoot = postRoot;
        emit BatchSubmitted(batchCount, preRoot, postRoot, txsHash);
        unchecked {
            ++batchCount;
        }
    }

    function setBridge(address _bridge) external {
        require(_bridge != address(0), "BRIDGE_ZERO");
        require(bridge == address(0), "BRIDGE_SET");
        bridge = _bridge;
    }

    function noteDeposit(address user, uint256 amount) external {
        require(msg.sender == bridge, "NOT_BRIDGE");
        pendingDeposits[user] += amount;
        pendingDepositsTotal += amount;
        emit DepositNoted(user, amount);
    }

    function consumeDeposits(DepositDelta[] calldata deltas) external {
        require(msg.sender == sequencer, "NOT_SEQUENCER");
        uint256 len = deltas.length;
        for (uint256 i; i < len; ) {
            address user = deltas[i].user;
            uint256 amount = deltas[i].amount;
            require(pendingDeposits[user] >= amount, "DEPOSIT_MISSING");
            pendingDeposits[user] -= amount;
            pendingDepositsTotal -= amount;
            emit DepositConsumed(user, amount);
            unchecked {
                ++i;
            }
        }
    }

    function finalizeBatch(uint256 batchId) external {
        require(batchId < batchCount, "BATCH_OOB");
        require(!batchReverted[batchId], "REVERTED");
        require(!finalized[batchId], "FINALIZED");
        Batch memory b = batches[batchId];
        require(block.timestamp >= b.timestamp + CHALLENGE_PERIOD, "CHALLENGE");
        finalized[batchId] = true;
        emit BatchFinalized(batchId);
    }

    /*//////////////////////////////////////////////////////////////
                              EXECUTION
    //////////////////////////////////////////////////////////////*/

    function calculateFee(L2Tx memory tx_) public pure returns (uint256) {
        require(tx_.gasLimit == GAS_PER_TX, "GAS_LIMIT");
        return GAS_PER_TX * tx_.maxFeePerGas;
    }

    function executeTx(
        L2Tx memory tx_,
        Account memory sender,
        Account memory receiver,
        Account memory sequencerAcct
    )
        public
        pure
        returns (Account memory newSender, Account memory newReceiver, Account memory newSequencer)
    {
        require(tx_.from != address(0) && tx_.to != address(0), "ZERO_ADDR");
        require(sender.nonce == tx_.nonce, "NONCE");
        require(tx_.gasLimit == GAS_PER_TX, "GAS_LIMIT");

        uint256 fee = calculateFee(tx_);
        require(sender.gasBalance >= fee, "GAS_FUNDS");
        require(sender.balance >= tx_.value, "INSUFFICIENT_FUNDS");

        newSender = sender;
        newReceiver = receiver;
        newSequencer = sequencerAcct;

        newSender.balance -= tx_.value;
        newReceiver.balance += tx_.value;

        newSender.gasBalance -= fee;
        newSequencer.gasBalance += fee;

        newSender.nonce += 1;
    }

    /*//////////////////////////////////////////////////////////////
                             FRAUD PROOFS
    //////////////////////////////////////////////////////////////*/

    function proveInvalidTx(
        uint256 batchId,
        L2Tx calldata tx_,
        Account calldata sender,
        Account calldata receiver,
        Account calldata sequencerAcct,
        MerkleStep[] calldata senderProof,
        MerkleStep[] calldata receiverProof,
        MerkleStep[] calldata sequencerProof
    ) external {
        require(batchId < batchCount, "BATCH_OOB");
        require(!batchReverted[batchId], "ALREADY_REVERTED");
        require(!finalized[batchId], "BATCH_FINALIZED");

        Batch memory batch = batches[batchId];

        // validate pre-state proofs
        require(
            verifyAccountProof(tx_.from, sender, senderProof, batch.preStateRoot)
                && verifyAccountProof(tx_.to, receiver, receiverProof, batch.preStateRoot)
                && verifyAccountProof(sequencer, sequencerAcct, sequencerProof, batch.preStateRoot),
            "INVALID_PROOF"
        );

        (Account memory newSender, Account memory newReceiver, Account memory newSequencer) =
            executeTx(tx_, sender, receiver, sequencerAcct);

        bytes32 senderLeaf = hashAccount(tx_.from, sender);
        bytes32 newSenderLeaf = hashAccount(tx_.from, newSender);
        bytes32 receiverLeaf = hashAccount(tx_.to, receiver);
        bytes32 newReceiverLeaf = hashAccount(tx_.to, newReceiver);
        bytes32 seqLeaf = hashAccount(sequencer, sequencerAcct);
        bytes32 newSeqLeaf = hashAccount(sequencer, newSequencer);

        bytes32 rootAfterSender = computeNewRoot(batch.preStateRoot, senderLeaf, newSenderLeaf, senderProof);
        bytes32 rootAfterReceiver = computeNewRoot(rootAfterSender, receiverLeaf, newReceiverLeaf, receiverProof);
        bytes32 finalRoot = computeNewRoot(rootAfterReceiver, seqLeaf, newSeqLeaf, sequencerProof);

        require(finalRoot != batch.postStateRoot, "NO_FRAUD");

        batchReverted[batchId] = true;
        stateRoot = batch.preStateRoot;
        emit BatchRevert(batchId, batch.preStateRoot);
    }

    function _hashPair(bytes32 a, bytes32 b, bool isLeft) internal pure returns (bytes32) {
        return isLeft ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
