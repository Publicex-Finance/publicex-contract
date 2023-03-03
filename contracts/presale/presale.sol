// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeToken} from "@pefish/solidity-lib/contracts/library/SafeToken.sol";
import {Ownable} from "@pefish/solidity-lib/contracts/contract/Ownable.sol";
import {IErc20} from "@pefish/solidity-lib/contracts/interface/IErc20.sol";
import {ReentrancyGuard} from "@pefish/solidity-lib/contracts/contract/ReentrancyGuard.sol";
import {Initializable} from "@pefish/solidity-lib/contracts/contract/Initializable.sol";

contract Presale is Ownable, Initializable, ReentrancyGuard {
    mapping(address => uint256) public prices; // with decimals
    address payable public foundation;
    IErc20 public tokenAddress;

    
    function init(address _tokenAddress, address _foundation) external initializer {
        ReentrancyGuard.__ReentrancyGuard_init();
        Ownable.__Ownable_init();

        foundation = payable(_foundation);
        tokenAddress = IErc20(_tokenAddress);
    }

    function buy(uint256 amount, address _baseToken) external payable {
        require(
            prices[_baseToken] > 0,
            "Presale::buy:: price must larger than 0"
        );
        uint256 need = amount * prices[_baseToken];
        if (_baseToken == address(0)) {
            // ETH
            foundation.transfer(need);
            payable(msg.sender).transfer(msg.value - need);
            SafeToken.safeTransfer(
                address(tokenAddress),
                address(msg.sender),
                amount * (10**tokenAddress.decimals())
            );
        } else {
            // ERC20
            SafeToken.safeTransferFrom(
                _baseToken,
                msg.sender,
                foundation,
                need
            );
            SafeToken.safeTransfer(
                address(tokenAddress),
                address(msg.sender),
                amount * (10**tokenAddress.decimals())
            );
        }
    }

    function setPrice(address _baseToken, uint256 _price) external onlyOwner {
        prices[_baseToken] = _price;
    }
}
