// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract NewToken is ERC20("NewToken","NTT") {

    constructor(){
        _mint(msg.sender, 50000 * 10 ** 18);
    }
}