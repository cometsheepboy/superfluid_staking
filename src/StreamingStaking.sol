// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import { CFASuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/CFASuperAppBase.sol";
import { SuperAppDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/Definitions.sol";
import { IConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract StreamingStaking is CFASuperAppBase {
    ISuperfluid public immutable host;
    IConstantFlowAgreementV1 public immutable cfa;

    ISuperToken public immutable stakingTokenX;
    IERC20 public immutable rewardTokenY;

    uint256 public rewardRatePerSecond;
    uint256 public totalFlowRate;

    uint256 public accRewardPerShare; // Scaled by 1e18
    uint256 public lastRewardTime;
    uint256 public totalRewardReceived;

    struct UserInfo {
        int96 flowRate;        // Current stream flow rate
        uint256 rewardDebt;    // Portion of accRewardPerShare already claimed
        uint256 startTime;     // Timestamp when stream started
    }

    mapping(address => UserInfo) public users;

    constructor(
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        ISuperToken _stakingTokenX,
        IERC20 _rewardTokenY
    ) CFASuperAppBase(_host) {
        host = _host;
        cfa = _cfa;
        stakingTokenX = _stakingTokenX;
        rewardTokenY = _rewardTokenY;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL;
        _host.registerApp(configWord);

        lastRewardTime = block.timestamp;
    }

    function updateRewards() external {
        // Simulate funding the reward pool
        uint256 rewardAmount = 100 ether;
        rewardTokenY.transferFrom(msg.sender, address(this), rewardAmount);
        updatePool();
        totalRewardReceived += rewardAmount;
    }

    function setRewardRatePerSecond(uint256 _rewardRatePerSecond) external {
        updatePool();
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    function updatePool() internal {
        uint256 currentTime = block.timestamp;
        if (currentTime <= lastRewardTime || totalFlowRate == 0) {
            lastRewardTime = currentTime;
            return;
        }

        uint256 timeElapsed = currentTime - lastRewardTime;
        uint256 reward = timeElapsed * rewardRatePerSecond;

        accRewardPerShare += (reward * 1e18) / totalFlowRate;
        lastRewardTime = currentTime;
    }

    function onFlowCreated(
        ISuperToken superToken,
        address sender,
        bytes calldata ctx
    ) internal override returns (bytes memory) {
        require(superToken == stakingTokenX, "Invalid token");

        updatePool();

        (, int96 flowRate,,) = cfa.getFlow(superToken, sender, address(this));

        uint256 userFlow = uint256(uint96(flowRate));
        totalFlowRate += userFlow;

        users[sender] = UserInfo({
            flowRate: flowRate,
            rewardDebt: (accRewardPerShare * userFlow) / 1e18,
            startTime: block.timestamp
        });

        return ctx;
    }

    function onFlowDeleted(
        ISuperToken superToken,
        address sender,
        address,
        int96,
        uint256,
        bytes calldata ctx
    ) internal override returns (bytes memory) {
        if (superToken != stakingTokenX) return ctx;

        updatePool();

        UserInfo storage user = users[sender];
        uint256 userFlow = uint256(uint96(user.flowRate));
        uint256 accumulated = (accRewardPerShare * userFlow) / 1e18;
        uint256 pending = accumulated - user.rewardDebt;

        if (pending > 0) {
            rewardTokenY.transfer(sender, pending);
            totalRewardReceived -= pending;
        }

        (, , uint256 deposit,) = cfa.getFlow(superToken, sender, address(this));
        stakingTokenX.transfer(sender, deposit);

        totalFlowRate -= userFlow;
        delete users[sender];

        return ctx;
    }
}