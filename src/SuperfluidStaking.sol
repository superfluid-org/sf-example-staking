// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";

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

    IERC20 public underlyingToken;
    ISuperToken public superToken;
    ISuperfluidPool public pool;
    SuperTokenFactory public superTokenFactory;

    mapping(address => uint256) public stakedAmounts;
    mapping(address => ClaimContract) public claimContracts;

    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    constructor(IERC20 _underlyingToken, SuperTokenFactory _superTokenFactory) {
        underlyingToken = _underlyingToken;
        superTokenFactory = _superTokenFactory;
        superToken = ISuperToken(superTokenFactory.createCanonicalERC20Wrapper(underlyingToken));

        pool = ISuperfluidPool(superToken.createPool(
            address(this),
            ISuperfluidPool.PoolConfig({
                transferabilityForUnitsOwner: false,
                distributionFromAnyAddress: true
            })
        ));
    }

    function supplyFunds(uint256 amount, uint256 duration) external onlyOwner {
        require(duration > 0, "Duration must be greater than 0");
        updateReward(address(0));

        underlyingToken.transferFrom(msg.sender, address(this), amount);
        underlyingToken.approve(address(superToken), amount);
        superToken.upgrade(amount);

        rewardRate = amount / duration;
        lastUpdateTime = block.timestamp;

        superToken.distributeFlow(address(this), pool, int96(int256(rewardRate)));
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        updateReward(msg.sender);

        totalStaked += amount;
        stakedAmounts[msg.sender] += amount;

        underlyingToken.transferFrom(msg.sender, address(this), amount);
        underlyingToken.approve(address(superToken), amount);
        superToken.upgrade(amount);

        if (address(claimContracts[msg.sender]) == address(0)) {
            claimContracts[msg.sender] = new ClaimContract(superToken, address(this), msg.sender);
        }

        superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), uint128(stakedAmounts[msg.sender]));

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Cannot unstake 0");
        require(stakedAmounts[msg.sender] >= amount, "Not enough staked");
        updateReward(msg.sender);

        totalStaked -= amount;
        stakedAmounts[msg.sender] -= amount;

        superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), uint128(stakedAmounts[msg.sender]));

        superToken.downgrade(amount);
        underlyingToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external {
        updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            ClaimContract claimContract = claimContracts[msg.sender];
            claimContract.claim();
            uint256 claimedAmount = superToken.balanceOf(address(claimContract));
            claimContract.withdrawTo(address(this), claimedAmount);
            superToken.downgrade(claimedAmount);
            underlyingToken.transfer(msg.sender, claimedAmount);
            emit RewardsClaimed(msg.sender, claimedAmount);
        }
    }

    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    function earned(address account) public view returns (uint256) {
        return ((stakedAmounts[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
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

    function getRewardRate() external view returns (uint256) {
        return rewardRate;
    }

    function getClaimContract(address user) external view returns (address) {
        return address(claimContracts[user]);
    }
}