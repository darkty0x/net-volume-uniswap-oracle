// NOTE: This is based on V4PreDeployed.s.sol
// You can make changes to base on V4Deployer.s.sol to deploy everything fresh as well

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/test/PoolClaimsTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {HookMiner} from "../test/HookMiner.sol";
import {NetVolumeOracle} from "../src/NetVolumeOracle.sol";
import {console} from "forge-std/console.sol";

contract HookMiningSample is Script {
    // base sepolia addresses
    PoolManager manager =
        PoolManager(0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829);
    PoolSwapTest swapRouter =
        PoolSwapTest(0x96E3495b712c6589f1D2c50635FDE68CF17AC83c);
    PoolModifyLiquidityTest modifyLiquidityRouter =
        PoolModifyLiquidityTest(0xC94a4C0a89937E278a0d427bb393134E68d5ec09);

    Currency token0;
    Currency token1;

    PoolKey key;
    NetVolumeOracle hook;

    function setUp() public {
        vm.startBroadcast();

        MockERC20 tokenA = new MockERC20("Meme Token", "M3M3", 18);
        MockERC20 tokenB = new MockERC20("Blue Chip Token", "BLU3CH1P", 18);

        if (address(tokenA) > address(tokenB)) {
            (token0, token1) = (
                Currency.wrap(address(tokenB)),
                Currency.wrap(address(tokenA))
            );
        } else {
            (token0, token1) = (
                Currency.wrap(address(tokenA)),
                Currency.wrap(address(tokenB))
            );
        }

        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);

        tokenA.mint(msg.sender, 1000000000000000000 * 10 ** 18);
        tokenB.mint(msg.sender, 1000000000000000000 * 10 ** 18);

        // Mine for hook address
        vm.stopBroadcast();

        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG);

        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(NetVolumeOracle).creationCode,
            abi.encode(address(manager))
        );
        console.log("Hook address: ", hookAddress);
        console.log("token0 address: ", Currency.unwrap(token0));
        console.log("token1 address: ", Currency.unwrap(token1));

        vm.startBroadcast();

        // deploy hook
        hook = new NetVolumeOracle{salt: salt}(manager);
        require(address(hook) == hookAddress, "hook address mismatch");

        key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 1000,
            tickSpacing: 120,
            hooks: hook
        });

        // the second argument here is SQRT_PRICE_1_1
        manager.initialize(key, 79228162514264337593543950336);
        vm.stopBroadcast();
    }

    function run() public {
        vm.startBroadcast();
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 100000000000000000e18,
                salt: 0
            }),
            new bytes(0)
        );

        // ask oracle to record up to 100 observations on the pool
        hook.increaseCardinalityNext(key, 100);
        vm.stopBroadcast();
    }
}
