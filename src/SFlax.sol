// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

///@notice Reward token for staking Flax. Instantiated by CoreStaker. Burnt on usage
contract SFlax is Ownable, ERC20 {
    mapping(address => bool) public approvedBurners;

    constructor() Ownable(msg.sender) ERC20("Staked Flax", "SFlax") {}

    function mint(address recipient, uint amount) public onlyOwner {
        _mint(recipient, amount);
    }

    function burn(uint amount) public onlyOwner {
        _burn(msg.sender, amount);
    }

    function burnFrom(address holder, uint amount) public {
        require(approvedBurners[msg.sender], "Non approved burner");
        _burn(holder, amount);
    }

    function setApprovedBurner(address burner, bool canBurn) public onlyOwner {
        approvedBurners[burner] = canBurn;
    }
}
