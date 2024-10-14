# SFLAX, staked Flax

## Introduction

Staked Flax is the next iteration in Flax incentives which seeks to address the following concerns:
1. Over inflating Flax which comes due eventually
2. Long lockup durations of rewards makes the investor uncertain of their eventual return in the face of market volatility
3. Every Flax dapp has to grapple with lockup incentives to balance the rewards that dapp offers.

## Initial Reflax approach
Initially Reflax would offer boosted rewards for locking Flax for long durations, similar to CRV. In this way, Reflax could pay out rewards immediately without being concerned of inflationary concerns, since the user has already secured a deflationary position.

## Generalized
Instead of locking Flax on each dapp such as Reflax, it would be ideal to offer a place to lock in one place. An ERC20 token, SFlax, is issued for every Flax-minute of locking. SFlax represents Flax-minutes already accrued. Staking users can increase the rate of earning by increasing the duration of lockup.

### Building and Testing
Solidity files with prefix .not.sol are to be excluded from compilaiton. LimboDAO is an example of a file which is used for easy reference. If your codebase includes such files, use the test.sh script to skip compilation of these files.

Forge install can often lead to conflicts in libraries. I've found it's easier to skip this tool and just manually clone into the lib directory. See the *remappings.txt* file for all the library modules.
