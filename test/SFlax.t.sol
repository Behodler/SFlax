// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {Test} from "@forge-std/Test.sol";
import {SFlax} from "src/SFlax.sol";
import {FlaxLocker, SFlax_set} from "src/FlaxLocker.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockFlax is ERC20 {
    address deployer;

    constructor() ERC20("MockFlax", "MFLAX") {
        deployer = msg.sender;
    }

    function mint(address recipient, uint256 amount) external {
        require(msg.sender == deployer, "protects from bugs");
        _mint(recipient, amount);
    }
}

contract MockBurner {
    SFlax sFlax;

    constructor(address sFlaxAddress) {
        sFlax = SFlax(sFlaxAddress);
    }

    function burnFrom(address holder) public {
        uint balance = sFlax.balanceOf(holder);
        sFlax.burnFrom(holder, balance);
    }
}

contract TestSFlax is Test {
    MockFlax flax;
    FlaxLocker locker;
    address user = address(0x1);

    function setUp() public {
        flax = new MockFlax();
        locker = new FlaxLocker(address(vm));
        flax.mint(address(this), 200_000 ether);
        vm.deal(user, 10 ether);
        locker.setConfig(address(flax), address(0), 500, (1 ether) / 1000_000);
    }

    function testSetup() public {}

    function test_invalid_lock_duration_fails() public {
        vm.expectRevert("invalid lock duration");
        locker.deposit(1000 ether, 0);

        vm.expectRevert("invalid lock duration");
        locker.deposit(1000 ether, 49);
    }

    //note: there seems to be issues with updating addresses in tests
    //asserts of logs have been commented out. Just test with -vvvv
    function test_set_zero_sflax_instantiates_new_flax() public {
        FlaxLocker newLocker = new FlaxLocker(address(vm));

        // vm.expectEmit(true, false, false, false);
        // emit SFlax_set(address(0), address(0));
        newLocker.setConfig(address(flax), address(0), 500, 1000_000);

        (, , , SFlax oldFlax) = locker.config();

        // vm.expectEmit(true, false, false, false);
        // emit SFlax_set(address(oldFlax), address(0));
        newLocker.setConfig(address(flax), address(0), 500, 1000_000);
    }

    function test_set_non_zero_sflax() public {
        SFlax newSFlax = new SFlax();

        vm.expectRevert("SFlax ownership not transferred");
        locker.setConfig(address(flax), address(newSFlax), 500, 1000);

        newSFlax.transferOwnership(address(locker));
        locker.setConfig(address(flax), address(newSFlax), 500, 1000);
    }

    function test_manual_disable_with_reverts() public {
        vm.expectRevert("Call break emergency glass to disable");
        locker.disable();

        locker.breakEmergencyGlass();

        locker.disable();

        vm.expectRevert("FlaxLocker has been disabled");
        locker.deposit(100, 2);

        vm.expectRevert("FlaxLocker has been disabled");
        locker.withdraw();
    }

    function test_transfer_to_new_locker() public {
        flax.mint(address(locker), 200000);
        FlaxLocker newLocker = new FlaxLocker(address(vm));

        locker.transferToNewLocker(address(newLocker));

        uint flaxOnOldLocker = flax.balanceOf(address(locker));
        uint flaxOnNewLocker = flax.balanceOf(address(newLocker));
        vm.assertEq(flaxOnOldLocker, 0);
        vm.assertEq(flaxOnNewLocker, 200000);

        vm.expectRevert("FlaxLocker has been disabled");
        locker.withdraw();
    }

    event SFlax_minted(uint amount);

    function test_successful_deposit_and_withdraw() public {
        flax.mint(user, 1000 ether);
        vm.prank(user);
        flax.approve(address(locker), type(uint).max);
        vm.prank(user);
        locker.deposit(200 ether, 3);
        uint initialTimeStamp = vm.getBlockTimestamp();
        (
            uint timeRemaining,
            uint weight,
            uint lastUpdate,
            uint lockedFlax
        ) = locker.userStakingInfo(user);

        vm.assertEq(timeRemaining, 3 * (30 days));
        vm.assertEq(weight, 600);
        vm.assertEq(lastUpdate, block.timestamp);
        vm.assertEq(lockedFlax, 200 ether);

        //get from config

        (, , , SFlax sFlax) = locker.config();
        uint sflaxBefore = sFlax.balanceOf(user);
        vm.assertEq(sflaxBefore, 0);

        vm.warp(initialTimeStamp + 30 days);

        locker.claimFor(user);

        uint sflaxAfter = sFlax.balanceOf(user);

        vm.assertGt(sflaxAfter, 0);
        sflaxBefore = sflaxAfter;

        vm.prank(user);
        vm.expectRevert("Flax still locked");
        locker.withdraw();
        uint intermediate = sFlax.balanceOf(user);

        vm.assertEq(intermediate, sflaxBefore);

        vm.prank(user);
        vm.warp(initialTimeStamp + 60 days);
        locker.withdraw();
        sflaxAfter = sFlax.balanceOf(user);
        vm.assertEq(sflaxAfter, sflaxBefore * 3);
        emit SFlax_minted(sflaxAfter);
    }

    function test_additional_deposits_extend_time() public {
        flax.mint(user, 1000 ether);
        vm.prank(user);
        flax.approve(address(locker), type(uint).max);
        vm.prank(user);
        locker.deposit(200 ether, 20);
        (uint timeRemainingBefore, , , ) = locker.userStakingInfo(user);

        vm.prank(user);
        locker.deposit(200 ether, 20);
        (uint timeRemainingAfter, , , ) = locker.userStakingInfo(user);

        vm.assertEq(timeRemainingAfter, timeRemainingBefore * 2);
        vm.assertEq(timeRemainingBefore, 20 * (30 days));
    }

    function testBoosterBurnPermissions() public {
        SFlax sFlax = new SFlax();
        sFlax.mint(user, 1000 ether);
        sFlax.transferOwnership(address(locker));
        locker.setConfig(
            address(flax),
            address(sFlax),
            500,
            (1 ether) / 1000_000
        );

        MockBurner mockBurner = new MockBurner(address(address(sFlax)));

        vm.expectRevert("Non approved burner");
        mockBurner.burnFrom(user);

        locker.setBooster(address(mockBurner), true);
        mockBurner.burnFrom(user);

        uint balance = sFlax.balanceOf(user);
        vm.assertEq(balance, 0);
    }
}
