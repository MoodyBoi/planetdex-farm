/**
 *Submitted for verification at FtmScan.com on 2021-04-25
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "./PlanetaryExchangeToken.sol";


contract AsteroidBelt is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        mapping(IERC20 => uint256) rewardDebts;
    }

    IERC20[] rewardTokens;

    mapping(IERC20 => uint256) public accTokenPerShares;
    mapping(IERC20 => uint256) public lastBalances;
    mapping(IERC20 => uint256) public allTimeTotalAccrued;

    uint256 public totalDeposited;
    
    // can probably make this more explicit when the token is done
    PlanetaryExchangeToken public plex; 

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(PlanetaryExchangeToken _plex) {
        plex = _plex;
    }

    function addRewardToken(IERC20 _rewardToken) external onlyOwner {
        massUpdate();
        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            require(rewardTokens[i] != _rewardToken, "already rewardToken");
        }
        rewardTokens.push(_rewardToken);
    }

    function pendingTokens(IERC20 _rewardToken, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accTokenPerShare = accTokenPerShares[_rewardToken];
        uint256 lpSupply = totalDeposited;


        uint256 delta;
        if (address(_rewardToken) != address(plex)) {
            if (_rewardToken.balanceOf(address(this)) > lastBalances[_rewardToken]) {
                delta = _rewardToken.balanceOf(address(this)).sub(lastBalances[_rewardToken]);   
            }
        } else {
            if (_rewardToken.balanceOf(address(this)).sub(totalDeposited) > lastBalances[_rewardToken]) {
                delta = _rewardToken.balanceOf(address(this)).sub(totalDeposited).sub(lastBalances[_rewardToken]);   
            }
        }
        
        accTokenPerShare = accTokenPerShares[_rewardToken].add(delta.mul(1e12).div(lpSupply));
        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebts[_rewardToken]);
    }

    function massUpdate() public {
        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            updateRewards(rewardTokens[i]);
        }
    }

    function updateRewards(IERC20 _rewardToken) public {
        uint256 lpSupply = totalDeposited;
        if (lpSupply == 0) {
            return;
        }
        uint256 delta;
        if (address(_rewardToken) != address(plex)) {
            if (_rewardToken.balanceOf(address(this)) > lastBalances[_rewardToken]) {
                delta = _rewardToken.balanceOf(address(this)).sub(lastBalances[_rewardToken]);  
            }
            lastBalances[_rewardToken] = _rewardToken.balanceOf(address(this));
        } else {
            if (_rewardToken.balanceOf(address(this)).sub(totalDeposited) > lastBalances[_rewardToken]) {
                delta = _rewardToken.balanceOf(address(this)).sub(totalDeposited).sub(lastBalances[_rewardToken]);   
            }
            lastBalances[_rewardToken] = _rewardToken.balanceOf(address(this)).sub(totalDeposited);
        }
        
        allTimeTotalAccrued[_rewardToken].add(delta);
        accTokenPerShares[_rewardToken] = accTokenPerShares[_rewardToken].add(delta.mul(1e12).div(lpSupply));
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];

        massUpdate();

        user.amount = user.amount.add(_amount);
        totalDeposited = totalDeposited.add(_amount);

        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20 rewardToken = rewardTokens[i];
            user.rewardDebts[rewardToken] = user.amount.mul(accTokenPerShares[rewardToken]).div(1e12);

            uint256 pending = user.amount.mul(accTokenPerShares[rewardToken]).div(1e12).sub(user.rewardDebts[rewardToken]);
            if (pending > 0) {
                lastBalances[rewardToken] = lastBalances[rewardToken].sub(pending);
                rewardToken.safeTransfer(msg.sender, pending);
            }
        }
        IERC20(plex).safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        massUpdate();

        user.amount = user.amount.sub(_amount);
        totalDeposited = totalDeposited.sub(_amount);

        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20 rewardToken = rewardTokens[i];
            user.rewardDebts[rewardToken] = user.amount.mul(accTokenPerShares[rewardToken]).div(1e12);

            uint256 pending = user.amount.mul(accTokenPerShares[rewardToken]).div(1e12).sub(user.rewardDebts[rewardToken]);
            if (pending > 0) {
                lastBalances[rewardToken] = lastBalances[rewardToken].sub(pending);
                rewardToken.safeTransfer(msg.sender, pending);
            }
        }
        safePlexTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];

        uint oldUserAmount = user.amount;
        user.amount = 0;

        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            user.rewardDebts[rewardTokens[i]] = 0;
        }

        safePlexTransfer(address(msg.sender), oldUserAmount);
        emit EmergencyWithdraw(msg.sender, oldUserAmount);

    }

    // Safe boo transfer function, just in case if rounding error causes pool to not have enough BOOs.
    function safePlexTransfer(address _to, uint256 _amount) internal {
        uint256 plexBal = plex.balanceOf(address(this));
        if (_amount > plexBal) {
            plex.transfer(_to, plexBal);
        } else {
            plex.transfer(_to, _amount);
        }
    }
}