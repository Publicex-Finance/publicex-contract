// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@pefish/solidity-lib/contracts/contract/Ownable.sol";
import {Initializable} from "@pefish/solidity-lib/contracts/contract/Initializable.sol";
import {IErc20} from "@pefish/solidity-lib/contracts/interface/IErc20.sol";
import {SafeToken} from "@pefish/solidity-lib/contracts/library/SafeToken.sol";
import {IPbc} from "../interface/IPbc.sol";
import {ReentrancyGuard} from "@pefish/solidity-lib/contracts/contract/ReentrancyGuard.sol";

interface ArbSys {
    /**
    * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
    * @return block number as int
     */ 
    function arbBlockNumber() external view returns (uint);
}

contract Pool is Ownable, Initializable, ReentrancyGuard {
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    struct UserInfo {
        uint256 amount; // How many Staking tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        address fundedBy; // Funded by who?
    }

    // Info of each pool.
    struct PoolInfo {
        address stakeToken; // Address of Staking token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that Tokens distribution occurs.
        uint256 accTokenPerShare; // Accumulated Tokens per share, times 1e12. See below.
        uint256 outFee; // ? / 10000
        uint256 noOutFeeBlock;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes Staking tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // Token tokens created per block.
    uint256 public tokenPerBlock;
    // The TOKEN!
    IPbc public token;
    // The block number when Token mining starts.
    uint256 public startBlock;
    uint256 constant MAXOUTFEE = 50;
    address public foundation = address(0);
    uint256 public harvestFee; // ? / 10000

    /// @dev init function for proxy
    function init(
        address _token,
        uint256 _tokenPerBlock,
        uint256 _startBlock,
        address _foundation
    ) external initializer {
        ReentrancyGuard.__ReentrancyGuard_init();
        Ownable.__Ownable_init();

        token = IPbc(_token);
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
        foundation = _foundation;
    }

    // ---------------------------- view function ----------------------------

    /// @dev View function to see pending Tokens on frontend.
    function pendingToken(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = IErc20(pool.stakeToken).balanceOf(address(this));
        if (ArbSys(address(100)).arbBlockNumber() > pool.lastRewardBlock && lpSupply != 0) {
            uint256 tokenReward = ((ArbSys(address(100)).arbBlockNumber() - pool.lastRewardBlock) *
                tokenPerBlock *
                pool.allocPoint) / totalAllocPoint;
            accTokenPerShare =
                accTokenPerShare +
                (tokenReward * 1e12) /
                lpSupply;
        }
        return (user.amount * accTokenPerShare) / 1e12 - user.rewardDebt;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function isDuplicatedPool(address _stakeToken) public view returns (bool) {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            if (poolInfo[_pid].stakeToken == _stakeToken) {
                return true;
            }
        }
        return false;
    }

    // ---------------------------- internal function ----------------------------

    function _harvest(address _to, uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_to];
        require(user.amount > 0, "Pool::_harvest:: nothing to harvest");
        uint256 pending = (user.amount * pool.accTokenPerShare) /
            1e12 -
            user.rewardDebt;
        require(
            pending <= token.balanceOf(address(this)),
            "Pool::_harvest:: not enough token"
        );
        uint256 fee = (pending * harvestFee) / 10000;
        if (fee > 0) {
            _safeTokenTransfer(foundation, fee);
        }
        _safeTokenTransfer(_to, pending - fee);
        emit Harvest(_to, _pid, pending);
    }

    /// @dev Safe token transfer function, just in case if rounding error causes pool to not have enough Tokens.
    function _safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            token.transfer(_to, tokenBal);
        } else {
            token.transfer(_to, _amount);
        }
    }

    function _withdraw(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.fundedBy == msg.sender, "Pool::_withdraw:: only funder");
        require(user.amount >= _amount, "Pool::_withdraw:: not good");
        updatePool(_pid);
        _harvest(msg.sender, _pid);
        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
        if (user.amount == 0) {
            user.fundedBy = address(0);
        }
        if (pool.stakeToken != address(0)) {
            uint256 outFee = pool.outFee;
            if (ArbSys(address(100)).arbBlockNumber() > pool.noOutFeeBlock) {
                outFee = 0;
            }
            uint256 fee = (_amount * outFee) / 10000;
            if (fee > 0) {
                SafeToken.safeTransfer(pool.stakeToken, foundation, fee);
            }
            SafeToken.safeTransfer(
                pool.stakeToken,
                address(msg.sender),
                _amount - fee
            );
        }
        emit Withdraw(msg.sender, _pid, user.amount);
    }

    // ---------------------------- external function ----------------------------

    /// @dev Deposit Staking tokens to poll for allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.fundedBy != address(0)) {
            require(user.fundedBy == msg.sender, "Pool::deposit:: bad funder");
        }
        require(
            pool.stakeToken != address(0),
            "Pool::deposit:: not accept deposit token"
        );
        updatePool(_pid);
        if (user.amount > 0) {
            _harvest(msg.sender, _pid);
        }
        if (user.fundedBy == address(0)) {
            user.fundedBy = msg.sender;
        }
        SafeToken.safeTransferFrom(
            pool.stakeToken,
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount + _amount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @dev Withdraw Staking tokens from pool.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        _withdraw(_pid, _amount);
    }

    function withdrawAll(uint256 _pid) external nonReentrant {
        _withdraw(_pid, userInfo[_pid][msg.sender].amount);
    }

    /// @dev Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            user.fundedBy == msg.sender,
            "Pool::emergencyWithdraw:: only funder"
        );
        SafeToken.safeTransfer(
            pool.stakeToken,
            address(msg.sender),
            user.amount
        );
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.fundedBy = address(0);
    }

    /// @dev Harvest Tokens earn from the pool.
    function harvest(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        _harvest(msg.sender, _pid);
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
    }

    // ---------------------------- external function of owner ----------------------------

    /// @dev Update the given pool's Token allocation point. Can only be called by the owner.
    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _outFee,
        uint256 _noOutFeeBlock
    ) external onlyOwner {
        massUpdatePools();
        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].outFee = _outFee;
        poolInfo[_pid].noOutFeeBlock = _noOutFeeBlock;
    }

    function setGovAddr(address _gov) external onlyOwner {
        foundation = _gov;
    }

    /// @dev Add a new lp to the pool. Can only be called by the owner.
    function addPool(
        uint256 _allocPoint,
        address _stakeToken,
        uint256 _outFee,
        uint256 _noOutFeeBlock,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        require(
            _stakeToken != address(0),
            "Pool::addPool:: not stakeToken addr"
        );
        require(
            !isDuplicatedPool(_stakeToken),
            "Pool::addPool:: stakeToken dup"
        );
        uint256 lastRewardBlock = ArbSys(address(100)).arbBlockNumber() > startBlock
            ? ArbSys(address(100)).arbBlockNumber()
            : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                stakeToken: _stakeToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accTokenPerShare: 0,
                outFee: _outFee,
                noOutFeeBlock: _noOutFeeBlock
            })
        );
    }

    function setTokenPerBlock(uint256 _tokenPerBlock) external onlyOwner {
        tokenPerBlock = _tokenPerBlock;
    }

    // ---------------------------- public function ----------------------------

    /// @dev Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @dev Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (ArbSys(address(100)).arbBlockNumber() <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = IErc20(pool.stakeToken).balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = ArbSys(address(100)).arbBlockNumber();
            return;
        }
        uint256 tokenReward = ((ArbSys(address(100)).arbBlockNumber() - pool.lastRewardBlock) *
            tokenPerBlock *
            pool.allocPoint) / totalAllocPoint;
        pool.accTokenPerShare =
            pool.accTokenPerShare +
            (tokenReward * 1e12) /
            lpSupply;
        pool.lastRewardBlock = ArbSys(address(100)).arbBlockNumber();
    }
}
