// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import { CFASuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/CFASuperAppBase.sol";
import { SuperAppDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/Definitions.sol";
import { IConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract StreamingStaking is CFASuperAppBase{
    IConstantFlowAgreementV1 public cfa;

    ISuperToken public stakingTokenX;
    IERC20 public rewardTokenY;
    uint256 public totalRewardReceived;

    struct UserInfo {
        int96 flowRate;
        uint256 startTime;
        uint256 refundAmount;
    }

    mapping(address => UserInfo) public users;

    constructor(
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        ISuperToken _stakingTokenX,
        IERC20 _rewardTokenY) CFASuperAppBase(_host)
    {
        cfa = _cfa;
        stakingTokenX = _stakingTokenX;
        rewardTokenY = _rewardTokenY;

        // Register SuperApp
        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL;
        _host.registerApp(configWord);
    }

    /// @notice Simulated method to add rewards, returns amount received
    function updateRewards() external {
        IERC20(rewardTokenY).transferFrom(msg.sender, address(this), 100 ether);
        totalRewardReceived += 100 ether;
    }

    function onFlowCreated(
        ISuperToken superToken,
        address sender,
        bytes calldata ctx
    ) internal override returns (bytes memory /*newCtx*/) {
        require(superToken == stakingTokenX, "Invalid token");

        (, int96 flowRate,,) = cfa.getFlow(superToken, sender, address(this));

        require(flowRate > 0, "FlowRate must be positive");

        users[sender] = UserInfo({
            flowRate: flowRate,
            startTime: block.timestamp,
            refundAmount: 0
        });

        return ctx;
    }

    function onFlowDeleted(
        ISuperToken superToken,
        address sender,
        address /*receiver*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory /*newCtx*/) {
        if (superToken != stakingTokenX) {
            return ctx;
        }

        (, int96 flowRate,uint256 deposit,) = cfa.getFlow(superToken, sender, address(this));
        
        // If flowRate is 0, the stream was terminated
        if (flowRate == 0) {
            users[sender].refundAmount = deposit;
            _stopStream(sender);
        }

        return ctx;
    }



    function _stopStream(address user) internal {
        UserInfo storage info = users[user];
        require(info.flowRate > 0, "No active stream");

        uint256 streamedTime = block.timestamp - info.startTime;
        uint256 userStreamedXAmount = uint256(uint96(info.flowRate)) * streamedTime;

        uint256 totalStreamedXAmount = stakingTokenX.balanceOf(address(this));
        uint256 userShare = totalRewardReceived * userStreamedXAmount / totalStreamedXAmount;
        totalRewardReceived -= userShare;

        // Transfer reward Y and refund unspent X
        rewardTokenY.transfer(user, userShare);
        stakingTokenX.transfer(user, users[user].refundAmount);
        delete users[user];
    }
}
