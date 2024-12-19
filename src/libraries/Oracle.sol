// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title Oracle
/// @notice Provides price and liquidity data useful for a wide variety of system designs
/// @dev Instances of stored oracle data, "observations", are collected in the oracle array
/// Every pool is initialized with an oracle array length of 1. Anyone can pay the SSTOREs to increase the
/// maximum length of the oracle array. New slots will be added when the array is fully populated.
/// Observations are overwritten when the full length of the oracle array is populated.
/// The most recent observation is available, independent of the length of the oracle array, by passing 0 to observe()
library Oracle {
    /// @notice Thrown when trying to interact with an Oracle of a non-initialized pool
    error OracleCardinalityCannotBeZero();

    /// @notice Thrown when trying to observe a price that is older than the oldest recorded price
    /// @param oldestTimestamp Timestamp of the oldest remaining observation
    /// @param targetTimestamp Invalid timestamp targeted to be observed
    error TargetPredatesOldestObservation(uint32 oldestTimestamp, uint32 targetTimestamp);

    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the volume accumulators, i.e. volume * time elapsed since the pool was first initialized
        int256 token0VolumeCumulative;
        int256 token1VolumeCumulative;
        // the volume at the observation
        int128 token0Volume;
        int128 token1Volume;
        // whether or not the observation is initialized
        bool initialized;
    }

    /// @notice Transforms a previous observation into a new observation, given the passage of time and the current token volume values
    /// @dev blockTimestamp _must_ be chronologically equal to or greater than last.blockTimestamp, safe for 0 or 1 overflows
    /// @param last The specified observation to be transformed
    /// @param blockTimestamp The timestamp of the new observation
    /// @param token0Volume The pool's token0 volume as of the new observation
    /// @param token1Volume The pool's token1 volume as of the new observation
    /// @return Observation The newly populated observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int128 token0Volume,
        int128 token1Volume
    )
        private
        pure
        returns (Observation memory)
    {
        unchecked {
            uint32 delta = blockTimestamp - last.blockTimestamp;
            // when the timestamp is the same (multiple observations in the same block)
            // set the delta to 1 so that the volume is scaled appropriately
            bool sameBlock = delta == 0;
            if (sameBlock) delta = 1;

            // if this tranform is part of the read path
            //  token0Volume should be equal to last.token0Volume * delta
            //  token1Volume should be equal to last.token1Volume * delta
            //  token0VolumeCumulative should be equal to last.token0VolumeCumulative + token0Volume
            //  token1VolumeCumulative should be equal to last.token1VolumeCumulative + token1Volume
            // if this transform is part of the write path
            //  if the observation is in the same block
            //      token0VolumeCumulative should be equal to last.token0VolumeCumulative + token0Volume
            //      token1VolumeCumulative should be equal to last.token1VolumeCumulative + token1Volume
            //      token0Volume should be equal to last.token0Volume + token0Volume
            //      token1Volume should be equal to last.token1Volume + token1Volume
            //  if the observation is in a new block
            //      token0Volume should be equal to token0Volume
            //      token1Volume should be equal to token1Volume
            //      token0VolumeCumulative should be equal to last.token0VolumeCumulative + last.token0Volume * delta + token0Volume
            //      token1VolumeCumulative should be equal to last.token1VolumeCumulative + last.token1Volume * delta + token1Volume

            return Observation({
                blockTimestamp: blockTimestamp,
                token0VolumeCumulative: last.token0VolumeCumulative + 
                    int256(last.token0Volume) * int256(uint256(delta)) +
                    int256(token0Volume),
                token1VolumeCumulative: last.token1VolumeCumulative +
                    int256(last.token1Volume) * int256(uint256(delta)) +
                    int256(token1Volume),
                token0Volume: sameBlock ? last.token0Volume + token0Volume : token0Volume,
                token1Volume: sameBlock ? last.token1Volume + token1Volume : token1Volume,
                initialized: true
            });
            /*
            return Observation({
                blockTimestamp: blockTimestamp,
                token0VolumeCumulative: last.token0VolumeCumulative + 
                    int256(token0Volume) * int256(uint256(delta)),
                token1VolumeCumulative: last.token1VolumeCumulative +
                    int256(token1Volume) * int256(uint256(delta)),
                initialized: true
            });
            */
        }
    }

    function transformReadPath(
        Observation memory last,
        uint32 blockTimestamp
    )
        private
        pure
        returns (Observation memory)
    {
        unchecked {
            uint32 delta = blockTimestamp - last.blockTimestamp;

            return Observation({
                blockTimestamp: blockTimestamp,
                token0VolumeCumulative: last.token0VolumeCumulative + 
                    int256(last.token0Volume) * int256(uint256(delta)),
                token1VolumeCumulative: last.token1VolumeCumulative +
                    int256(last.token1Volume) * int256(uint256(delta)),
                token0Volume: last.token0Volume,
                token1Volume: last.token1Volume,
                initialized: true
            });
        }
    }

    function transformWritePath(
        Observation memory last,
        uint32 blockTimestamp,
        int128 token0Volume,
        int128 token1Volume
    )
        private
        pure
        returns (Observation memory)
    {
        unchecked {
            uint32 delta = blockTimestamp - last.blockTimestamp;
            bool sameBlock = delta == 0;

            return Observation({
                blockTimestamp: blockTimestamp,
                token0VolumeCumulative: last.token0VolumeCumulative + 
                    int256(last.token0Volume) * int256(uint256(delta)) +
                    int256(token0Volume),
                token1VolumeCumulative: last.token1VolumeCumulative +
                    int256(last.token1Volume) * int256(uint256(delta)) +
                    int256(token1Volume),
                token0Volume: sameBlock ? last.token0Volume + token0Volume : token0Volume,
                token1Volume: sameBlock ? last.token1Volume + token1Volume : token1Volume,
                initialized: true
            });
        }
    }

    /// @notice Initialize the oracle array by writing the first slot. Called once for the lifecycle of the observations array
    /// @param self The stored oracle array
    /// @param time The time of the oracle initialization, via block.timestamp truncated to uint32
    /// @return cardinality The number of populated elements in the oracle array
    /// @return cardinalityNext The new length of the oracle array, independent of population
    function initialize(Observation[65535] storage self, uint32 time)
        internal
        returns (uint16 cardinality, uint16 cardinalityNext)
    {
        self[0] = Observation({
            blockTimestamp: time,
            token0VolumeCumulative: 0,
            token1VolumeCumulative: 0,
            token0Volume: 0,
            token1Volume: 0,
            initialized: true
        });
        return (1, 1);
    }

    /// @notice Writes an oracle observation to the array
    /// @dev Index represents the most recently written element. cardinality and index must be tracked externally.
    /// If the index is at the end of the allowable array length (according to cardinality), and the next cardinality
    /// is greater than the current one, cardinality may be increased. This restriction is created to preserve ordering.
    /// @param self The stored oracle array
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param blockTimestamp The timestamp of the new observation
    /// @param token0Volume The pool's token0 volume in the new observation
    /// @param token1Volume The pool's token1 volume in the new observation
    /// @param cardinality The number of populated elements in the oracle array
    /// @param cardinalityNext The new length of the oracle array, independent of population
    /// @return indexUpdated The new index of the most recently written element in the oracle array
    /// @return cardinalityUpdated The new cardinality of the oracle array
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int128 token0Volume,
        int128 token1Volume,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        unchecked {
            Observation memory last = self[index];

            // do not update index or cardinality if observation is in the same block
            if (last.blockTimestamp == blockTimestamp) {
                self[index] = transformWritePath(last, blockTimestamp, token0Volume, token1Volume);
                return (index, cardinality);
            }

            // if the conditions are right, we can bump the cardinality
            if (cardinalityNext > cardinality && index == (cardinality - 1)) {
                cardinalityUpdated = cardinalityNext;
            } else {
                cardinalityUpdated = cardinality;
            }

            indexUpdated = (index + 1) % cardinalityUpdated;
            self[indexUpdated] = transformWritePath(last, blockTimestamp, token0Volume, token1Volume);
        }
    }

    /// @notice Prepares the oracle array to store up to `next` observations
    /// @param self The stored oracle array
    /// @param current The current next cardinality of the oracle array
    /// @param next The proposed next cardinality which will be populated in the oracle array
    /// @return next The next cardinality which will be populated in the oracle array
    function grow(Observation[65535] storage self, uint16 current, uint16 next) internal returns (uint16) {
        unchecked {
            if (current == 0) revert OracleCardinalityCannotBeZero();
            // no-op if the passed next value isn't greater than the current next value
            if (next <= current) return current;
            // store in each slot to prevent fresh SSTOREs in swaps
            // this data will not be used because the initialized boolean is still false
            for (uint16 i = current; i < next; i++) {
                self[i].blockTimestamp = 1;
            }
            return next;
        }
    }

    /// @notice comparator for 32-bit timestamps
    /// @dev safe for 0 or 1 overflows, a and b _must_ be chronologically before or equal to time
    /// @param time A timestamp truncated to 32 bits
    /// @param a A comparison timestamp from which to determine the relative position of `time`
    /// @param b From which to determine the relative position of `time`
    /// @return Whether `a` is chronologically <= `b`
    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        unchecked {
            // if there hasn't been overflow, no need to adjust
            if (a <= time && b <= time) return a <= b;

            uint256 aAdjusted = a > time ? a : a + 2 ** 32;
            uint256 bAdjusted = b > time ? b : b + 2 ** 32;

            return aAdjusted <= bAdjusted;
        }
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a target, i.e. where [beforeOrAt, atOrAfter] is satisfied.
    /// The result may be the same observation, or adjacent observations.
    /// @dev The answer must be contained in the array, used when the target is located within the stored observation
    /// boundaries: older than the most recent observation and younger, or the same age as, the oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation recorded before, or at, the target
    /// @return atOrAfter The observation recorded at, or after, the target
    function binarySearch(Observation[65535] storage self, uint32 time, uint32 target, uint16 index, uint16 cardinality)
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        unchecked {
            uint256 l = (index + 1) % cardinality; // oldest observation
            uint256 r = l + cardinality - 1; // newest observation
            uint256 i;
            while (true) {
                i = (l + r) / 2;

                beforeOrAt = self[i % cardinality];
                atOrAfter = self[(i + 1) % cardinality];

                bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

                // check if we've found the answer!
                if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

                if (!targetAtOrAfter) r = i - 1;
                else l = i + 1;
            }
        }
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a given target, i.e. where [beforeOrAt, atOrAfter] is satisfied
    /// @dev Assumes there is at least 1 initialized observation.
    /// Used by observeSingle() to compute the counterfactual accumulator values as of a given block timestamp.
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation which occurred at, or before, the given timestamp
    /// @return atOrAfter The observation which occurred at, or after, the given timestamp
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        unchecked {
            // optimistically set before to the newest observation
            beforeOrAt = self[index];

            // if the target is chronologically at or after the newest observation, we can early return
            if (lte(time, beforeOrAt.blockTimestamp, target)) {
                if (beforeOrAt.blockTimestamp == target) {
                    // if newest observation equals target, we're in the same block, so we can ignore atOrAfter
                    return (beforeOrAt, atOrAfter);
                } else {
                    // otherwise, we need to transform
                    return (beforeOrAt, transformReadPath(beforeOrAt, target));
                }
            }

            // now, set before to the oldest observation
            beforeOrAt = self[(index + 1) % cardinality];
            if (!beforeOrAt.initialized) beforeOrAt = self[0];

            // ensure that the target is chronologically at or after the oldest observation
            if (!lte(time, beforeOrAt.blockTimestamp, target)) {
                revert TargetPredatesOldestObservation(beforeOrAt.blockTimestamp, target);
            }

            // if we've reached this point, we have to binary search
            return binarySearch(self, time, target, index, cardinality);
        }
    }

    /// @dev Reverts if an observation at or before the desired observation timestamp does not exist.
    /// 0 may be passed as `secondsAgo' to return the current cumulative values.
    /// If called with a timestamp falling between two observations, returns the counterfactual accumulator values
    /// at exactly the timestamp between the two observations.
    /// @param self The stored oracle array
    /// @param time The current block timestamp
    /// @param secondsAgo The amount of time to look back, in seconds, at which point to return an observation
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param cardinality The number of populated elements in the oracle array
    /// @return token0VolumeCumulative The token0Volume * time elapsed since the pool was first initialized, as of `secondsAgo`
    /// @return token1VolumeCumulative The token1Volume * time elapsed since the pool was first initialized, as of `secondsAgo`
    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int256 token0VolumeCumulative, int256 token1VolumeCumulative) {
        unchecked {
            if (secondsAgo == 0) {
                Observation memory last = self[index];
                if (last.blockTimestamp != time) last = transformReadPath(last, time);
                return (last.token0VolumeCumulative, last.token1VolumeCumulative);
            }

            uint32 target = time - secondsAgo;

            (Observation memory beforeOrAt, Observation memory atOrAfter) =
                getSurroundingObservations(self, time, target, index, cardinality);

            if (target == beforeOrAt.blockTimestamp) {
                // we're at the left boundary
                return (beforeOrAt.token0VolumeCumulative, beforeOrAt.token1VolumeCumulative);
            } else if (target == atOrAfter.blockTimestamp) {
                // we're at the right boundary
                return (atOrAfter.token0VolumeCumulative, atOrAfter.token1VolumeCumulative);
            } else {
                // we're in the middle
                uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
                uint32 targetDelta = target - beforeOrAt.blockTimestamp;
                return (
                    beforeOrAt.token0VolumeCumulative
                        + ((atOrAfter.token0VolumeCumulative - beforeOrAt.token0VolumeCumulative) / int256(uint256(observationTimeDelta)))
                            * int256(uint256(targetDelta)),
                    beforeOrAt.token1VolumeCumulative
                        + ((atOrAfter.token1VolumeCumulative - beforeOrAt.token1VolumeCumulative) / int256(uint256(observationTimeDelta)))
                            * int256(uint256(targetDelta))
                );
            }
        }
    }

    /// @notice Returns the accumulator values as of each time seconds ago from the given time in the array of `secondsAgos`
    /// @dev Reverts if `secondsAgos` > oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param secondsAgos Each amount of time to look back, in seconds, at which point to return an observation
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param cardinality The number of populated elements in the oracle array
    /// @return token0VolumeCumulatives The token0Volumes * time elapsed since the pool was first initialized, as of each `secondsAgo`
    /// @return token1VolumeCumulatives The token1Volumes * time elapsed since the pool was first initialized, as of each `secondsAgo`
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        uint16 index,
        uint16 cardinality
    ) internal view returns (
        int256[] memory token0VolumeCumulatives,
        int256[] memory token1VolumeCumulatives
    ) {
        unchecked {
            if (cardinality == 0) revert OracleCardinalityCannotBeZero();

            token0VolumeCumulatives = new int256[](secondsAgos.length);
            token1VolumeCumulatives = new int256[](secondsAgos.length);
            for (uint256 i = 0; i < secondsAgos.length; i++) {
                (token0VolumeCumulatives[i], token1VolumeCumulatives[i]) =
                    observeSingle(self, time, secondsAgos[i], index, cardinality);
            }
        }
    }
}
