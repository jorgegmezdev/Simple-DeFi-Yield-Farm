// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DappToken.sol";
import "./LPToken.sol";

contract TokenFarmV2 {
    string public name;
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;

    uint256 public rewardPerBlock;
    uint256 public minRewardPerBlock;
    uint256 public maxRewardPerBlock;
    bool public dynamicRewards;

    uint256 public totalStakingBalance;
    uint256 public claimFee; // nuevo: fee en % * 100 (ej: 200 = 2%)
    uint256 public collectedFees;

    address[] public stakers;

    struct Staker {
        uint256 balance;
        uint256 checkpoint;
        uint256 pendingRewards;
        bool hasStaked;
        bool isStaking;
    }
    mapping(address => Staker) public stakersInfo;

    bool private initialized;

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
    event FeeWithdrawn(address indexed owner, uint256 amount);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyStaker() {
        require(stakersInfo[msg.sender].isStaking, "Not staking");
        _;
    }

    // --- Inicialización vía proxy ---
    function initialize(
        DAppToken _dappToken,
        LPToken _lpToken,
        uint256 _initialReward,
        uint256 _minReward,
        uint256 _maxReward,
        uint256 _claimFee
    ) external {
        require(!initialized, "Already initialized");
        require(address(_dappToken) != address(0) && address(_lpToken) != address(0), "Zero address");
        require(_minReward <= _initialReward && _initialReward <= _maxReward, "Invalid reward range");

        dappToken = _dappToken;
        lpToken = _lpToken;
        owner = msg.sender;

        rewardPerBlock = _initialReward;
        minRewardPerBlock = _minReward;
        maxRewardPerBlock = _maxReward;
        dynamicRewards = false;

        claimFee = _claimFee;
        name = "Proportional Token Farm V2";

        initialized = true;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // --- Admin ---
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRewardPerBlock(uint256 newReward) external onlyOwner {
        require(newReward >= minRewardPerBlock && newReward <= maxRewardPerBlock, "out of range");
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

    function setClaimFee(uint256 fee) external onlyOwner {
        require(fee <= 1000, "Fee too high"); // max 10%
        claimFee = fee;
    }

    function withdrawFees() external onlyOwner {
        uint256 amount = collectedFees;
        require(amount > 0, "No fees");
        collectedFees = 0;
        dappToken.mint(owner, amount);
        emit FeeWithdrawn(owner, amount);
    }

    // --- Usuario ---
    function deposit(uint256 _amount) external {
        require(_amount > 0, "amount=0");
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
        require(balance > 0, "balance=0");
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
        uint256 pendingAmount = user.pendingRewards;
        require(pendingAmount > 0, "no rewards");
        uint256 fee = (pendingAmount * claimFee) / 10000;
        uint256 amountAfterFee = pendingAmount - fee;
        collectedFees += fee;
        user.pendingRewards = 0;
        dappToken.mint(msg.sender, amountAfterFee);
        emit RewardsClaimed(msg.sender, amountAfterFee, fee);
    }

    // --- Distribución ---
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

    function pendingRewardsView(address beneficiary) external view returns (uint256) {
        Staker storage user = stakersInfo[beneficiary];
        uint256 last = user.checkpoint;
        if (last == 0 || block.number <= last) return user.pendingRewards;
        if (totalStakingBalance == 0 || user.balance == 0) return user.pendingRewards;
        uint256 blocksPassed = block.number - last;
        uint256 effRewardPerBlock = _effectiveRewardPerBlockView(beneficiary, last, block.number);
        uint256 reward = (effRewardPerBlock * blocksPassed * user.balance) / totalStakingBalance;
        return user.pendingRewards + reward;
    }

    // --- Internas ---
    function _distributeRewards(address beneficiary) private {
        Staker storage user = stakersInfo[beneficiary];
        uint256 last = user.checkpoint;
        if (last == 0) { user.checkpoint = block.number; return; }
        if (block.number <= last) return;
        if (totalStakingBalance == 0 || user.balance == 0) { user.checkpoint = block.number; return; }
        uint256 blocksPassed = block.number - last;
        uint256 effRewardPerBlock = _effectiveRewardPerBlockStateful(beneficiary, last, block.number);
        uint256 reward = (effRewardPerBlock * blocksPassed * user.balance) / totalStakingBalance;
        if (reward > 0) {
            user.pendingRewards += reward;
            emit RewardsDistributed(beneficiary, reward, blocksPassed);
        }
        user.checkpoint = block.number;
    }

    function _effectiveRewardPerBlockStateful(address beneficiary, uint256 fromBlock, uint256 toBlock) internal view returns (uint256) {
        if (!dynamicRewards) return rewardPerBlock;
        uint256 span = maxRewardPerBlock - minRewardPerBlock;
        if (span == 0) return minRewardPerBlock;
        uint256 x = uint256(keccak256(abi.encodePacked(address(this), beneficiary, fromBlock, toBlock)));
        uint256 offset = x % (span + 1);
        return minRewardPerBlock + offset;
    }

    function _effectiveRewardPerBlockView(address beneficiary, uint256 fromBlock, uint256 toBlock) internal view returns (uint256) {
        return _effectiveRewardPerBlockStateful(beneficiary, fromBlock, toBlock);
    }
}
