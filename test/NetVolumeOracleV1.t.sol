// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {NetVolumeOracleV1} from "../src/NetVolumeOracleV1.sol";

contract TestNetVolumeOracleV1 is Test, Deployers {
    using CurrencyLibrary for Currency;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    PoolId poolId;

    NetVolumeOracleV1 hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        hook = NetVolumeOracleV1(address(flags));
        deployCodeTo("NetVolumeOracleV1.sol", abi.encode(manager), address(hook));

        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), 100, SQRT_PRICE_1_1
        );
        poolId = key.toId();

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function test_swap_zeroForOne() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));
        uint256 amountToSwap = 1e15;

        PoolSwapTest.TestSettings memory testSettings = 
            PoolSwapTest.TestSettings({
                    takeClaims: false,
                    settleUsingBurn: false
                });

        // swap token0 for token1
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(amountToSwap),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        BalanceDelta delta = swapRouter.swap(
            key,
            params,
            testSettings,
            hookData
        );

        // assert that the netVolume of token0 on the pool is negative
        assertEq(hook.poolNetVolumeToken0(poolId), delta.amount0());
        assertLt(hook.poolNetVolumeToken0(poolId), 0);

        // assert that the netVolume of token1 on the pool is positive
        assertEq(hook.poolNetVolumeToken1(poolId), delta.amount1());
        assertGt(hook.poolNetVolumeToken1(poolId), 0);

        // assert that the user's net volume of token0 is negative
        assertEq(hook.userNetVolumeToken0(poolId, address(this)), delta.amount0());
        assertLt(hook.userNetVolumeToken0(poolId, address(this)), 0);

        // assert that the user's net volume of token1 is positive
        assertEq(hook.userNetVolumeToken1(poolId, address(this)), delta.amount1());
        assertGt(hook.userNetVolumeToken1(poolId, address(this)), 0);
    }

    function test_swap_oneForZero() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));
        uint256 amountToSwap = 1e15;

        PoolSwapTest.TestSettings memory testSettings = 
            PoolSwapTest.TestSettings({
                    takeClaims: false,
                    settleUsingBurn: false
                });

        // swap token1 for token0
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(amountToSwap),
            sqrtPriceLimitX96: MAX_PRICE_LIMIT
        }); 
        BalanceDelta delta = swapRouter.swap(
            key,
            params,
            testSettings,
            hookData
        );

        // assert that the netVolume of token0 on the pool is negative
        assertEq(hook.poolNetVolumeToken0(poolId), delta.amount0());
        assertGt(hook.poolNetVolumeToken0(poolId), 0);

        // assert that the netVolume of token1 on the pool is positive
        assertEq(hook.poolNetVolumeToken1(poolId), delta.amount1());
        assertLt(hook.poolNetVolumeToken1(poolId), 0);

        // assert that the user's net volume of token0 is positive
        assertEq(hook.userNetVolumeToken0(poolId, address(this)), delta.amount0());
        assertGt(hook.userNetVolumeToken0(poolId, address(this)), 0);

        // assert that the user's net volume of token1 is negative
        assertEq(hook.userNetVolumeToken1(poolId, address(this)), delta.amount1());
        assertLt(hook.userNetVolumeToken1(poolId, address(this)), 0);
    }
}
