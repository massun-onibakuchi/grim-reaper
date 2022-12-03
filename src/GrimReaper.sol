// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

interface IERC20Like {
    function balanceOf(address account) external returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @title Aave V3 Pool
interface IPoolLike {
    /**
     * @notice Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken True if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     *
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;
}

library SafeERC20 {
    /// @dev relaxing the requirement on the return value: the return value is optional

    // CODE 5: safeTransfer failed
    function safeTransfer(IERC20Like token, address to, uint256 value) internal {
        (bool s,) = address(token).call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, value));
        require(s, "5");
    }
}

contract GrimReaper {
    using SafeERC20 for IERC20Like;

    error OnlyOwner();

    address internal constant OWNER = 0x0000000000000000000000000000000000000003;

    /// @dev The Aave V3 Pool on Optimism
    address internal constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    /// TODO: change this to the fallback function
    function execute(address collateralAsset, address debtAsset, address user, uint256 debtToCover) external payable {
        // only the owner of this contract is allowed to call this function
        if (msg.sender != OWNER) revert OnlyOwner();
        IERC20Like(debtAsset).approve(POOL, debtToCover); // this may not properly work for some kind of tokens like USDT
        // allow the POOL contract to transfer up to `debtToCover` amount of `debtAsset` from the caller's account
        IPoolLike(POOL).liquidationCall(collateralAsset, debtAsset, user, debtToCover, false);
    }

    /// @notice Receive profits from contract
    function recoverERC20(address token) public {
        if (msg.sender != OWNER) revert OnlyOwner();
        // ignore overflow/underflow check
        unchecked {
            // leave a small amount of "dust" in the contract to save on gas costs
            IERC20Like(token).safeTransfer(msg.sender, IERC20Like(token).balanceOf(address(this)) - 1);
        }
    }
}
