// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPool {
    uint256 public bonus = 1.1 * 1e18;
    bool public liquidatable = true;

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external {
        require(receiveAToken == false, "Not Implemented");
        require(liquidatable, "Liquidation failed");

        SafeERC20.safeTransferFrom(IERC20(debtAsset), msg.sender, address(this), debtToCover);
        SafeERC20.safeTransfer(IERC20(collateralAsset), msg.sender, bonus);
    }

    function setLiquidation(bool _liquidatable) public {
        liquidatable = _liquidatable;
    }

    function setLiquidationBonus(uint256 _bonus) public {
        bonus = _bonus;
    }
}
