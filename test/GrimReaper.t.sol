// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Test.sol";
import {IGasMeter} from "./IGasMeter.sol";

import {GrimReaper} from "../src/GrimReaper.sol";
import {OptimizedGrimReaper, OptimizedGrimReaperL2} from "../src/OptimizedGrimReaper.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockPool} from "./MockPool.sol";

abstract contract GrimReaperBaseTest is Test {
    /// @dev Forked from: https://github.com/orenyomtov/gas-meter/blob/main/src/GasMeter.sol
    bytes constant GAS_METER_RUNTIME_CODE =
        hex"608060405234801561001057600080fd5b50600436106100365760003560e01c80632b73eefa1461003b578063abe770f21461003b575b600080fd5b61004e6100493660046100b1565b610065565b60405161005c929190610181565b60405180910390f35b600060606101d861007281565b60006040518060e0016040528060ba81526020016101d860ba9139805197909650945050505050565b634e487b7160e01b600052604160045260246000fd5b600080604083850312156100c457600080fd5b82356001600160a01b03811681146100db57600080fd5b9150602083013567ffffffffffffffff808211156100f857600080fd5b818501915085601f83011261010c57600080fd5b81358181111561011e5761011e61009b565b604051601f8201601f19908116603f011681019083821181831017156101465761014661009b565b8160405282815288602084870101111561015f57600080fd5b8260208601602083013760006020848301015280955050505050509250929050565b82815260006020604081840152835180604085015260005b818110156101b557858101830151858201606001528201610199565b506000606082860101526060601f19601f83011685010192505050939250505056fe5b60003560e01c8063abe770f2146100296101d8015780632b73eefa146100716101d80157600080fd5b36600460003760005131505a6000600060405160606000515afa905a60800190036000523d600060603e6100606101d801573d6060fd5b60406020523d6040523d6060016000f35b36600460003760005131505a600060006040516060346000515af1905a60820190036000523d600060603e6100a96101d801573d6060fd5b60406020523d6040523d6060016000f3a2646970667358221220439eb155e23107a428910378fc720256ab7c361a4f8bd97415d3f321fecb459c64736f6c63430008130033";

    address constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant owner = 0x00000dB7402a2Ae8E49369B46C0ED999bA024Ac7;

    GrimReaper public reaper;

    MockERC20 collateral = MockERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MockERC20 debt;
    MockPool pool = MockPool(POOL);

    uint256 liquidationBonus = 10000;

    /// @dev Setup the testing environment.
    function setUp() public virtual {
        MockERC20 _token = new MockERC20();
        vm.etch(address(collateral), address(_token).code);
        debt = new MockERC20();
        MockPool _pool = new MockPool();
        vm.etch(POOL, address(_pool).code);

        _deployGrimReaper();

        // set up the pool
        pool.setLiquidationBonus(liquidationBonus);
        pool.setLiquidation(true);
        // fund
        collateral.mint(POOL, liquidationBonus);
        debt.mint(address(reaper), 1000);

        vm.label(address(collateral), "collateral");
        vm.label(address(debt), "debt");
        vm.label(POOL, "pool");
        vm.label(address(reaper), "GrimReaper");
        vm.label(address(0xbabe), "babe");
    }

    function _deployGrimReaper() internal virtual;

    function testLiquidate() public {
        testFuzz_Liquidate(1000e18, address(0xbabe));
    }

    function testFuzz_Liquidate(uint256 amount, address user) public {
        vm.assume(amount < type(uint128).max);
        deal(address(debt), address(reaper), amount, true);

        vm.expectCall(
            POOL, abi.encodeWithSelector(MockPool.liquidationCall.selector, collateral, debt, user, amount, false)
        );
        _callLiquidate(owner, address(collateral), address(debt), user, amount);

        assertEq(debt.balanceOf(address(reaper)), 0);
        assertEq(collateral.balanceOf(address(reaper)), liquidationBonus);
    }

    function _callLiquidate(address caller, address _col, address _debt, address _user, uint256 _debtToCover)
        public
        virtual
    {
        vm.prank(caller);
        (bool s,) = address(reaper).call(getLiquidationPayload(_col, _debt, _user, _debtToCover));
        require(s, "liquidation failed");
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        view
        virtual
        returns (bytes memory payload)
    {
        payload = abi.encodeCall(reaper.execute, (_col, _debt, _user, _debtToCover));
    }

    function testGas_Liquidate() public virtual {
        deal(address(debt), address(reaper), 10_000e18, true);
        vm.etch(address(owner), GAS_METER_RUNTIME_CODE);
        IGasMeter gasMeter = IGasMeter(owner); // Only owner can call liquidate function

        (uint256 gasUsed,) = gasMeter.meterCall(
            address(reaper), getLiquidationPayload(address(collateral), address(debt), address(0xbabe), 1000e18)
        );
        console.log("gas measured: %s", gasUsed);
    }

    function testRevertIfLiquidationFail() public {
        pool.setLiquidation(false);
        vm.expectRevert("liquidation failed");
        this._callLiquidate(owner, address(collateral), address(debt), address(0xcafe), 1000);
    }

    function testRecoverERC20() public virtual {
        uint256 balance = 10000;
        deal(address(debt), address(reaper), balance, true);

        uint256 _before = gasleft();
        vm.prank(owner);
        reaper.recoverERC20(address(debt));
        console2.log("gas usage: ", _before - gasleft());

        assertEq(debt.balanceOf(address(reaper)), 1);
        assertEq(debt.balanceOf(owner), balance - 1);
    }

    function testOnlyOwner(address non_user) public {
        vm.assume(non_user != owner);

        vm.expectRevert();
        _callLiquidate(non_user, address(collateral), address(debt), address(0xcafe), 1000);

        vm.expectRevert();
        vm.prank(non_user);
        reaper.recoverERC20(address(collateral));
    }
}

contract GrimReaperSolTest is GrimReaperBaseTest {
    function _deployGrimReaper() internal override {
        reaper = new GrimReaper();
    }
}

contract OptimizedGrimReaperSolTest is GrimReaperBaseTest {
    function _deployGrimReaper() internal virtual override {
        reaper = GrimReaper(address(new OptimizedGrimReaper()));
    }

    function _callLiquidate(address caller, address _col, address _debt, address _user, uint256 _debtToCover)
        public
        override
    {
        bytes memory payload = getLiquidationPayload(_col, _debt, _user, _debtToCover);

        vm.prank(caller);
        (bool success,) = address(reaper).call(payload);
        require(success, "liquidation failed");
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        pure
        virtual
        override
        returns (bytes memory payload)
    {
        payload = abi.encodePacked(_col, _debt, _user, uint128(_debtToCover));
    }

    function testRecoverERC20() public virtual override {
        uint256 balance = 10000;
        deal(address(debt), address(reaper), balance, true);

        uint256 _before = gasleft();
        vm.prank(owner);
        (bool success,) =
            address(reaper).call(abi.encodeWithSelector(OptimizedGrimReaper.execute_44g58pv.selector, address(debt)));
        require(success, "recoverERC20 failed");
        console2.log("gas usage: ", _before - gasleft());

        assertEq(debt.balanceOf(address(reaper)), 1);
        assertEq(debt.balanceOf(owner), balance - 1);
    }
}

contract Deployer {
    constructor(bytes memory runtimeCode, bytes memory table) {
        bytes memory code = bytes.concat(runtimeCode, table);
        assembly {
            return(add(code, 32), mload(code))
        }
    }
}

function getGrimReaperL2LiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
    pure
    returns (bytes memory payload)
{
    uint8 id;
    if (_col == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) {
        id = 0;
    } else if (_col == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) {
        id = 1;
    } else if (_col == 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0) {
        id = 2;
    } else {
        revert("invalid collateral");
    }
    payload = abi.encodePacked(_debt, uint8(id), _user, uint128(_debtToCover));
}

/// @dev abi.encodePacked(WETH, USDC, LUSD);
bytes constant COLLATERAL_ASSET_TABLE =
    hex"C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB485f98805A4E8be255a32880FDeC7F6728C6568bA0";

contract OptimizedGrimReaperSolL2Test is OptimizedGrimReaperSolTest {
    function _deployGrimReaper() internal override {
        bytes memory solidityCode = type(OptimizedGrimReaperL2).runtimeCode;
        reaper = GrimReaper(address(new Deployer(solidityCode, COLLATERAL_ASSET_TABLE)));
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        pure
        override
        returns (bytes memory payload)
    {
        payload = getGrimReaperL2LiquidationPayload(_col, _debt, _user, _debtToCover);
    }
}

contract GrimReaperHuffTest is OptimizedGrimReaperSolTest {
    function _deployGrimReaper() internal virtual override {
        reaper = GrimReaper(HuffDeployer.deploy("GrimReaper"));
    }

    function testRecoverERC20() public override {
        uint256 balance = 10000;
        deal(address(debt), address(reaper), balance, true);

        uint256 _before = gasleft();
        vm.prank(owner);
        (bool success,) = address(reaper).call(abi.encode(debt));
        console2.log("gas usage: ", _before - gasleft());
        require(success, "recoverERC20 failed");

        assertEq(debt.balanceOf(address(reaper)), 1);
        assertEq(debt.balanceOf(owner), balance - 1);
    }
}

contract GrimReaperHuffL2Test is GrimReaperHuffTest {
    /// @dev abi.encode(WETH, USDC, LUSD);
    bytes constant COLLATERAL_ASSET_TABLE_HUFF = abi.encode(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
        0x5f98805A4E8be255a32880FDeC7F6728C6568bA0
    );

    function _deployGrimReaper() internal virtual override {
        bytes memory code = HuffDeployer.deploy("GrimReaperL2").code;
        reaper = GrimReaper(address(new Deployer(code, COLLATERAL_ASSET_TABLE_HUFF)));
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        pure
        override
        returns (bytes memory payload)
    {
        payload = getGrimReaperL2LiquidationPayload(_col, _debt, _user, _debtToCover);
    }
}
