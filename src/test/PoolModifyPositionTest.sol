// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract PoolModifyPositionTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
        bytes hookData;
    }

    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, params, hookData))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.modifyPosition(data.key, data.params, data.hookData);
        console2.logInt(delta.amount0());
        console2.logInt(delta.amount1());

        if (delta.amount0() > 0) {
            if (data.key.currency0.isNative()) {
                console2.log("0");
                manager.settle{value: uint256(int256(delta.amount0()))}(data.key.currency0);
            } else {
                console2.log("1");
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(manager), uint256(int256(delta.amount0()))
                );
                manager.settle(data.key.currency0);
            }
        }
        if (delta.amount1() > 0) {
                console2.log("2");
            if (data.key.currency1.isNative()) {
                manager.settle{value: uint256(int256(delta.amount1()))}(data.key.currency1);
            } else {
                console2.log("3");
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(manager), uint256(int256(delta.amount1()))
                );
                manager.settle(data.key.currency1);
            }
        }

        if (delta.amount0() < 0) {
            console2.log("4");
            manager.take(data.key.currency0, data.sender, uint256(-int256(delta.amount0())));
        }
        if (delta.amount1() < 0) {
            console2.log("5");
            manager.take(data.key.currency1, data.sender, uint256(-int256(delta.amount1())));
        }

        console2.log("DONE");
        return abi.encode(delta);
    }
}
