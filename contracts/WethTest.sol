// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract WethTest is ERC20 {
  constructor(uint256 initialSupply) ERC20("Weth Test", "WETH-T") {
    _mint(msg.sender, initialSupply);
  }
}
