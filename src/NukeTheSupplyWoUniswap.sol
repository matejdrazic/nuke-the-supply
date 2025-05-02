// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Imports
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; - baca mi error kad je ovo aktivno, valjda jer vec ima implementacija u WeaponsMarket ugovoru
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Import ICBM & Warhead tokens (& WeaponsMarket)
import "./ICBMToken.sol";
import "./WarheadToken.sol";
import "./WeaponsMarket.sol";

contract NukeTheSupply is Ownable {
    using SafeERC20 for IERC20;

    // Tokens used in contract
    ICBMToken public ICBM;
    WarheadToken public Warhead;
    address public weaponsMarket; // State variable for WeaponsMarket contract address

    // Token supply values - there were changes in WH supply, operations phase is now 100 days, default sell is 3.5M 
    uint256 public constant ICBM_TOKEN_TOTAL_SUPPLY = 500_000_000 ether; // 500 million
    uint256 public constant INITIAL_WARHEAD_TOKEN_SUPPLY = 1_000_000 ether; // a million
    uint256 public NTS_CONTRACT_ICBM_BALANCE = 350_000_000 ether; // 350 million
    uint256 public constant DAILY_ICBM_SELL_AMOUNT = 3_500_000 ether; // 2.5 million per day

    // Token values
    uint256 public totalArmedICBMAmount; // Total amount of user supplied tokens in "ARM" state
    uint256 public totalICBMTokensBurned; // Total amount of ICBM tokens burned by users with "nuke" function, since deployment
    uint256 public totalICMBTokensSold; // Total amount of ICBM tokens sold by this contract, since deployment
    uint256 public day; // Day counter variable - counting since deployment
    uint256 public deploymentTimestamp; // Used to set conditions for the first call to the sell function and contract phase control
    uint256 public nextSellTimestamp; // Used to enforce delay between subsequent sell calls
    uint256 public constant PREPARATION_DURATION = 48 hours; // Change to 2 minutes for testing purposes
    uint256 public constant OPERATIONS_DURATION = 100 days; // Time period during which the contract is selling ICBM tokens
    uint256 public constant ARM_DURATION = 24 hours; // Time period during which ICBM tokens are armed
    uint256 public constant SELL_INTERVAL = 24 hours; // Time period between sell functions

    // Structs and mapping for user's batches of armed ICBM tokens
    struct ArmBatch {
        uint256 amount;
        uint256 endTime;
    }

    mapping(address => ArmBatch[]) public userArmBatches;

    // EVENTS
    event Armed(address indexed user, uint256 amount, uint256 endTime);
    event Nuked(address indexed user, uint256 icbmAmount, uint256 burnedAmount, uint256 whMinted);
    event SoldToWeaponsMarket(address indexed weaponsMarket, uint256 amount);

    // MODIFIER
    modifier inOperationsPhase() {
        require(block.timestamp >= deploymentTimestamp + PREPARATION_DURATION, "Operations phase not started");
        _;
    }

     constructor(address owner_) Ownable(owner_) {
        deploymentTimestamp = block.timestamp;
        day = 1;
        ICBM = new ICBMToken("ICBM", "ICBM", ICBM_TOKEN_TOTAL_SUPPLY, address(this));
        Warhead = new WarheadToken("Warhead", "WH", INITIAL_WARHEAD_TOKEN_SUPPLY, address(this));
        weaponsMarket = address(new WeaponsMarket(address(ICBM), address(Warhead), address(this), owner_)); // Pass NukeTheSupply address
        ICBM.transfer(owner(), ICBM_TOKEN_TOTAL_SUPPLY - NTS_CONTRACT_ICBM_BALANCE); // Creator receives 150M ICBM tokens
        Warhead.transfer(owner(), INITIAL_WARHEAD_TOKEN_SUPPLY); // Creator receives the full initial WH supply
    }

    // =======================================================
    // ===============      MAIN FUNCTIONS      ==============
    // =======================================================

    /*
     * @dev: This function is called by the user to "ARM" their ICBM tokens.
     * The function checks if the user has enough ICBM tokens, and if so, it creates a new batch of armed ICBM tokens.
     * The function also transfers the ICBM tokens from the user to this contract.
     */
    function arm(uint256 amount_) external {
        require(day < 99, "Arm phase over"); // Users end arming ICBM tokens after 149 days
        require(amount_ > 0, "Amount must be greater than 0");

        // Create new batch in memory
        ArmBatch memory newBatch = ArmBatch({amount: amount_, endTime: block.timestamp + ARM_DURATION});
        userArmBatches[_msgSender()].push(newBatch);
        totalArmedICBMAmount += amount_;

        // Transfer ICBM tokens from user to this contract
        require(ICBM.transferFrom(_msgSender(), address(this), amount_), "Transfer failed"); // Users send their ICBM tokens to this contract

        // Emit event
        emit Armed(_msgSender(), amount_, block.timestamp + ARM_DURATION);
    }

    /*
     * @dev: This function is called by the user to "NUKE" their armed ICBM tokens.
     * The function checks if the batch is ready to be nuked, and if so, it returns the 'ARMED' ICBM tokens to the user,
     * while burning 10% of the ICBM tokens amount of the contracts balance.
     * The function also mints Warhead tokens to the user in a 1:1 ratio with the burned ICBM tokens.
     */
    function nuke() external {
        // Get the user's batches from storage
        ArmBatch[] storage userBatches = userArmBatches[_msgSender()];
        uint256 totalICBMToReturn = 0;
        uint256 totalICBMToBurn = 0;

        // Check if the user has any batches
        for (uint256 i = 0; i < userBatches.length;) {
            // Check if the batch is ready to be nuked
            if (block.timestamp >= userBatches[i].endTime) {
                // Calculate the amount to burn and return ICBM tokens to user
                uint256 ICBMTokenAmount = userBatches[i].amount;
                uint256 burnAmount = ICBMTokenAmount / 10; // burn 10%
                totalICBMToReturn += ICBMTokenAmount;

                totalICBMToBurn += burnAmount; // Make sure contract holds enough tokens to burn

                // We track the contract's balance in a storage variable, since .balanceOf() would include user-armings too
                NTS_CONTRACT_ICBM_BALANCE -= burnAmount;
                totalICBMTokensBurned += burnAmount;
                totalArmedICBMAmount -= ICBMTokenAmount;

                // Emit event
                emit Nuked(_msgSender(), ICBMTokenAmount, burnAmount, burnAmount);

                // Remove the batch from storage
                userBatches[i] = userBatches[userBatches.length - 1];
                userBatches.pop();
            } else {
                i++;
            }
        }

        // Require that the user has at least one batch ready to be nuked
        require(totalICBMToReturn > 0, "No batches ready");
        // Transfer the ICBM tokens back to the user
        require(ICBM.transfer(_msgSender(), totalICBMToReturn), "Transfer failed");
        // Burn the ICBM tokens
        ICBM.burn(totalICBMToBurn);
        // Mint Warhead tokens to the user in 1:1 ratio with burned ICBM
        Warhead.mint(_msgSender(), totalICBMToBurn);
    }

    /*
     * @dev: This function transfers ICBM tokens to WeaponsMarket smart contract
     */
    function sell() external inOperationsPhase {
        require(block.timestamp >= nextSellTimestamp, "Can not sell yet");
        require(day <= 100, "Sell period ended");
        require(weaponsMarket != address(0), "WeaponsMarket not set");
        uint256 dailySell = (DAILY_ICBM_SELL_AMOUNT * day) > (totalICMBTokensSold + totalICBMTokensBurned)
            ? (DAILY_ICBM_SELL_AMOUNT * day) - (totalICMBTokensSold + totalICBMTokensBurned)
            : 0;

        if (dailySell > 0 && dailySell <= NTS_CONTRACT_ICBM_BALANCE) {
            NTS_CONTRACT_ICBM_BALANCE -= dailySell;
            totalICMBTokensSold += dailySell;

            // Transfer ICBM tokens to WeaponsMarket contract
            IERC20(address(ICBM)).safeTransfer(weaponsMarket, dailySell);
            emit SoldToWeaponsMarket(weaponsMarket, dailySell);

            // Reward the caller with 0.001% of the current WH supply
            uint256 warheadTokenSupply = Warhead.totalSupply();
            uint256 rewardAmount = warheadTokenSupply / 100_000;
            if (rewardAmount > 0) {
                Warhead.mint(_msgSender(), rewardAmount);
            }

            // State updates
            day++; // Increment day for next sell calculation
            nextSellTimestamp = block.timestamp + SELL_INTERVAL; // Set next allowed sell timestamp
        }
    }

    // =======================================================
    // ===============      VIEW FUNCTIONS      ==============
    // =======================================================

    // Returns true if the operations phase has ended
    function isOperationsPhaseEnded() external view returns (bool) {
        return block.timestamp >= deploymentTimestamp + OPERATIONS_DURATION;
    }

    // Fetch the address of the ICBM token
    function getICBMTokenAddress() public view returns (address) {
        return address(ICBM);
    }

    // Fetch the address of the Warhead token
    function getWarheadTokenAddress() public view returns (address) {
        return address(Warhead);
    }

    // Fetch the address of the WeaponsMarket contract
    function getWeaponsMarket() public view returns (address) {
        return weaponsMarket;
    }

    // Get the amount of ICBM tokens user has in ARM mode
    function getUserArmedICBM(address user) external view returns (uint256) {
        // ICBM tokens in ARM mode
        ArmBatch[] storage batches = userArmBatches[user];
        uint256 totalArmed;
        for (uint256 i = 0; i < batches.length; i++) {
            totalArmed += batches[i].amount;
        }
        return totalArmed;
    }

    // Get the amount of ICBM tokens user has ready to be "NUKE"
    function getUserReadyToNuke(address user) external view returns (uint256) {
        // ICBM tokens user is ready to "NUKE"
        ArmBatch[] storage batches = userArmBatches[user];
        uint256 totalReady;
        for (uint256 i = 0; i < batches.length; i++) {
            if (block.timestamp >= batches[i].endTime) {
                totalReady += batches[i].amount;
            }
        }
        return totalReady;
    }

    function getTotalBurned() external view returns (uint256) {
        return totalICBMTokensBurned;
    }

    function getTotalSold() external view returns (uint256) {
        return totalICMBTokensSold;
    }

    function getCurrentDay() external view returns (uint256) {
        return day;
    }

    function getRemainingSupply() external view returns (uint256) {
        return NTS_CONTRACT_ICBM_BALANCE;
    }

    function getDailySell() external view returns (uint256) {
        return (DAILY_ICBM_SELL_AMOUNT * day) > (totalICMBTokensSold + totalICBMTokensBurned)
            ? (DAILY_ICBM_SELL_AMOUNT * day) - (totalICMBTokensSold + totalICBMTokensBurned)
            : 0;
    }
}