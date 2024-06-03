// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Test.sol";

import {GrimReaper} from "../src/GrimReaper.sol";
import {OptimizedGrimReaper, OptimizedGrimReaperV2} from "../src/OptimizedGrimReaper.sol";
import "./MockERC20.sol";
import "./MockPool.sol";

abstract contract GrimReaperBaseTest is Test {
    address constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant owner = 0x0000000000000000000000000000000000000003;

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
        uint256 _before = gasleft();
        vm.prank(caller);
        (bool s,) = address(reaper).call(abi.encodeCall(reaper.execute, (_col, _debt, _user, _debtToCover)));
        uint256 _after = gasleft();
        console2.log("Gas used: ", (_before - _after));
        require(s, "ExpectRevert: liquidation failed");
    }

    function testRevertIfLiquidationFail() public {
        pool.setLiquidation(false);
        vm.expectRevert("ExpectRevert: liquidation failed");
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

        uint256 _before = gasleft();
        vm.prank(caller);
        (bool success,) = address(reaper).call(payload);
        uint256 _after = gasleft();
        console2.log("Gas used: ", (_before - _after));
        require(success, "ExpectRevert: liquidation failed");
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        pure
        virtual
        returns (bytes memory payload)
    {
        payload = abi.encodePacked(_col, _debt, _user, uint128(_debtToCover));
    }
}

contract Deployer {
    constructor(bytes memory table) {
        bytes memory solidityCode = type(OptimizedGrimReaperV2).runtimeCode;
        bytes memory code = bytes.concat(solidityCode, table);
        assembly {
            return(add(code, 32), mload(code))
        }
    }
}

contract OptimizedGrimReaperSolV2Test is OptimizedGrimReaperSolTest {
    /// @dev abi.encodePacked(WETH, USDC, LUSD);
    bytes constant COLLATERAL_ASSET_TABLE =
        hex"C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB485f98805A4E8be255a32880FDeC7F6728C6568bA0";

    function _deployGrimReaper() internal override {
        reaper = GrimReaper(address(new Deployer(COLLATERAL_ASSET_TABLE)));
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        pure
        override
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
