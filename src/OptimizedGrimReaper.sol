// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

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

contract OptimizedGrimReaper {
    address internal constant OWNER = 0x0000000000000000000000000000000000000003;

    /// @dev The Aave V3 Pool on Optimism
    address internal constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    /// @dev function approve(address spender, uint256 value)
    bytes4 internal constant ERC20_APPROVE_ID = 0x095ea7b3;
    /// @dev function liquidationCall(address collateralAsset,address debtAsset,address user,uint256 debtToCover,bool receiveAToken)
    bytes4 internal constant LIQUIDATION_CALL_ID = 0x00a718a9;

    fallback() external payable {
        assembly {
            // only the owner of this contract is allowed to call this function
            if iszero(eq(caller(), OWNER)) {
                // WGMI
                revert(3, 3)
            }

            // We don't have function signatures sweet saving EVEN MORE GAS

            // bytes20
            let col := shr(96, calldataload(0x00))
            // bytes20
            let debtAsset := shr(96, calldataload(0x14))
            // bytes20
            let user := shr(96, calldataload(0x28))
            // uint128
            let debtToCover := shr(128, calldataload(0x3c))

            // Call debtAsset.approve(pool, debtToCover)

            // approve function signature
            // 0x7c = 124 in decimal.
            mstore(0x7c, ERC20_APPROVE_ID)
            // pool
            mstore(0x80, POOL)
            // debtToCover
            mstore(0xa0, debtToCover)

            let s1 := call(sub(gas(), 5000), debtAsset, 0, 0x7c, 0x44, 0, 0)
            if iszero(s1) {
                // WGMI
                revert(3, 3)
            }
            // Call POOL.liquidationCall(collateralAsset, debtAsset, user, debtToCover, false)
            // liquidation function signature
            mstore(0x7c, LIQUIDATION_CALL_ID)
            mstore(0x80, col)
            mstore(0xa0, debtAsset)
            mstore(0xc0, user)
            mstore(0xe0, debtToCover)

            let s2 := call(sub(gas(), 5000), POOL, 0, 0x7c, 0x104, 0, 0)
            if iszero(s2) { revert(3, 3) }
        }
    }

    /// @notice Receive profits from contract
    function recoverERC20(address /* token */ ) public payable {
        assembly {
            // only the owner of this contract is allowed to call this function
            if iszero(eq(caller(), OWNER)) {
                // WGMI
                revert(3, 3)
            }

            let token := calldataload(0x04) // The token to recover.
            // Modified from Solidity's SafeTransferLib
            mstore(0x00, 0x70a08231) // Store the function selector of `balanceOf(address)`.
            mstore(0x20, address()) // Store the address of the current contract.
            // Read the balance, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                    staticcall(gas(), token, 0x1c, 0x24, 0x34, 0x20)
                )
            ) { revert(3, 3) }
            mstore(0x14, caller()) // Store the `to` argument.
            // ignore overflow/underflow check
            mstore(0x34, sub(mload(0x34), 1)) // The `amount` is already at 0x34.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) { revert(3, 3) }
            // mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
            stop() // Stop the execution.
        }
    }
}
