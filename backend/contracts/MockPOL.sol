// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockPOL
 * @notice Mock POL (Polygon) token for testnet
 * @dev Anyone can mint unlimited tokens for testing purposes
 */
contract MockPOL is ERC20, Ownable {
    
    constructor() ERC20("Mock Polygon", "POL") Ownable(msg.sender) {
        // Mint 1,000,000 POL to deployer for initial testing
        _mint(msg.sender, 1_000_000 * 10**18);
    }
    
    /**
     * @notice Mint tokens to any address (for testing)
     * @param to Address to receive tokens
     * @param amount Amount to mint (in wei, 18 decimals)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    /**
     * @notice Mint tokens to yourself (convenience function)
     * @param amount Amount in whole POL (will be multiplied by 10^18)
     */
    function faucet(uint256 amount) external {
        _mint(msg.sender, amount * 10**18);
    }
    
    /**
     * @notice Get 1000 POL for free (testnet faucet)
     */
    function getFreeTokens() external {
        _mint(msg.sender, 1000 * 10**18);
    }
}
