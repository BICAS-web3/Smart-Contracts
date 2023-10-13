
pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.9/token/ERC20/ERC20.sol";

contract DraxToken is ERC20{
    constructor() ERC20("Drax", "DRAX"){
        _mint(msg.sender,10000000000000*10**18);
    }
}
