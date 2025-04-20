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
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

pragma solidity >=0.5.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function approve(address guy, uint256 wad) external returns (bool);
}

contract NukeTheSupplyTest is Test {
    NukeTheSupply public nts;
    ICBMToken public icbm;
    WarheadToken public warhead;
    IUniswapV3Factory public uniswapFactory;
    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;

    uint256 mainnetFork;

    address public owner = address(0xABCD);
    address public user = address(0x1234);
    address public swapRouter; // Mock router

    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH address on mainnet

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.startPrank(owner);

        mainnetFork = vm.createFork(MAINNET_RPC_URL);

        uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

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
        nts = new NukeTheSupply(owner, address(weth), swapRouter);

        // Fetch the ICBM token and Warhead token addresses
        icbm = ICBMToken(nts.getICBMTokenAddress());
        warhead = WarheadToken(nts.getWarheadTokenAddress());

        // Assert correct balances of ICBM and Warhead tokens
        assertEq(icbm.balanceOf(owner), 100_000_000 * 10 ** 18);
        assertEq(warhead.balanceOf(owner), 1000 * 10 ** 18);
        assertEq(icbm.balanceOf(address(nts)), 730_000_000 * 10 ** 18);

        // Get 1000 weth
        vm.deal(owner, 1000 ether);
        weth.deposit{value: 1000 ether}();

        assertEq(weth.balanceOf(owner), 1000 ether);

        // Create ICBM/WETH pool
        address pool = uniswapFactory.createPool(address(icbm), address(weth), 3000);
        assertNotEq(pool, address(0));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
    
        // set the initial price for the pool
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        // Approve liquidity to the position manager
        TransferHelper.safeApprove(address(icbm), address(positionManager), type(uint256).max);
        TransferHelper.safeApprove(address(weth), address(positionManager), type(uint256).max);
        TransferHelper.safeApprove(address(warhead), address(positionManager), type(uint256).max);
    }
}
