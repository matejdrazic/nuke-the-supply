// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Imports
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ICBMToken is ERC20Burnable, Ownable {

    // Constructor for the ICBM token
    constructor(string memory name_, string memory symbol_, uint256 totalSupply_, address owner_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {
        // Mint initial supply to the deployer so they can initialize the Uniswap trading pair
        _mint(_msgSender(), totalSupply_);
    }

    // Function to burn tokens
    function burn(uint256 amount) public override(ERC20Burnable) onlyOwner {
        super.burn(amount);
    }

    // Function to burn tokens from a specific account
    function burnFrom(address account, uint256 amount) public override(ERC20Burnable) onlyOwner {
        super.burnFrom(account, amount);
    }
}
