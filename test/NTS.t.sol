// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../src/NTS_.sol";
import "../src/ICBMToken.sol";
import "../src/WarheadToken.sol";

import {Test, console} from "forge-std/Test.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function approve(address guy, uint256 wad) external returns (bool);
}

interface INonFungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams memory params)
        external
        returns (uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);
}

contract NukeTheSupplyTest is Test {
    NukeTheSupply public nts;
    ICBMToken public icbm;
    WarheadToken public warhead;
    IUniswapV3Factory public uniswapFactory;
    INonFungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;

    uint256 mainnetFork;

    address public owner = address(0xABCD);
    address public user = address(0x1234);

    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH address on mainnet

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.startPrank(owner);

        mainnetFork = vm.createFork(MAINNET_RPC_URL);

        uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        positionManager = INonFungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

        vm.stopPrank();
    }

    function testCanSetForkBlockNumber() public {
        vm.selectFork(mainnetFork);
        vm.rollFork(1_337_000);

        assertEq(block.number, 1_337_000);
    }

    function testNukeTheSupplyE2E() public {
        // Start a prank as the owner
        vm.startPrank(owner);

        // Select fork of the mainnet
        vm.selectFork(mainnetFork);

        // Deploy the NukeTheSupply contract
        nts = new NukeTheSupply(owner, address(weth), address(swapRouter));

        // Fetch the ICBM token and Warhead token addresses
        icbm = ICBMToken(nts.getICBMTokenAddress());
        warhead = WarheadToken(nts.getWarheadTokenAddress());

        // Assert correct balances of ICBM and Warhead tokens
        assertEq(icbm.balanceOf(owner), 100_000_000 * 10 ** 18);
        assertEq(warhead.balanceOf(owner), 1000 * 10 ** 18);
        assertEq(icbm.balanceOf(address(nts)), 730_000_000 * 10 ** 18);

        // Get 1000 weth
        vm.deal(owner, 5000 ether);
        weth.deposit{value: 5000 ether}();

        assertEq(weth.balanceOf(owner), 5000 ether);

        // FIRST POOL INITIALIZING WETH/ICBM
        {
            address token0;
            address token1;
            // Check the order of tokens
            if (address(icbm) < address(weth)) {
                token0 = address(icbm);
                token1 = address(weth);
            } else {
                token0 = address(weth);
                token1 = address(icbm);
            }

            // Create ICBM/WETH pool
            address pool = uniswapFactory.createPool(token0, token1, 3000);
            assertNotEq(pool, address(0));

            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);

            // set the initial price for the pool
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);

            // Approve liquidity to the position manager
            TransferHelper.safeApprove(address(icbm), address(positionManager), type(uint256).max);
            TransferHelper.safeApprove(address(weth), address(positionManager), type(uint256).max);
            TransferHelper.safeApprove(address(warhead), address(positionManager), type(uint256).max);

            // Add liquidity to the pool
            INonFungiblePositionManager.MintParams memory params = INonFungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: 1000 ether,
                amount1Desired: 100_000_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(owner),
                deadline: block.timestamp
            });
            (uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1) = positionManager.mint(params);

            // Approve swap router to spend WETH
            TransferHelper.safeApprove(address(weth), address(swapRouter), type(uint256).max);

            // Perform a swap in the pool
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(icbm),
                fee: 3000,
                recipient: address(owner),
                deadline: block.timestamp,
                amountIn: 123 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            uint256 amountOut = swapRouter.exactInputSingle(swapParams);
            console.log(amountOut);
        }

        // SECOND POOL INITIALIZING WETH/WARHEAD
        {
            address token0;
            address token1;
            // Check the order of tokens
            if (address(warhead) < address(weth)) {
                token0 = address(warhead);
                token1 = address(weth);
            } else {
                token0 = address(weth);
                token1 = address(warhead);
            }

            // Create ICBM/WETH pool
            address pool = uniswapFactory.createPool(token0, token1, 3000);
            assertNotEq(pool, address(0));

            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);

            // set the initial price for the pool
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);

            // Approve liquidity to the position manager
            TransferHelper.safeApprove(address(warhead), address(positionManager), type(uint256).max);
            TransferHelper.safeApprove(address(weth), address(positionManager), type(uint256).max);
            TransferHelper.safeApprove(address(warhead), address(positionManager), type(uint256).max);

            // Add liquidity to the pool
            INonFungiblePositionManager.MintParams memory params = INonFungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: 1000 ether,
                amount1Desired: 1000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(owner),
                deadline: block.timestamp
            });
            (uint256 tokenId, uint256 liquidity, uint256 amount0, uint256 amount1) = positionManager.mint(params);

            // Approve swap router to spend WETH
            TransferHelper.safeApprove(address(weth), address(swapRouter), type(uint256).max);

            // Perform a swap in the pool
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(warhead),
                fee: 3000,
                recipient: address(owner),
                deadline: block.timestamp,
                amountIn: 123 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            uint256 amountOut = swapRouter.exactInputSingle(swapParams);
            console.log(amountOut);
        }

        // Make a multihop swap
        {
            TransferHelper.safeApprove(address(icbm), address(swapRouter), type(uint256).max); // approve the swapRouter to spend ICBM tokens

            // See more: https://docs.uniswap.org/contracts/v3/guides/swaps/multihop-swaps
            ISwapRouter.ExactInputParams memory swapParams_ = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(icbm), uint24(3000), address(weth), uint24(3000), address(warhead)), // need to put correct fee tier
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: 123456,
                amountOutMinimum: 0 // Handle this more securely
            });

            // Executes the swap
            uint256 amountOut = ISwapRouter(swapRouter).exactInput(swapParams_);
            console.log(amountOut);
        }

        // Test multihop swap on NukeTheSupply contract
        {
            vm.warp(block.timestamp + 7 days);
            nts.sell();
        }
    }
}
