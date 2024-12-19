// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Oracle} from "../../src/libraries/Oracle.sol";

contract OracleImplementation {
    using Oracle for Oracle.Observation[65535];

    Oracle.Observation[65535] public observations;

    uint32 public time;
    uint16 public index;
    uint16 public cardinality;
    uint16 public cardinalityNext;

    struct InitializeParams {
        uint32 time;
    }

    function initialize(InitializeParams calldata params) external {
        require(cardinality == 0, "already initialized");
        time = params.time;
        (cardinality, cardinalityNext) = observations.initialize(params.time);
    }

    function advanceTime(uint32 by) public {
        unchecked {
            time += by;
        }
    }

    struct UpdateParams {
        uint32 advanceTimeBy;
        int128 token0Volume;
        int128 token1Volume;
    }

    // write an observation, then change token0Volume and token1Volume
    function update(UpdateParams calldata params) external {
        advanceTime(params.advanceTimeBy);
        (index, cardinality) = observations.write(index, time, params.token0Volume, params.token1Volume, cardinality, cardinalityNext);
    }

    function batchUpdate(UpdateParams[] calldata params) external {
        // sload everything
        uint16 _index = index;
        uint16 _cardinality = cardinality;
        uint16 _cardinalityNext = cardinalityNext;
        uint32 _time = time;

        for (uint256 i = 0; i < params.length; i++) {
            _time += params[i].advanceTimeBy;
            (_index, _cardinality) =
                observations.write(_index, _time, params[i].token0Volume, params[i].token1Volume, _cardinality, _cardinalityNext);
        }

        // sstore everything
        index = _index;
        cardinality = _cardinality;
        time = _time;
    }

    function grow(uint16 _cardinalityNext) external {
        cardinalityNext = observations.grow(cardinalityNext, _cardinalityNext);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives)
    {
        return observations.observe(time, secondsAgos, index, cardinality);
    }

    function getGasCostOfObserve(uint32[] calldata secondsAgos) external view returns (uint256) {
        (uint32 _time, uint16 _index) = (time, index);
        uint256 gasBefore = gasleft();
        observations.observe(_time, secondsAgos, _index, cardinality);
        return gasBefore - gasleft();
    }
}
