// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockETH
 * @notice Mock ETH token for testnet (wrapped ETH simulation)
 * @dev Anyone can mint unlimited tokens for testing purposes
 */
contract MockETH is ERC20, Ownable {
    
    constructor() ERC20("Mock Ethereum", "ETH") Ownable(msg.sender) {
        // Mint 10,000 ETH to deployer for initial testing
        _mint(msg.sender, 10_000 * 10**18);
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
     * @param amount Amount in whole ETH (will be multiplied by 10^18)
     */
    function faucet(uint256 amount) external {
        _mint(msg.sender, amount * 10**18);
    }
    
    /**
     * @notice Get 1 ETH for free (testnet faucet)
     */
    function getFreeTokens() external {
        _mint(msg.sender, 1 * 10**18);
    }
}
