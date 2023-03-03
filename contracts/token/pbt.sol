// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@pefish/solidity-lib/contracts/contract/Ownable.sol";
import {IErc20} from "@pefish/solidity-lib/contracts/interface/IErc20.sol";

contract PBT is Ownable, IErc20 {
    address public pool; // farm pool address
    bool public transferLock = true;
    address public lastPresale;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    string public name;
    string public symbol;
    uint8 public override decimals = 18;
    uint256 public override totalSupply;

    constructor(
        uint256 _initialSupply,
        string memory _name,
        string memory _symbol
    ) {
        Ownable.__Ownable_init();

        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initialSupply);
    }

    function mint(address account, uint256 amount)
        external
        onlyOwner
        returns (bool)
    {
        _mint(account, amount);
        return true;
    }

    function setLastPresale(address _lastPresale) external onlyOwner {
        lastPresale = _lastPresale;
    }

    function burn(uint256 amount) external onlyOwner returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        require(!transferLock || msg.sender == owner() || msg.sender == lastPresale, "transfer:: transfer locked");
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(!transferLock || msg.sender == owner() || msg.sender == lastPresale, "transfer:: transfer locked");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        totalSupply = totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _balances[account] = _balances[account] - amount;
        totalSupply = totalSupply - amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function changePool(address _newPool) external onlyOwner {
        pool = _newPool;
    }

    function mintByPool(address _account, uint256 _amount)
        external
        returns (bool)
    {
        require(
            msg.sender == pool,
            "mintByPool:: must be operated by pool address"
        );
        _mint(_account, _amount);
        return true;
    }

    function lockTransfer() external onlyOwner {
        transferLock = true;
    }

    function unlockTransfer() external onlyOwner {
        transferLock = false;
    }
}
