// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @dev https://github.com/orenyomtov/gas-meter/blob/main/src/GasMeter.sol

interface IGasMeter {
    function meterStaticCall(address, /* addr */ bytes memory /* data */ )
        external
        pure
        returns (uint256 gasUsed, bytes memory returnData);

    function meterCall(address, /* addr */ bytes memory /* data */ )
        external
        returns (uint256 gasUsed, bytes memory returnData);
}
