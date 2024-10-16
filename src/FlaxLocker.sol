// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SFlax} from "./SFlax.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Vm} from "lib/forge-std/src/Test.sol";
struct Config {
    IERC20 flax;
    uint basisPointsBoost; //For every month locked, a 5% boost expressed in basis points
    uint sFlaxEarning_baseline; //1 ether => 1 unit per unit per minute staked (not typo)
    SFlax sFlax;
}

struct UserStakingInfo {
    uint timeRemaining; //converted to seconds
    uint weight; //basis_points multiplier. anything above 10_000 is boosted.
    uint lastUpdate;
    uint lockedFlax;
}

event SFlax_set(address indexed oldSFlax, address indexed newSFlax);

contract FlaxLocker is Ownable, ReentrancyGuard {
    Config public config;
    bool disabled;
    bool emergencyGlass;
    address vm_address;
    uint constant MONTH = 30 days;
    mapping(address => UserStakingInfo) public userStakingInfo;

    constructor(address vm) Ownable(msg.sender) {
        vm_address =vm;
    }

    modifier updateSFlaxEarnings(address sender) {
        updateAccounting(sender);
        _;
    }

    modifier enabled() {
        require(!disabled, "FlaxLocker has been disabled");
        _;
    }

    function breakEmergencyGlass() public onlyOwner {
        emergencyGlass = true;
    }

    function disable() public onlyOwner {
        require(emergencyGlass, "Call break emergency glass to disable");
        disabled = true;
    }

    function setBooster (address booster, bool live) public onlyOwner {
            config.sFlax.setApprovedBurner(booster,live);
    }

    function setConfig(
        address flax,
        address sFlax, //if zero, a new sFlax is instantiated
        uint basisPointsBoost,
        uint sFlaxEarning_baseline
    ) public onlyOwner {
        require(
            basisPointsBoost < 10_000,
            "basisPointsBoost must be basis point"
        );

        config.basisPointsBoost = basisPointsBoost;
        config.flax = IERC20(flax);
        config.sFlaxEarning_baseline = sFlaxEarning_baseline;
        if (sFlax == address(0)) {
            SFlax newSFlax = new SFlax();
            emit SFlax_set(address(config.sFlax), address(newSFlax));
            config.sFlax = newSFlax;
        } else if (sFlax != address(config.sFlax)) {
            emit SFlax_set(address(config.sFlax), sFlax);
            require(
                Ownable(sFlax).owner() == address(this),
                "SFlax ownership not transferred"
            );
            config.sFlax = SFlax(sFlax);
        }
    }

    function deposit(
        uint amount,
        uint durationInMonths
    ) public enabled updateSFlaxEarnings(msg.sender) nonReentrant {
        require(
            durationInMonths >= 1 && durationInMonths < 48,
            "invalid lock duration"
        );
        UserStakingInfo memory info = userStakingInfo[msg.sender];

        info.timeRemaining += durationInMonths * MONTH;
        info.timeRemaining = info.timeRemaining> 48 * MONTH?48*MONTH:info.timeRemaining;
        info.weight = (info.timeRemaining / (MONTH))*200;

        info.lockedFlax += amount;
        config.flax.transferFrom(msg.sender, address(this), amount);
        info.lastUpdate = vm_address==address(0)? block.timestamp:Vm(vm_address).getBlockTimestamp();
        userStakingInfo[msg.sender] = info;
    }

    //total withdrawal to minimize security surface area
    function withdraw() public enabled updateSFlaxEarnings(msg.sender) nonReentrant {
        UserStakingInfo memory info = userStakingInfo[msg.sender];
        require(info.timeRemaining == 0, "Flax still locked");
        config.flax.transfer(msg.sender, info.lockedFlax);
        info.lockedFlax = 0;
        info.weight = 0;
        info.lastUpdate = 0;
        userStakingInfo[msg.sender] = info;
    }

    function claimFor (address claimant) public enabled updateSFlaxEarnings(claimant) nonReentrant{
        //if you look very carefully, you'll see code in this function.
    }
   
    function transferToNewLocker(address newLocker) public onlyOwner {
        disabled = true;
        uint balance = config.flax.balanceOf(address(this));
        config.flax.transfer(newLocker, balance);
    }


    function updateAccounting(address sender) private {
        UserStakingInfo memory info = userStakingInfo[sender];

        if (info.lastUpdate == 0) {
            return;
        }
        uint timeSinceLastUpdate = (vm_address==address(0)? block.timestamp:Vm(vm_address).getBlockTimestamp()) - info.lastUpdate;
        uint minutesSinceLastUpdate = (timeSinceLastUpdate) / (60);
        uint unweighted_sFlaxEarned = (info.lockedFlax *
            config.sFlaxEarning_baseline *
            minutesSinceLastUpdate) / (1 ether);
        uint weightedEarnings = (unweighted_sFlaxEarned *
            (10_000 + info.weight)) / 10_000;

        config.sFlax.mint(sender, weightedEarnings);

        if (timeSinceLastUpdate > info.timeRemaining) {
            info.timeRemaining = 0;
        } else info.timeRemaining -= timeSinceLastUpdate;
        userStakingInfo[sender] = info;
    }
}
