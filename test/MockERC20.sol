// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20("Token", "TKN") {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
