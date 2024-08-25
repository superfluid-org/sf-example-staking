// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperTokenFactory.sol";

contract ClaimContract {
    ISuperToken public superToken;
    address public stakingContract;
    address public staker;

    constructor(ISuperToken _superToken, address _stakingContract, address _staker) {
        superToken = _superToken;
        stakingContract = _stakingContract;
        staker = _staker;
    }

    function claim() external {
        require(msg.sender == stakingContract, "Only staking contract can call");
        SuperTokenV1Library.claimAll(superToken, ISuperfluidPool(stakingContract), address(this));
    }

    function withdrawTo(address to, uint256 amount) external {
        require(msg.sender == stakingContract, "Only staking contract can call");
        superToken.transfer(to, amount);
    }
}

contract SuperfluidStaking is Ownable {
    using SuperTokenV1Library for ISuperToken;

    IERC20 public underlyingStakedToken;
    IERC20Metadata public underlyingRewardsToken;
    ISuperToken public superToken;
    ISuperfluidPool public pool;
    ISuperTokenFactory public superTokenFactory;
    uint128 public scalingFactor;

    mapping(address => uint256) public stakedAmounts;
    mapping(address => ClaimContract) public claimContracts;

    uint256 public totalStaked;
    int96 public flowRate;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event FundsSupplied(uint256 amount, uint256 duration, int96 flowRate);

    constructor(
        IERC20 _underlyingStakedToken,
        IERC20Metadata _underlyingRewardsToken,
        ISuperTokenFactory _superTokenFactory,
        uint128 _scalingFactor
    ) {
        underlyingStakedToken = _underlyingStakedToken;
        underlyingRewardsToken = _underlyingRewardsToken;
        superTokenFactory = _superTokenFactory;
        scalingFactor = _scalingFactor;
        superToken = ISuperToken(superTokenFactory.createERC20Wrapper(
            underlyingRewardsToken,
            ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE,
            "Super Rewards",
            "RWDx"
        ));

        pool = ISuperfluidPool(superToken.createPool(
            address(this),
            PoolConfig({
                transferabilityForUnitsOwner: false,
                distributionFromAnyAddress: true
            })
        ));
    }

    function supplyFunds(uint256 amount, uint256 duration) external onlyOwner {
        require(duration > 0, "Duration must be greater than 0");

        underlyingRewardsToken.transferFrom(msg.sender, address(this), amount);
        underlyingRewardsToken.approve(address(superToken), amount);
        superToken.upgrade(amount);

        int96 newFlowRate = int96(int256(superToken.balanceOf(address(this)) / duration));
        superToken.distributeFlow(address(this), pool, newFlowRate);
        
        flowRate = newFlowRate;

        emit FundsSupplied(amount, duration, newFlowRate);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");

        totalStaked += amount;
        stakedAmounts[msg.sender] += amount;

        underlyingStakedToken.transferFrom(msg.sender, address(this), amount);

        if (address(claimContracts[msg.sender]) == address(0)) {
            claimContracts[msg.sender] = new ClaimContract(superToken, address(this), msg.sender);
        }

        superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), uint128(stakedAmounts[msg.sender])/scalingFactor);

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Cannot unstake 0");
        require(stakedAmounts[msg.sender] >= amount, "Not enough staked");

        totalStaked -= amount;
        stakedAmounts[msg.sender] -= amount;

        superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), uint128(stakedAmounts[msg.sender])/scalingFactor);

        superToken.downgrade(amount);
        underlyingStakedToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external {
        ClaimContract claimContract = claimContracts[msg.sender];
        require(address(claimContract) != address(0), "No claim contract");

        claimContract.claim();
        uint256 claimedAmount = superToken.balanceOf(address(claimContract));
        claimContract.withdrawTo(address(this), claimedAmount);
        superToken.downgrade(claimedAmount);
        underlyingRewardsToken.transfer(msg.sender, claimedAmount);

        emit RewardsClaimed(msg.sender, claimedAmount);
    }

    function emergencyWithdraw(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

    // Getters
    function getStakedAmount(address user) external view returns (uint256) {
        return stakedAmounts[user];
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getFlowRate() external view returns (int96) {
        return flowRate;
    }

    function getClaimContract(address user) external view returns (address) {
        return address(claimContracts[user]);
    }
}