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
    address internal constant OWNER = 0x00000dB7402a2Ae8E49369B46C0ED999bA024Ac7;

    /// @dev The Aave V3 Pool on Optimism
    address internal constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    /// @dev function approve(address spender, uint256 value)
    bytes4 internal constant ERC20_APPROVE_ID = 0x095ea7b3;
    /// @dev function liquidationCall(address collateralAsset,address debtAsset,address user,uint256 debtToCover,bool receiveAToken)
    bytes4 internal constant LIQUIDATION_CALL_ID = 0x00a718a9;

    /// @dev Dispatching function calls manually saves tiny gas. It's not much worth it.
    fallback() external payable virtual {
        assembly {
            // only the owner of this contract is allowed to call this function
            if iszero(eq(caller(), OWNER)) { revert(0, 0) }

            // We don't have function signatures sweet saving EVEN MORE GAS

            // bytes20
            let col := shr(0x60, calldataload(0x00))
            // bytes20
            let debtAsset := shr(0x60, calldataload(0x14))
            // bytes20
            let user := shr(0x60, calldataload(0x28))
            // uint128
            let debtToCover := shr(0x80, calldataload(0x3c))

            // Call debtAsset.approve(pool, debtToCover)

            // approve function signature
            mstore(0x14, POOL)
            mstore(0x34, add(debtToCover, 0x01))
            mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
            let s1 := call(gas(), debtAsset, 0, 0x10, 0x44, 0x00, 0x00) // NOTE: Ignore the return data. We don't care about `approve`'s return value.
            if iszero(s1) { revert(0, 0) }
            // Call POOL.liquidationCall(collateralAsset, debtAsset, user, debtToCover, false)
            // liquidation function signature
            mstore(0x14, col)
            mstore(0x34, debtAsset)
            mstore(0x00, 0x00a718a9000000000000000000000000)
            mstore(0x54, user)
            mstore(0x74, debtToCover)

            let s2 := call(gas(), POOL, 0, 0x10, 0xa4, 0x00, 0x00)
            if iszero(s2) { revert(0, 0) }
        }
    }

    /// @notice Receive profits from contract
    /// @dev Function signature matches `execute_44g58pv()` = 0x00000000. Remove calldatasize check inserted by compiler.
    function execute_44g58pv( /* address token */ ) external payable {
        assembly {
            // only the owner of this contract is allowed to call this function
            if iszero(eq(caller(), OWNER)) { revert(0, 0) }

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
            ) { revert(0, 0) }
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
            ) { revert(0, 0) }
        }
    }
}

/// @notice Supports only 3 collateral assets
contract OptimizedGrimReaperL2 is OptimizedGrimReaper {
    uint256 constant COLLATERAL_ASSETS_TABLE_OFFSET = 0x0C + 0x14 * 3; // 0x0C +0x14 * [number of supported collateral assetss]

    /// @dev At deployment, the table of collateral assets must be appended to the runtime code of this contract
    /// `bytes.concat(type(OptimizedGrimReaperV2).runtimeCode, collateralAssetsTable)`
    /// where `collateralAssetsTable` is a table of collateral assets to be used in the liquidation call
    /// The table must be in the format of: `abi.encodePacked(address[] collateralAssets)`
    constructor() {}

    /// @custom:param data Custom encoded data for `liquidationCall`
    /// @dev abi.encodePacked(address _debt, uint8 collateralId, address _user, uint128 _debtToCover)
    /// where `collateralId` is the index of the collateral asset in the table appended to the runtime code on deployment
    fallback() external payable override {
        assembly {
            // only the owner of this contract is allowed to call this function
            if iszero(eq(caller(), OWNER)) { revert(0, 0) }

            // We don't have function signatures sweet saving EVEN MORE GAS

            let debtAsset := shr(0x58, calldataload(0x00)) // bytes21 (address debtAsset, bytes1 collateralId)
            let collateralId := and(debtAsset, 0xff)
            debtAsset := shr(0x08, debtAsset) // Remove the last byte and get the address
            // bytes20
            let user := shr(0x60, calldataload(0x15))
            // uint128
            let debtToCover := shr(0x80, calldataload(0x29))

            // Call debtAsset.approve(pool, debtToCover)

            // approve function signature
            mstore(0x14, POOL)
            mstore(0x34, add(debtToCover, 0x01))
            mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
            let s1 := call(gas(), debtAsset, 0, 0x10, 0x44, 0x00, 0x00) // NOTE: Ignore the return data. We don't care about `approve`'s return value.
            if iszero(s1) { revert(0, 0) }

            // Call POOL.liquidationCall(collateralAsset, debtAsset, user, debtToCover, false)

            // Copy the collateral asset from the table
            codecopy(0x14, add(sub(codesize(), COLLATERAL_ASSETS_TABLE_OFFSET), mul(collateralId, 0x14)), 0x20)
            mstore(0x34, debtAsset)
            mstore(0x00, 0x00a718a9000000000000000000000000)
            mstore(0x54, user)
            mstore(0x74, debtToCover)

            let s2 := call(gas(), POOL, 0, 0x10, 0xa4, 0x00, 0x00)
            if iszero(s2) { revert(0, 0) }
        }
    }
}
