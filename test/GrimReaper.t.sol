// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Test.sol";

import {GrimReaper} from "../src/GrimReaper.sol";
import {OptimizedGrimReaper} from "../src/OptimizedGrimReaper.sol";
import "./MockERC20.sol";
import "./MockPool.sol";

abstract contract GrimReaperBaseTest is Test {
    address constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant owner = 0x0000000000000000000000000000000000000003;

    GrimReaper public reaper;

    MockERC20 collateral;
    MockERC20 debt;
    MockPool pool = MockPool(POOL);

    uint256 liquidationBonus = 10000;

    /// @dev Setup the testing environment.
    function setUp() public virtual {
        collateral = new MockERC20();
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
    }

    function _deployGrimReaper() internal virtual;

    function testLiquidate() public {
        testLiquidate(1000e18, address(0xbabe));
    }

    function testLiquidate(uint256 amount, address user) public {
        vm.assume(amount < type(uint128).max);
        deal(address(debt), address(reaper), amount, true);

        vm.expectCall(
            POOL, abi.encodeWithSelector(MockPool.liquidationCall.selector, collateral, debt, user, amount, false)
        );
        vm.prank(owner);
        _callLiquidate(address(collateral), address(debt), user, amount);

        assertEq(debt.balanceOf(address(reaper)), 0);
        assertEq(collateral.balanceOf(address(reaper)), liquidationBonus);
    }

    function _callLiquidate(address _col, address _debt, address _user, uint256 _debtToCover) internal virtual {
        uint256 _before = gasleft();
        reaper.execute(_col, _debt, _user, _debtToCover);
        uint256 _after = gasleft();
        console2.log("Gas used: ", (_before - _after));
    }

    function testRevertIfLiquidationFail() public {
        pool.setLiquidation(false);
        vm.expectRevert();
        vm.prank(owner);
        _callLiquidate(address(collateral), address(debt), address(0xcafe), 1000);
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
        vm.prank(non_user);
        _callLiquidate(address(collateral), address(debt), address(0xcafe), 1000);

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

    function _callLiquidate(address _col, address _debt, address _user, uint256 _debtToCover) internal override {
        bytes memory payload = getLiquidationPayload(_col, _debt, _user, _debtToCover);

        uint256 _before = gasleft();
        (bool success,) = address(reaper).call(payload);
        uint256 _after = gasleft();
        console2.log("Gas used: ", (_before - _after));
        require(success, "liquidation failed");
    }

    function getLiquidationPayload(address _col, address _debt, address _user, uint256 _debtToCover)
        internal
        pure
        returns (bytes memory payload)
    {
        payload = abi.encodePacked(_col, _debt, _user, uint128(_debtToCover));
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
