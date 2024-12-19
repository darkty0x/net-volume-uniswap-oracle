// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {Oracle} from "../src/libraries/Oracle.sol";
import {NetVolumeOracle} from "../src/NetVolumeOracle.sol";

contract TestNetVolumeOracle is Test, Deployers {
    using CurrencyLibrary for Currency;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    PoolId poolId;

    NetVolumeOracle hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG);
        hook = NetVolumeOracle(address(flags));
        deployCodeTo("NetVolumeOracle.sol", abi.encode(manager), address(hook));

        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), 100, SQRT_PRICE_1_1
        );
        poolId = key.toId();

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function testCanAttachToPoolsWithDifferentFees() public {
        initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), 300, SQRT_PRICE_1_1
        );

        initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), 500, SQRT_PRICE_1_1
        );

        initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), 1000, SQRT_PRICE_1_1
        );
    }

    function testAfterInitializeState() public {
        NetVolumeOracle.ObservationState memory observationState = hook.getState(key);
        assertEq(observationState.index, 0);
        assertEq(observationState.cardinality, 1);
        assertEq(observationState.cardinalityNext, 1);
    }

    function testAfterInitializeObservation() public {
        Oracle.Observation memory observation = hook.getObservation(key, 0);
        assertTrue(observation.initialized);
        assertEq(observation.blockTimestamp, 1);
        assertEq(observation.token0VolumeCumulative, 0);
        assertEq(observation.token1VolumeCumulative, 0);
    }

    function testAfterInitializeObserve0() public {
        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 0;
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) = hook.observe(key, secondsAgo);
        assertEq(token0VolumeCumulatives.length, 1);
        assertEq(token1VolumeCumulatives.length, 1);
        assertEq(token0VolumeCumulatives[0], 0);
        assertEq(token1VolumeCumulatives[0], 0);
    }

    function testObserveAfterSwapZeroForOne() public {
        BalanceDelta delta = swap_zeroForOne(100);

        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 0;
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) = hook.observe(key, secondsAgo);

        assertEq(token0VolumeCumulatives.length, 1);
        assertEq(token1VolumeCumulatives.length, 1);
        assertEq(token0VolumeCumulatives[0], delta.amount0());
        assertEq(token1VolumeCumulatives[0], delta.amount1());
    }

    function testObserveAfterSwapOneForZer0() public {
        BalanceDelta delta = swap_oneForZero(100);

        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 0;
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) = hook.observe(key, secondsAgo);

        assertEq(token0VolumeCumulatives.length, 1);
        assertEq(token1VolumeCumulatives.length, 1);
        assertEq(token0VolumeCumulatives[0], delta.amount0());
        assertEq(token1VolumeCumulatives[0], delta.amount1());
    }

    function testObserveAfterSwapZeroForOne20SecondsLater() public {
        BalanceDelta delta = swap_zeroForOne(100);
        vm.warp(block.timestamp + 20);

        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 0;
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) = hook.observe(key, secondsAgo);

        assertEq(token0VolumeCumulatives.length, 1);
        assertEq(token1VolumeCumulatives.length, 1);
        assertEq(token0VolumeCumulatives[0], delta.amount0() + delta.amount0() * 20);
        assertEq(token1VolumeCumulatives[0], delta.amount1() + delta.amount1() * 20);
    }

    function testObserve20SecondsAgoAfterSwapAfter20Seconds() public {
        BalanceDelta delta = swap_zeroForOne(100);
        vm.warp(block.timestamp + 20);

        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 20;
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) = hook.observe(key, secondsAgo);

        assertEq(token0VolumeCumulatives.length, 1);
        assertEq(token1VolumeCumulatives.length, 1);
        assertEq(token0VolumeCumulatives[0], delta.amount0());
        assertEq(token1VolumeCumulatives[0], delta.amount1());
    }

    function testIncreaseCardinalityNext() public {
        // increase cardinality next
        hook.increaseCardinalityNext(key, 3);

        // assert state
        NetVolumeOracle.ObservationState memory observationState = hook.getState(key);
        assertEq(observationState.index, 0);
        assertEq(observationState.cardinality, 1);
        assertEq(observationState.cardinalityNext, 3);

        // conduct swap
        vm.warp(block.timestamp + 12);  // advance a block
        swap_zeroForOne(100);

        // assert new state
        observationState = hook.getState(key);
        assertEq(observationState.index, 1);
        assertEq(observationState.cardinality, 3);
        assertEq(observationState.cardinalityNext, 3);
    }

    /* Util function for swapping token0 to token1 */
    function swap_zeroForOne(uint256 amountToSwap) public returns (BalanceDelta) {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

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

        return delta;
    }

    /* Util function for swapping token1 to token0 */
    function swap_oneForZero(uint256 amountToSwap) public returns (BalanceDelta) {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

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

        return delta;
    }

    // get time weighted average net volume for a pool during a given time period
    function testGetNetVolumeTimePeriod() public {
        hook.increaseCardinalityNext(key, 3);

        // set the times to be observed
        uint32 startTime = uint32(block.timestamp) + 20;
        uint32 endTime = uint32(block.timestamp) + 40;

        // make first swap (won't be queried)
        swap_zeroForOne(100);

        // make second swap
        vm.warp(startTime);
        BalanceDelta deltaSecond = swap_zeroForOne(200);

        // make third swap
        vm.warp(endTime);
        BalanceDelta deltaThird = swap_zeroForOne(300);

        // get net volume
        (int256 token0NetVolume, int256 token1NetVolume) = hook.getNetVolume(
            key, 
            startTime,
            endTime
        );
        
        // assert net volume
        assertEq(token0NetVolume, (deltaSecond.amount0() * 20 + deltaThird.amount0()) / 20);
        assertEq(token1NetVolume, (deltaSecond.amount1() * 20 + deltaThird.amount1()) / 20);
    }

    // get time weighted average net volume for a pool between the given time and now
    function testGetNetVolumeSinceGivenTime() public {
        hook.increaseCardinalityNext(key, 3);

        // set the times to be observed
        uint32 startTime = uint32(block.timestamp) + 20;
        uint32 endTime = uint32(block.timestamp) + 40;

        // make first swap (won't be queried)
        swap_zeroForOne(100);

        // make second swap
        vm.warp(startTime);
        BalanceDelta deltaSecond = swap_zeroForOne(200);

        // make third swap
        vm.warp(endTime);
        BalanceDelta deltaThird = swap_zeroForOne(300);

        // get net volume
        (int256 token0NetVolume, int256 token1NetVolume) = hook.getNetVolume(
            key, 
            startTime
        );
        
        // assert net volume
        assertEq(token0NetVolume, (deltaSecond.amount0() * 20 + deltaThird.amount0()) / 20);
        assertEq(token1NetVolume, (deltaSecond.amount1() * 20 + deltaThird.amount1()) / 20);
    }
}
