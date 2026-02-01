// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Rollup.sol";
import "./GasToken.sol";

/// @title Bridge
/// @notice Locks L1 assets and gas tokens and allows withdrawals proven against the rollup state root.
contract Bridge {
    Rollup public immutable rollup;
    GasToken public immutable gasToken;

    uint256 public totalAssetLocked;
    uint256 public totalGasLocked;

    event DepositAsset(address indexed from, address indexed to, uint256 amount);
    event DepositGasToken(address indexed from, address indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);

    constructor(address _rollup, address _gasToken) {
        require(_rollup != address(0), "ROLLUP_ZERO");
        require(_gasToken != address(0), "GAS_ZERO");
        rollup = Rollup(_rollup);
        gasToken = GasToken(_gasToken);
        rollup.setBridge(address(this));
    }

    function depositAsset(address to) external payable {
        require(to != address(0), "ZERO_ADDR");
        require(msg.value > 0, "ZERO_VALUE");

        totalAssetLocked += msg.value;
        rollup.noteDeposit(to, msg.value);
        emit DepositAsset(msg.sender, to, msg.value);
    }

    function depositGasToken(address to, uint256 amount) external {
        require(to != address(0), "ZERO_ADDR");
        require(amount > 0, "ZERO_VALUE");

        bool ok = gasToken.transferFrom(msg.sender, address(this), amount);
        require(ok, "TRANSFER_FAIL");
        totalGasLocked += amount;
        emit DepositGasToken(msg.sender, to, amount);
    }

    function withdraw(
        address user,
        uint256 amount,
        Rollup.Account calldata acct,
        bytes32[] calldata proof
    ) external {
        require(user != address(0), "ZERO_ADDR");
        require(amount > 0, "ZERO_VALUE");

        uint256 latestBatch = rollup.batchCount();
        require(latestBatch > 0, "NO_BATCH");
        require(rollup.finalized(latestBatch - 1), "BATCH_NOT_FINAL");

        bytes32 leaf = rollup.hashAccount(user, acct);
        bool valid = rollup.verifyAccountProof(user, acct, proof, rollup.stateRoot());
        require(valid, "INVALID_PROOF");
        require(acct.balance >= amount, "INSUFFICIENT");
        require(totalAssetLocked >= amount, "LOCKED_FUNDS");

        totalAssetLocked -= amount;
        (bool sent,) = user.call{value: amount}("");
        require(sent, "WITHDRAW_FAIL");
        emit Withdraw(user, amount);
    }
}
