// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../src/StreamingStaking.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";


// MOCKS — these would be real supertokens or mock implementations
contract StakeToken is ERC20 {
    constructor() ERC20("StakeToken", "SKT") {
        _mint(msg.sender, 1000000 ether); // Mint 1 million tokens to deployer
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}


contract RewardToken is ERC20 {
    constructor() ERC20("RewardToken", "RWT") {
        _mint(msg.sender, 1000000 ether); // Mint 1 million tokens to deployer
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}


contract StreamingStakingTest is Test {
    using SuperTokenV1Library for ISuperToken;

    SuperfluidFrameworkDeployer.Framework private sf;
    StreamingStaking staking;
    StakeToken underlyingTokenX;
    ISuperToken tokenX;
    RewardToken tokenY;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        SuperfluidFrameworkDeployer sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        sf = sfDeployer.getFramework();

        underlyingTokenX = new StakeToken();
        tokenX = ISuperToken(sf.superTokenFactory.createERC20Wrapper(
            underlyingTokenX,
            ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE,
            "Super Stake",
            "SKTx"
        ));

        tokenY = new RewardToken();

        // Deploy staking contract with mock Superfluid host and CFA (just placeholders)
        staking = new StreamingStaking(
            sf.host, // mock
            sf.cfa, // mock
            tokenX,
            IERC20(address(tokenY))
        );

        // Mint tokens to users
        underlyingTokenX.mint(alice, 1000 ether);
        
        vm.startPrank(alice);
        underlyingTokenX.approve(address(tokenX), 1000 ether);
        tokenX.upgrade(1000 ether);
        vm.stopPrank();

        tokenY.mint(address(bob), 5000 ether);
    }

    function testUpdateRewardsSimulated() public {
        uint256 before = staking.totalRewardReceived();
        vm.startPrank(bob);
        tokenY.approve(address(staking), 100 ether);
        staking.updateRewards();
        vm.stopPrank();
        uint256 afterReward = staking.totalRewardReceived();

        assertEq(afterReward - before, 100 ether);
    }

    // Add tests simulating stream start, stop, and reward distribution
    function testCreateStream() public {
        vm.startPrank(bob);
        tokenY.approve(address(staking), 100 ether);
        staking.updateRewards();
        vm.stopPrank();

        uint256 balanceXBefore = tokenX.balanceOf(alice);
        uint256 balanceYBefore = tokenY.balanceOf(alice);

        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeWithSelector(
                sf.cfa.createFlow.selector,
                tokenX,
                address(staking),
                int96(10),
                new bytes(0)
            ),
            new bytes(0)
        );

        uint256 current = block.timestamp;
        vm.warp(current + 10 seconds);
        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeWithSelector(
                sf.cfa.deleteFlow.selector,
                tokenX,
                alice,
                address(staking),
                new bytes(0)
            ),
            new bytes(0)
        );

        uint256 balanceXAfter = tokenX.balanceOf(alice);
        uint256 balanceYAfter = tokenY.balanceOf(alice);
        assertEq(balanceXAfter, balanceXBefore - 100);
        assertEq(balanceYAfter, 100 ether);
    }
}
