// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Imports
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Import ICBM & Warhead tokens
import "./ICBMToken.sol";
import "./WarheadToken.sol";

contract NukeTheSupply is Ownable {
    using SafeERC20 for IERC20;

    // Tokens used in contract
    ICBMToken public ICBM;
    WarheadToken public Warhead;

    // Token supply values
    uint256 public constant ICBM_TOKEN_TOTAL_SUPPLY = 830_000_000 * 10 ** 18; // 830 million
    uint256 public constant INITIAL_WARHEAD_TOKEN_SUPPLY = 1_000 * 10 ** 18; // 1 thousand
    uint256 public NTS_CONTRACT_ICBM_BALANCE = 730_000_000 * 10 ** 18; // 730 million
    uint256 public constant DAILY_ICBM_SELL_AMOUNT = 2_000_000 * 10 ** 18; // 2 million per day

    // Token values
    uint256 public totalArmedICBMAmount; // Total amount of user supplied tokens in "ARM" state
    uint256 public totalWarheadBought; // Total amount of Warhead tokens bought by this contract
    uint256 public totalICBMTokensBurned; // Total amount of ICBM tokens burned by users with "nuke" function, since deployment
    uint256 public totalICMBTokensSold; // Total amount of ICBM tokens sold by this contract, since deployment
    uint256 public day; // Day counter variable - counting since deployment
    uint256 public deploymentTimestamp; // potrebno za postavljanje uvjeta za prvi poziv sell funkciji i faze rada ugovora
    uint256 public nextSellTimestamp; // potrebno za postavljanje svih drugih uvjeta za sell funkciju
    uint256 public constant PREPARATION_DURATION = 48 hours; // Change to 2 minutes for testing purposes
    uint256 public constant OPERATIONS_DURATION = 365 days; // Time period during which the contract is selling ICBM tokens
    uint256 public constant ARM_DURATION = 24 hours; // Time period during which ICBM tokens are armed
    uint256 public constant SELL_INTERVAL = 24 hours; // Time period between sell functions
    address public immutable WETH; // Wrapped ETH (sepolia)
    address public swapRouter; // Uniswap V3 router address

    // Structs and mapping for user's batches of armed ICBM tokens
    struct ArmBatch {
        uint256 amount;
        uint256 endTime;
    }

    mapping(address => ArmBatch[]) public userArmBatches;

    // EVENTS
    event Armed(address indexed user, uint256 amount, uint256 endTime);
    event Nuked(address indexed user, uint256 icbmAmount, uint256 burnedAmount, uint256 whMinted);
    event Sold(uint256 day, uint256 icbmSold, uint256 ethReceived, uint256 ethKept);
    event Bought(uint256 day, uint256 warheadBought);

    // MODIFIERS
    modifier inPreparationPhase() {
        require(block.timestamp < deploymentTimestamp + PREPARATION_DURATION, "Preparation phase ended");
        _;
    }

    modifier inOperationsPhase() {
        require(block.timestamp >= deploymentTimestamp + PREPARATION_DURATION, "Operations phase not started");
        _;
    }

    constructor(address owner_, address WETH_, address swapRouter_) Ownable(owner_) {
        deploymentTimestamp = block.timestamp;
        day = 1;
        ICBM = new ICBMToken("ICBM", "ICBM", ICBM_TOKEN_TOTAL_SUPPLY, address(this)); // kreatoru ide 830M ICBM tokena da napravi trading par ICBM/WETH na uniswapu v3
        Warhead = new WarheadToken("Warhead", "WH", INITIAL_WARHEAD_TOKEN_SUPPLY, address(this)); // kreatoru ide 1K WH tokena da napravi trading par WH/WETH na uniswapu v3
        ICBM.transfer(owner(), ICBM_TOKEN_TOTAL_SUPPLY - NTS_CONTRACT_ICBM_BALANCE); // kreatoru ide 100M ICBM tokena da napravi trading par ICBM/WETH na uniswapu v3
        Warhead.transfer(owner(), INITIAL_WARHEAD_TOKEN_SUPPLY); // kreatoru ide sav inicijalni supply za WH/WETH trading par

        WETH = WETH_; // Wrapped ETH (sepolia)
        swapRouter = swapRouter_; // Uniswap V3 router address
    }

    // =======================================================
    // ===============      MAIN FUNCTIONS      ==============
    // =======================================================

    function arm(uint256 amount_) external {
        require(day < 364, "Arm phase over"); // Users end arming ICBM tokens after 364 days
        require(amount_ > 0, "Amount must be greater than 0");

        // Create new batch in memory
        ArmBatch memory newBatch = ArmBatch({amount: amount_, endTime: block.timestamp + ARM_DURATION});
        userArmBatches[_msgSender()].push(newBatch);
        totalArmedICBMAmount += amount_;

        // Transfer ICBM tokens from user to this contract
        require(ICBM.transferFrom(msg.sender, address(this), amount_), "Transfer failed"); // Users send their ICBM tokens to this contract

        // Emit event
        emit Armed(msg.sender, amount_, block.timestamp + ARM_DURATION);
    }

    function nuke() external {
        // Get the user's batches from storage
        ArmBatch[] storage userBatches = userArmBatches[msg.sender];
        uint256 totalICBMToReturn = 0;
        uint256 totalICBMBurned = 0;

        // Check if the user has any batches
        for (uint256 i = 0; i < userBatches.length;) {
            // Check if the batch is ready to be nuked
            if (block.timestamp >= userBatches[i].endTime) {
                // Calculate the amount to burn and return ICBM tokens to user
                uint256 ICBMTokenAmount = userBatches[i].amount;
                // Calculate the amount of this contracts token amount to burn
                uint256 burnAmount = ICBMTokenAmount / 10;
                // Calculate the total amount of ICBM tokens to return to user
                totalICBMToReturn += ICBMTokenAmount;

                // Handling the supply
                totalICBMBurned += burnAmount; // We need to make sure this contract HAS enough ICBM tokens to burn
                require(ICBM.balanceOf(address(this)) >= burnAmount, "Not enough ICBM tokens in contract");

                // We track the balance of this contract in a storage variable because dynamic .balaneOf() calls will also
                // track in the tokens user armed to the contract
                NTS_CONTRACT_ICBM_BALANCE -= burnAmount;
                totalICBMTokensBurned += burnAmount;
                totalArmedICBMAmount -= ICBMTokenAmount;

                // Mint Warhead tokens to the user in 1:1 ratio of the ICBM tokens this contract is burning
                Warhead.mint(_msgSender(), burnAmount);

                // Emit event
                emit Nuked(_msgSender(), ICBMTokenAmount, burnAmount, burnAmount);

                // Remove the batch from storage
                userBatches[i] = userBatches[userBatches.length - 1];
                userBatches.pop();
            } else {
                i++;
            }
        }

        // Require there are some ICBM tokens to return to user
        require(totalICBMToReturn > 0, "No batches ready");
        // Transfer ICBM tokens back to the user
        require(ICBM.transfer(_msgSender(), totalICBMToReturn), "Transfer failed");
        // Burn the ICBM tokens from this contract
        ICBM.burn(totalICBMTokensBurned);
    }

    /////////// funkcija koju može pozvati bilo tko, svaka 24 sata, računa količinu ICBM-a za prodaju, dobiveni WETH koristi za kupnju WH tokena
    /////////// nagrađuje pozivatelja funkcije sa 0.001% supply-a WH tokena, minta WH i šalje ih pozivatelju funkcije
    function sell() external inOperationsPhase {
        require(block.timestamp >= nextSellTimestamp, "Can not sell yet");
        require(day <= 365, "Sell period ended");

        uint256 dailySell = (DAILY_ICBM_SELL_AMOUNT * day) > (totalICMBTokensSold + totalICBMTokensBurned)
            ? (DAILY_ICBM_SELL_AMOUNT * day) - (totalICMBTokensSold + totalICBMTokensBurned)
            : 0;

        if (dailySell > 0 && dailySell <= NTS_CONTRACT_ICBM_BALANCE) {
            NTS_CONTRACT_ICBM_BALANCE -= dailySell;
            totalICMBTokensSold += dailySell;

            /**
             * Uniswap trading happens here:
             * dailySell amount of ICBM tokens is sold for WETH, WETH is then used for buying Warhead tokens, those Warhead tokens are then burned
             */

            TransferHelper.safeApprove(address(ICBM), address(swapRouter), dailySell); // approve the swapRouter to spend ICBM tokens

            // See more: https://docs.uniswap.org/contracts/v3/guides/swaps/multihop-swaps
            ISwapRouter.ExactInputParams memory swapParams_ = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(ICBM), uint24(3000), WETH, uint24(3000), address(Warhead)), // need to put correct fee tier
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: dailySell,
                amountOutMinimum: 0 // Handle this more securely
            });

            // Executes the swap
            uint256 amountOut = ISwapRouter(swapRouter).exactInput(swapParams_);

            // Burn the receiving amount of Warhead tokens
            Warhead.burn(amountOut);

            // Do we put this here?
            // totalWarheadBought += amountOut; // Track the total amount of Warhead tokens bought by this contract

            // Mint to caller 0.001% of the Warhead current total supply
            uint256 warheadTokenSupply = Warhead.totalSupply();
            uint256 rewardAmount = warheadTokenSupply / 100000;
            if (rewardAmount > 0) {
                Warhead.mint(_msgSender(), rewardAmount);
            }

            // Change necessary state
            day++; // postavljanje day varijable za sljedeću kalkulaciju u sell funkciji
            nextSellTimestamp = block.timestamp + SELL_INTERVAL; // postavljanje novog timestampa prije kojeg se sell funkcija ne može pozvati
        }
    }

    // =======================================================
    // ===============      VIEW FUNCTIONS      ==============
    // =======================================================
}
