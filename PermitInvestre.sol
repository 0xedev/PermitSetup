// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PermitAutoBuyContract
 * @dev Contract that accepts EIP-2612 permits and executes swaps atomically
 * 
 * Users grant permits to this contract, then the contract:
 * 1. Uses permit to transfer USDC from user
 * 2. Approves DEX router for USDC spending
 * 3. Executes swap via router
 * 4. Sends received tokens directly to user
 * 
 * This eliminates the need for backend wallet to hold user funds
 */
contract PermitAutoBuyContract is Ownable, Pausable, ReentrancyGuard {
    
    IERC20 public immutable usdc;
    
    // Trusted DEX routers
    address public constant KYBERSWAP_ROUTER = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
    
    // User daily spending tracking
    mapping(address => mapping(uint256 => uint256)) public dailySpent; // user => day => amount
    mapping(address => uint256) public userDailyLimit;
    mapping(address => uint256) public likeAmount;
    mapping(address => uint256) public recastAmount;
    
    // Events
    event PermitAutoBuyExecuted(
        address indexed user,
        address indexed tokenOut,
        uint256 usdcAmount,
        uint256 tokensReceived,
        string actionType
    );
    
    event UserLimitsSet(
        address indexed user,
        uint256 dailyLimit,
        uint256 likeAmount,
        uint256 recastAmount
    );
    
    constructor(address _usdc, address owner) Ownable(owner) {
        usdc = IERC20(_usdc);
    }
    
    /**
     * @dev Execute auto-buy using EIP-2612 permit
     * @param user User's wallet address
     * @param usdcAmount Amount of USDC to spend
     * @param deadline Permit deadline
     * @param v,r,s Permit signature components
     * @param swapData Encoded swap transaction data for DEX router
     * @param actionType "like" or "recast"
     */
    function executePermitAutoBuy(
        address user,
        uint256 usdcAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata swapData,
        string calldata actionType
    ) external onlyOwner whenNotPaused nonReentrant {
        
        // Validate action type and amount limits
        uint256 today = block.timestamp / 86400; // days since epoch
        uint256 maxAmount;
        
        bytes32 actionHash = keccak256(bytes(actionType));
        if (actionHash == keccak256(bytes("like"))) {
            require(likeAmount[user] > 0, "Like amount not set");
            maxAmount = likeAmount[user];
        } else if (actionHash == keccak256(bytes("recast"))) {
            require(recastAmount[user] > 0, "Recast amount not set");
            maxAmount = recastAmount[user];
        } else {
            revert("Invalid action type");
        }
        
        require(usdcAmount <= maxAmount, "Amount exceeds action limit");
        
        // Check daily limit
        uint256 limit = userDailyLimit[user];
        require(limit > 0, "Daily limit not set");
        require(dailySpent[user][today] + usdcAmount <= limit, "Daily limit exceeded");
        
        // Execute permit to allow this contract to spend user's USDC
        IERC20Permit(address(usdc)).permit(
            user,
            address(this),
            usdcAmount,
            deadline,
            v,
            r,
            s
        );
        
        // Transfer USDC from user to this contract
        require(
            usdc.transferFrom(user, address(this), usdcAmount),
            "USDC transfer failed"
        );
        
        // Approve router to spend USDC
        require(
            usdc.approve(KYBERSWAP_ROUTER, usdcAmount),
            "Router approval failed"
        );
        
        // Execute swap via router
        (bool success, bytes memory result) = KYBERSWAP_ROUTER.call(swapData);
        require(success, string(result));
        
        // Update daily spending
        dailySpent[user][today] += usdcAmount;
        
        // Note: Tokens are sent directly to user by the DEX router
        // We don't know the exact amount received, but that's tracked off-chain
        
        emit PermitAutoBuyExecuted(
            user,
            address(0), // We don't know the output token address from swapData
            usdcAmount,
            0, // We don't know exact tokens received
            actionType
        );
    }
    
    /**
     * @dev Set user limits and amounts
     */
    function setUserLimits(
        address user,
        uint256 dailyLimit,
        uint256 _likeAmount,
        uint256 _recastAmount
    ) external onlyOwner {
        userDailyLimit[user] = dailyLimit;
        likeAmount[user] = _likeAmount;
        recastAmount[user] = _recastAmount;
        
        emit UserLimitsSet(user, dailyLimit, _likeAmount, _recastAmount);
    }
    
    /**
     * @dev Get current daily spent amount
     */
    function getDailySpent(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 86400;
        return dailySpent[user][today];
    }
    
    /**
     * @dev Emergency functions
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Emergency token recovery
     */
    function emergencyRecovery(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
