// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SuperfluidStaking.sol";
import {
    ERC1820RegistryCompiled
} from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import {
    SuperfluidFrameworkDeployer
} from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract SuperfluidStakingTest is Test {
    SuperfluidStaking private sfStaking;
    SuperfluidFrameworkDeployer.Framework private sf;
    MockERC20 private stakedToken;
    MockERC20 private rewardsToken;
    ISuperToken private superRewardsToken;

    address public owner;
    address public alice;
    address public bob;

    uint128 public constant SCALING_FACTOR = 1e10;
    uint256 public constant INITIAL_BALANCE = 1000000 * 1e18;
    uint256 public constant STAKE_AMOUNT = 1000 * 1e18;

    function setUp() public {
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        SuperfluidFrameworkDeployer sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        sf = sfDeployer.getFramework();

        owner = address(this);
        alice = address(0x1);
        bob = address(0x2);

        stakedToken = new MockERC20("Staked Token", "STK");

        rewardsToken = new MockERC20("Rewards Token", "RWD");

        sfStaking = new SuperfluidStaking(
            IERC20(address(stakedToken)), IERC20Metadata(address(rewardsToken)), sf.superTokenFactory, SCALING_FACTOR
        );

        superRewardsToken = sfStaking.superToken();

        // Mint tokens to users
        stakedToken.mint(alice, INITIAL_BALANCE);
        stakedToken.mint(bob, INITIAL_BALANCE);
        rewardsToken.mint(owner, INITIAL_BALANCE);

        // Approve staking contract
        vm.startPrank(alice);
        stakedToken.approve(address(sfStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        stakedToken.approve(address(sfStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(owner);
        rewardsToken.approve(address(sfStaking), type(uint256).max);
        vm.stopPrank();
    }

    function testSupplyFunds() public {
        uint256 amount = 10000 * 1e18;
        uint256 duration = 30 days;

        vm.startPrank(owner);
        sfStaking.supplyFunds(amount, duration);
        vm.stopPrank();

        assertEq(sfStaking.getFlowRate(), int96(int256(amount / duration)));
        assertEq(superRewardsToken.balanceOf(address(sfStaking)), amount);
    }

    function testStake() public {
        vm.startPrank(alice);
        sfStaking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(sfStaking.getStakedAmount(alice), STAKE_AMOUNT);
        assertEq(sfStaking.getTotalStaked(), STAKE_AMOUNT);
        assertEq(stakedToken.balanceOf(address(sfStaking)), STAKE_AMOUNT);
    }

    function testUnstake() public {
        uint256 amount = 10000 * 1e18;
        uint256 duration = 30 days;

        vm.startPrank(owner);
        sfStaking.supplyFunds(amount, duration);
        vm.stopPrank();

        vm.startPrank(alice);
        sfStaking.stake(STAKE_AMOUNT);
        sfStaking.unstake(STAKE_AMOUNT / 2);
        vm.stopPrank();

        assertEq(sfStaking.getStakedAmount(alice), STAKE_AMOUNT / 2);
        assertEq(sfStaking.getTotalStaked(), STAKE_AMOUNT / 2);
        assertEq(stakedToken.balanceOf(address(sfStaking)), STAKE_AMOUNT / 2);
    }

    /*function testClaimRewards() public {
        uint256 supplyAmount = 10000 * 1e18;
        uint256 duration = 30 days;

        // Supply funds
        vm.startPrank(owner);
        sfStaking.supplyFunds(supplyAmount, duration);
        vm.stopPrank();

        // Stake tokens
        vm.startPrank(alice);
        sfStaking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 7 days);

        // Claim rewards
        vm.startPrank(alice);
        sfStaking.claimRewards();
        vm.stopPrank();

        // Check rewards (this is an approximation)
        uint256 expectedRewards = (supplyAmount * 7 days) / duration;
        uint256 actualRewards = rewardsToken.balanceOf(alice);
        assertApproxEqRel(actualRewards, expectedRewards, 1e16); // 1% tolerance
    }

    function testMultipleStakers() public {
        uint256 supplyAmount = 10000 * 1e18;
        uint256 duration = 30 days;

        // Supply funds
        vm.startPrank(owner);
        sfStaking.supplyFunds(supplyAmount, duration);
        vm.stopPrank();

        // Alice stakes
        vm.startPrank(alice);
        sfStaking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Bob stakes
        vm.startPrank(bob);
        sfStaking.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();

        assertEq(sfStaking.getTotalStaked(), STAKE_AMOUNT * 3);

        // Advance time
        vm.warp(block.timestamp + 15 days);

        // Both users claim rewards
        vm.startPrank(alice);
        sfStaking.claimRewards();
        vm.stopPrank();

        vm.startPrank(bob);
        sfStaking.claimRewards();
        vm.stopPrank();

        // Check rewards distribution (this is an approximation)
        uint256 totalRewards = (supplyAmount * 15 days) / duration;
        uint256 aliceRewards = rewardsToken.balanceOf(alice);
        uint256 bobRewards = rewardsToken.balanceOf(bob);

        assertApproxEqRel(aliceRewards, totalRewards / 3, 1e16); // 1% tolerance
        assertApproxEqRel(bobRewards, (totalRewards * 2) / 3, 1e16); // 1% tolerance
    }*/

    function testEmergencyWithdraw() public {
        uint256 amount = 1000 * 1e18;
        rewardsToken.transfer(address(sfStaking), amount);

        vm.startPrank(owner);
        uint256 initalOwnerBalance = rewardsToken.balanceOf(owner);
        sfStaking.emergencyWithdraw(IERC20(address(rewardsToken)));
        vm.stopPrank();

        assertEq(rewardsToken.balanceOf(owner), initalOwnerBalance + amount);
    }

    function testGetters() public {
        vm.startPrank(alice);
        sfStaking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(sfStaking.getStakedAmount(alice), STAKE_AMOUNT);
        assertEq(sfStaking.getTotalStaked(), STAKE_AMOUNT);
        assertEq(sfStaking.getFlowRate(), 0); // No funds supplied yet
        assertTrue(sfStaking.getClaimContract(alice) != address(0));
    }

    function testRevertIfStakeZero() public {
        vm.startPrank(alice);
        vm.expectRevert();
        sfStaking.stake(0);
        vm.stopPrank();
    }

    function testRevertIfUnstakeMoreThanStaked() public {
        vm.startPrank(alice);
        sfStaking.stake(STAKE_AMOUNT);
        vm.expectRevert();
        sfStaking.unstake(STAKE_AMOUNT + 1);
        vm.stopPrank();
    }

    function testRevertIfClaimWithoutStaking() public {
        vm.startPrank(alice);
        vm.expectRevert();
        sfStaking.claimRewards();
        vm.stopPrank();
    }

    function testRevertIfEmergencyWithdrawNonOwner() public {
        vm.startPrank(alice);
        vm.expectRevert();
        sfStaking.emergencyWithdraw(IERC20(address(rewardsToken)));
        vm.stopPrank();
    }
}
