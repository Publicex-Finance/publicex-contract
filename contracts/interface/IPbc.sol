// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IErc20 } from "@pefish/solidity-lib/contracts/interface/IErc20.sol";

interface IPbc is IErc20 {

  function mintByPool(address _account, uint256 _amount) external returns (bool);

}
