// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './PlanetaryExchangeToken.sol';

contract PlanetaryIFO is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PLEXs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPLEXPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accPLEXPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 Token;           // Address of token contract.
        uint256 stakingTokenTotalAmount;
        uint256 allocPoint;       // How many allocation points assigned to this pool. PLEXs to distribute per block.
        uint256 lastRewardTime;  // Last block time that PLEXs distribution occurs.
        uint256 accPLEXPerShare; // Accumulated PLEXs per share, times 1e12. See below.
    }

    // planetdeX
    PlanetaryExchangeToken public plex;

    // plex tokens created per block.
    uint256 public plexPerSecond;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when plex mining starts.
    uint256 public immutable startTime;

    uint256 public endTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        PlanetaryExchangeToken _plex,
        uint256 _plexPerSecond,
        uint256 _startTime
    ) {
        plex = _plex;
        plexPerSecond = _plexPerSecond;
        startTime = _startTime;
        endTime = _startTime + 13 weeks;
    }

    function changeEndTime(uint32 addSeconds) external onlyOwner {
        endTime += addSeconds;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Good practice to update pools without messing up the contract
    function setPlexPerSecond(uint256 _plexPerSecond) external onlyOwner {

        // This MUST be done or pool rewards will be calculated with new plex per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools(); 

        plexPerSecond = _plexPerSecond;
    }

    function checkForDuplicate(IERC20 _Token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].Token != _Token, "add: pool already exists!!!!");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _Token) external onlyOwner {

        checkForDuplicate(_Token); // ensure you cant add duplicate pools

        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            Token: _Token,
            allocPoint: _allocPoint,
            stakingTokenTotalAmount: 0,
            lastRewardTime: lastRewardTime,
            accPLEXPerShare: 0
        }));
    }

    // Update the given pool's plex allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_from > endTime || _to < startTime) {
            return 0;
        }
        if (_to > endTime) {
            return endTime - _from;
        }
        return _to - _from;
    }

    // View function to see pending PLEXs on frontend.
    function pendingPLEX(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPLEXPerShare = pool.accPLEXPerShare;

        if (block.timestamp > pool.lastRewardTime && pool.stakingTokenTotalAmount != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 plexReward = multiplier.mul(plexPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accPLEXPerShare = accPLEXPerShare.add(plexReward.mul(1e12).div(pool.stakingTokenTotalAmount));
        }
        return user.amount.mul(accPLEXPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.stakingTokenTotalAmount == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 plexReward = multiplier.mul(plexPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        pool.accPLEXPerShare = pool.accPLEXPerShare.add(plexReward.mul(1e12).div(pool.stakingTokenTotalAmount));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit tokens to IFO for plex allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accPLEXPerShare).div(1e12).sub(user.rewardDebt);

        user.amount = user.amount.add(_amount);
        pool.stakingTokenTotalAmount += _amount;
        user.rewardDebt = user.amount.mul(pool.accPLEXPerShare).div(1e12);

        if(pending > 0) {
            safePLEXTransfer(msg.sender, pending);
        }
        pool.Token.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accPLEXPerShare).div(1e12).sub(user.rewardDebt);

        user.amount = user.amount.sub(_amount);
        pool.stakingTokenTotalAmount -= _amount;
        user.rewardDebt = user.amount.mul(pool.accPLEXPerShare).div(1e12);

        if(pending > 0) {
            safePLEXTransfer(msg.sender, pending);
        }
        pool.Token.safeTransfer(address(msg.sender), _amount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint oldUserAmount = user.amount;
        pool.stakingTokenTotalAmount -= user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        pool.Token.safeTransfer(address(msg.sender), oldUserAmount);
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);

    }

    // Safe plex transfer function, just in case if rounding error causes pool to not have enough PLEXs.
    function safePLEXTransfer(address _to, uint256 _amount) internal {
        uint256 plexBal = plex.balanceOf(address(this));
        if (_amount > plexBal) {
            plex.transfer(_to, plexBal);
        } else {
            plex.transfer(_to, _amount);
        }
    }
}