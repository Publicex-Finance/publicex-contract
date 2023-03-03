// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeToken} from "@pefish/solidity-lib/contracts/library/SafeToken.sol";
import {IErc20} from "@pefish/solidity-lib/contracts/interface/IErc20.sol";

contract SendPbc {
    IErc20 public tokenAddress;

    constructor(address _tokenAddress) {
        tokenAddress = IErc20(_tokenAddress);
    }

    function send(address[] memory addrs, uint256[] memory amount) external {
        require(
            addrs.length == amount.length,
            "SendPbc::send:: length must be same"
        );
        require(
            addrs.length > 0,
            "SendPbc::send:: length must be larger than 0"
        );

        for (uint256 i = 0; i < addrs.length; i++) {
            SafeToken.safeTransferFrom(
                address(tokenAddress),
                msg.sender,
                addrs[i],
                amount[i]
            );
        }
    }
}
