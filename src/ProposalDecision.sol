// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IEntropyConsumer } from "node_modules/@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import { IEntropy } from "node_modules/@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { Pseudorandom } from "./lib/Pseudorandom.sol";

contract ProposalDecision is IEntropyConsumer, AccessControlEnumerable {
    error CallbackNotImplemented();
    error InsufficientFeeForRandomness();
    error NotEnoughFees();
    error NoEligibleMember(bytes32 role);
    error TaskNotFound(uint64 sequenceNumber);

    struct Task {
        uint64 sequenceNumber;
        bytes32 eligibleRoleId;
        address assignedTo;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IEntropy public entropy;
    mapping(uint256 => Task) private _tasks;
    mapping(uint64 => uint256) private _sequenceNumberToTaskId;

    event TaskAssigned(
        uint256 taskId,
        bytes32 eligibleRoleId,
        address assignee
    );
    event TaskCreated(uint256 taskId, uint64 sequenceNumber);

    constructor(address _entropy, address admin) {
        _grantRole(ADMIN_ROLE, admin);
        entropy = IEntropy(_entropy);
    }

    function assignTask(
        uint256 taskId,
        bytes32 eligibleRoleId,
        bytes32 random
    ) external payable {
        address provider = entropy.getDefaultProvider();
        uint256 fee = entropy.getFee(provider);
        if (msg.value < fee) revert NotEnoughFees();
        if (getRoleMemberCount(eligibleRoleId) > 0) revert NoEligibleMember(eligibleRoleId);
        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(provider, random);

        _tasks[taskId] = Task({
            eligibleRoleId: eligibleRoleId,
            sequenceNumber: sequenceNumber,
            assignedTo: address(0)
        });

        _sequenceNumberToTaskId[sequenceNumber] = taskId;
        emit TaskCreated(taskId, sequenceNumber);
    }

    function entropyCallback(
        uint64 sequenceNumber,
        address /* _providerAddress */,
        bytes32 randomNumber
    ) internal virtual override {
        uint256 taskId = _sequenceNumberToTaskId[sequenceNumber];
        if (taskId == 0) revert TaskNotFound(sequenceNumber);
        
        bytes32 eligibleRoleId = _tasks[taskId].eligibleRoleId;
        if (getRoleMemberCount(eligibleRoleId) > 0) revert NoEligibleMember(eligibleRoleId);

        uint256 seed = Pseudorandom.derive(abi.encodePacked(randomNumber));
        uint256 assigneeIndex = Pseudorandom.pick(seed, getRoleMemberCount(eligibleRoleId));

        address assignee = getRoleMember(eligibleRoleId, assigneeIndex);
        _tasks[taskId].assignedTo = assignee;
        emit TaskAssigned(taskId, eligibleRoleId, assignee);
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }
}
