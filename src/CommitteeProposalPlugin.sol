
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PluginCloneable } from "lib/osx-commons/contracts/src/plugin/PluginCloneable.sol";
import { IDAO } from "lib/osx-commons/contracts/src/dao/IDAO.sol";
import { IEntropyConsumer } from "node_modules/@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import { IEntropy } from "node_modules/@pythnetwork/entropy-sdk-solidity/IEntropy.sol";

contract CommitteeProposalPlugin is PluginCloneable, IEntropyConsumer {
    error ProposalAlreadyResolved(uint256 proposalId);
    error VotingPeriodOver(uint256 proposalId);
    error VotingPeriodNotOver(uint256 proposalId);
    error NotInsideVote(address voter);
    error InsufficientFeeForRandomness();
    error DAODoesntHavePermission();

    struct SpecialProposal {
        address proposer;
        string description;
        address[] committeeMembers;
        mapping(address => bool) voted;
        mapping(address => bool) vote;
        uint256 deadline;
        bool resolved;
        address selectedExecutor;
    }

    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 public constant RESOLVE_PROPOSAL_PERMISSION_ID = keccak256("RESOLVE_PROPOSAL_PERMISSION");
    bytes32 public constant ADMIN_EXECUTE_PERMISSION_ID = keccak256('ADMIN_EXECUTE_PERMISSION');

    address public admin;
    mapping(uint256 => SpecialProposal) public specialProposals;
    uint256 public proposalCount;
    IEntropy private entropy;

    event SpecialProposalCreated(uint256 proposalId, string description);
    event MemberVoted(uint256 proposalId, address member, bool willDoIt);
    event ExecutorSelected(uint256 proposalId, address executor);

    function initialize(IDAO _dao, address _admin, address _entropy) external initializer {
        entropy = IEntropy(_entropy);
        __PluginCloneable_init(_dao);
        admin = _admin;
    }

    function createSpecialProposal(
        string memory description,
        address[] memory committee
    ) external {
        if(!dao().hasPermission(address(this), msg.sender, CREATE_PROPOSAL_PERMISSION_ID, msg.data))
            revert DAODoesntHavePermission();
        uint256 id = proposalCount++;
        SpecialProposal storage p = specialProposals[id];
        p.proposer = msg.sender;
        p.description = description;
        p.committeeMembers = committee;
        p.deadline = block.timestamp + 1 days;
        emit SpecialProposalCreated(id, description);
    }

    function vote(uint256 proposalId, bool willDoIt) external {
        SpecialProposal storage p = specialProposals[proposalId];
        if (p.resolved) revert ProposalAlreadyResolved(proposalId);
        if (block.timestamp >= p.deadline) revert VotingPeriodOver(proposalId);

        bool isMember = false;
        for (uint256 i = 0; i < p.committeeMembers.length; i++) {
            if (p.committeeMembers[i] == msg.sender) {
                isMember = true;
                break;
            }
        }
        if (!isMember) revert NotInsideVote(msg.sender);

        p.voted[msg.sender] = true;
        p.vote[msg.sender] = true;
        emit MemberVoted(proposalId, msg.sender, willDoIt);
    }

    function resolve(uint256 proposalId, bytes32 randomness) external payable {
        if(!dao().hasPermission(address(this), msg.sender, CREATE_PROPOSAL_PERMISSION_ID, msg.data))
            revert DAODoesntHavePermission();
        SpecialProposal storage p = specialProposals[proposalId];
        if (p.resolved) revert ProposalAlreadyResolved(proposalId);
        if (block.timestamp < p.deadline)
            revert VotingPeriodNotOver(proposalId);

        address[] memory volunteers = new address[](p.committeeMembers.length);
        uint256 count = 0;
        for (uint256 i = 0; i < p.committeeMembers.length; i++) {
            address member = p.committeeMembers[i];
            if (p.vote[member]) {
                volunteers[count] = member;
                count++;
            }
        }

        address selected;
        if (count == 1) {
            selected = volunteers[0];
        } else {
            address provider = entropy.getDefaultProvider();
            uint256 fee = entropy.getFee(provider);
            if (msg.value < fee) revert InsufficientFeeForRandomness();
            uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(
                provider,
                randomness
            );

            if (count == 0) {
                count = p.committeeMembers.length;
                selected = p.committeeMembers[uint256(randomness) % count];
            } else {
                selected = volunteers[uint256(randomness) % count];
            }
        }

        p.selectedExecutor = selected;
        p.resolved = true;

        emit ExecutorSelected(proposalId, selected);
    }

    function getExecutor(uint256 proposalId) external view returns (address) {
        return specialProposals[proposalId].selectedExecutor;
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    function entropyCallback(
        uint64 sequence,
        address provider,
        bytes32 randomNumber
    ) internal virtual override {}
}
