// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DappToken.sol";
import "./LPToken.sol";

contract TokenFarm {
    string public name = "Proportional Token Farm";
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;

    // Recompensas
    uint256 public rewardPerBlock;
    uint256 public minRewardPerBlock;
    uint256 public maxRewardPerBlock;
    bool    public dynamicRewards;

    uint256 public totalStakingBalance;

    // Fee de recompensas
    uint256 public feePercent;
    uint256 public accumulatedFees;

    address[] public stakers;

    struct Staker {
        uint256 balance;
        uint256 checkpoint;
        uint256 pendingRewards;
        bool hasStaked;
        bool isStaking;
    }

    mapping(address => Staker) public stakersInfo;

    // --- Eventos ---
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount, uint256 fee);
    event RewardsDistributed(address indexed user, uint256 amount, uint256 blocksPassed);
    event RewardsDistributedAll(uint256 processed);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RewardPerBlockUpdated(uint256 oldReward, uint256 newReward);
    event RewardRangeUpdated(uint256 minReward, uint256 maxReward);
    event DynamicRewardsToggled(bool enabled);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed owner, uint256 amount);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyStaker() {
        require(stakersInfo[msg.sender].isStaking, "Not staking");
        _;
    }

    // --- Constructor ---
    constructor(
        DAppToken _dappToken,
        LPToken _lpToken,
        uint256 _initialReward,
        uint256 _minReward,
        uint256 _maxReward,
        uint256 _feePercent
    ) {
        require(address(_dappToken) != address(0) && address(_lpToken) != address(0), "Zero address");
        require(_minReward <= _initialReward && _initialReward <= _maxReward, "Invalid reward range");
        require(_feePercent <= 10000, "Fee > 100%");

        dappToken = _dappToken;
        lpToken = _lpToken;
        owner = msg.sender;

        rewardPerBlock = _initialReward;
        minRewardPerBlock = _minReward;
        maxRewardPerBlock = _maxReward;
        dynamicRewards = false;

        feePercent = _feePercent;

        emit OwnershipTransferred(address(0), msg.sender);
    }

    // --- Admin ---
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero addr");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRewardPerBlock(uint256 newReward) external onlyOwner {
        require(newReward >= minRewardPerBlock && newReward <= maxRewardPerBlock, "Out of range");
        uint256 old = rewardPerBlock;
        rewardPerBlock = newReward;
        emit RewardPerBlockUpdated(old, newReward);
    }

    function setRewardRange(uint256 _minReward, uint256 _maxReward) external onlyOwner {
        require(_minReward > 0 && _maxReward >= _minReward, "Invalid range");
        minRewardPerBlock = _minReward;
        maxRewardPerBlock = _maxReward;

        if (rewardPerBlock < _minReward) rewardPerBlock = _minReward;
        if (rewardPerBlock > _maxReward) rewardPerBlock = _maxReward;

        emit RewardRangeUpdated(_minReward, _maxReward);
    }

    function setDynamicRewards(bool enabled) external onlyOwner {
        dynamicRewards = enabled;
        emit DynamicRewardsToggled(enabled);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10000, "Fee > 100%");
        uint256 old = feePercent;
        feePercent = _feePercent;
        emit FeeUpdated(old, _feePercent);
    }

    function withdrawFees() external onlyOwner {
        require(accumulatedFees > 0, "No fees");
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;
        dappToken.mint(owner, amount);
        emit FeesWithdrawn(owner, amount);
    }

    // --- Usuario ---
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Amount=0");
        Staker storage user = stakersInfo[msg.sender];

        _distributeRewards(msg.sender);
        lpToken.transferFrom(msg.sender, address(this), _amount);

        user.balance += _amount;
        totalStakingBalance += _amount;

        if (!user.hasStaked) {
            stakers.push(msg.sender);
            user.hasStaked = true;
        }
        user.isStaking = true;
        user.checkpoint = block.number;

        emit Deposited(msg.sender, _amount);
    }

    function withdraw() external onlyStaker {
        Staker storage user = stakersInfo[msg.sender];
        uint256 balance = user.balance;
        require(balance > 0, "Balance=0");

        _distributeRewards(msg.sender);

        user.balance = 0;
        totalStakingBalance -= balance;
        user.isStaking = false;

        lpToken.transfer(msg.sender, balance);
        user.checkpoint = block.number;

        emit Withdrawn(msg.sender, balance);
    }

    function claimRewards() external onlyStaker {
        Staker storage user = stakersInfo[msg.sender];
        uint256 pending = user.pendingRewards;
        require(pending > 0, "No rewards");

        uint256 fee = (pending * feePercent) / 10000;
        uint256 netAmount = pending - fee;

        user.pendingRewards = 0;
        accumulatedFees += fee;

        dappToken.mint(msg.sender, netAmount);

        emit RewardsClaimed(msg.sender, netAmount, fee);
    }

    function distributeRewardsAll() external onlyOwner {
        uint256 processed;
        for (uint256 i = 0; i < stakers.length; i++) {
            address userAddr = stakers[i];
            Staker storage user = stakersInfo[userAddr];
            if (user.isStaking && user.balance > 0) {
                _distributeRewards(userAddr);
                processed++;
            } else if (user.checkpoint == 0) {
                user.checkpoint = block.number;
            }
        }
        emit RewardsDistributedAll(processed);
    }

    // --- Views ---
    function pendingRewardsView(address beneficiary) external view returns (uint256) {
        Staker storage user = stakersInfo[beneficiary];
        uint256 last = user.checkpoint;
        if (last == 0 || block.number <= last || totalStakingBalance == 0 || user.balance == 0) {
            return user.pendingRewards;
        }

        uint256 blocks = block.number - last;
        uint256 effReward = _effectiveRewardPerBlockView(beneficiary, last, block.number);
        return user.pendingRewards + (effReward * blocks * user.balance) / totalStakingBalance;
    }

    // --- Internas ---
    function _distributeRewards(address beneficiary) private {
        Staker storage user = stakersInfo[beneficiary];
        uint256 last = user.checkpoint;

        if (last == 0 || block.number <= last || totalStakingBalance == 0 || user.balance == 0) {
            user.checkpoint = block.number;
            return;
        }

        uint256 blocks = block.number - last;
        uint256 effReward = _effectiveRewardPerBlockStateful(beneficiary, last, block.number);
        uint256 reward = (effReward * blocks * user.balance) / totalStakingBalance;

        if (reward > 0) {
            user.pendingRewards += reward;
            emit RewardsDistributed(beneficiary, reward, blocks);
        }

        user.checkpoint = block.number;
    }

    function _effectiveRewardPerBlockStateful(address beneficiary, uint256 fromBlock, uint256 toBlock)
        internal
        view
        returns (uint256)
    {
        if (!dynamicRewards) return rewardPerBlock;
        uint256 span = maxRewardPerBlock - minRewardPerBlock;
        if (span == 0) return minRewardPerBlock;

        uint256 x = uint256(keccak256(abi.encodePacked(address(this), beneficiary, fromBlock, toBlock)));
        return minRewardPerBlock + (x % (span + 1));
    }

    function _effectiveRewardPerBlockView(address beneficiary, uint256 fromBlock, uint256 toBlock)
        internal
        view
        returns (uint256)
    {
        return _effectiveRewardPerBlockStateful(beneficiary, fromBlock, toBlock);
    }
}
