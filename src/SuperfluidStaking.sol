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

/// @title ClaimContract
/// @notice This contract is created for each staker to manage their rewards
contract ClaimContract {
    ISuperToken public superToken;
    address public stakingContract;
    address public staker;

    /// @param _superToken The SuperToken used for rewards
    /// @param _stakingContract The address of the main staking contract
    /// @param _staker The address of the staker this contract is for
    constructor(ISuperToken _superToken, address _stakingContract, address _staker) {
        superToken = _superToken;
        stakingContract = _stakingContract;
        staker = _staker;
    }

    /// @notice Claims all rewards for the staker
    /// @dev Can only be called by the main staking contract
    function claim() external {
        require(msg.sender == stakingContract, "Only staking contract can call");
        SuperTokenV1Library.claimAll(
            superToken, 
            SuperfluidStaking(stakingContract).pool(),
            address(this)
        );
    }

    /// @notice Withdraws claimed rewards to a specified address
    /// @dev Can only be called by the main staking contract
    /// @param to The address to send the rewards to
    /// @param amount The amount of rewards to withdraw
    function withdrawTo(address to, uint256 amount) external {
        require(msg.sender == stakingContract, "Only staking contract can call");
        superToken.transfer(to, amount);
    }
}

/// @title SuperfluidStaking
/// @notice A staking contract that uses Superfluid for reward distribution
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

    /// @notice Constructor to initialize the staking contract
    /// @param _underlyingStakedToken The token that users will stake
    /// @param _underlyingRewardsToken The token used for rewards
    /// @param _superTokenFactory The Superfluid token factory
    /// @param _scalingFactor A factor used to scale down staked amounts for precision
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
        
        // Create a wrapped super token for rewards
        superToken = ISuperToken(superTokenFactory.createERC20Wrapper(
            underlyingRewardsToken,
            ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE,
            "Super Rewards",
            "RWDx"
        ));

        // Create a Superfluid pool for distributing rewards
        pool = ISuperfluidPool(superToken.createPool(
            address(this),
            PoolConfig({
                transferabilityForUnitsOwner: false,
                distributionFromAnyAddress: true
            })
        ));
    }

    /// @notice Allows the owner to supply funds for rewards
    /// @param amount The amount of reward tokens to supply
    /// @param duration The duration over which these rewards should be distributed
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

    /// @notice Allows users to stake tokens
    /// @param amount The amount of tokens to stake
    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");

        totalStaked += amount;
        stakedAmounts[msg.sender] += amount;

        underlyingStakedToken.transferFrom(msg.sender, address(this), amount);

        // Create a new ClaimContract for the user if they don't have one
        if (address(claimContracts[msg.sender]) == address(0)) {
            claimContracts[msg.sender] = new ClaimContract(superToken, address(this), msg.sender);
        }

        // Update the user's units in the Superfluid pool
        superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), uint128(stakedAmounts[msg.sender])/scalingFactor);

        emit Staked(msg.sender, amount);
    }

    /// @notice Allows users to unstake their tokens
    /// @param amount The amount of tokens to unstake
    function unstake(uint256 amount) external {
        require(amount > 0, "Cannot unstake 0");
        require(stakedAmounts[msg.sender] >= amount, "Not enough staked");

        totalStaked -= amount;
        stakedAmounts[msg.sender] -= amount;

        // Update the user's units in the Superfluid pool
        superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), uint128(stakedAmounts[msg.sender])/scalingFactor);

        superToken.downgrade(amount);
        underlyingStakedToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /// @notice Allows users to claim their accumulated rewards
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

    /// @notice Allows the owner to withdraw any tokens in case of emergency
    /// @param token The token to withdraw
    function emergencyWithdraw(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

    // Getter functions

    /// @notice Get the staked amount for a specific user
    /// @param user The address of the user
    /// @return The amount of tokens staked by the user
    function getStakedAmount(address user) external view returns (uint256) {
        return stakedAmounts[user];
    }

    /// @notice Get the total amount of tokens staked in the contract
    /// @return The total amount of staked tokens
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice Get the current flow rate of reward distribution
    /// @return The current flow rate
    function getFlowRate() external view returns (int96) {
        return flowRate;
    }

    /// @notice Get the claim contract address for a specific user
    /// @param user The address of the user
    /// @return The address of the user's claim contract
    function getClaimContract(address user) external view returns (address) {
        return address(claimContracts[user]);
    }
}