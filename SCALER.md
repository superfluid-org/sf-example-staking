# Scaling Factor for Superfluid Staking

## Problem Statement

In Superfluid's staking contract, we encounter a precision issue when distributing rewards. This problem arises from Solidity's inability to handle decimal numbers, potentially leading to a situation where the total flow rate divided by the total units is less than 1, resulting in zero rewards for stakers.

## Formal Description

Let's define our variables:

- $T_1$: Total supply of the staked token
- $T_2$: Total supply of the rewards token
- $N$: Number of members in the pool
- $P$: Total units in the pool
- $F$: Total flow rate of rewards
- $S$: Scaling factor

We make the following assumptions:

1. The total flow rate is small: $F = 0.001\% \cdot T_2 / \text{year}$
2. The total amount staked is significant: $P = 0.5 \cdot T_1 / S$

## Objective

Our goal is to find a condition on the scaling factor $S$ such that the remainder of the flow rate distribution is insignificant even in the long run. Specifically, we want:

$$\text{Remainder}(F/P) \cdot P \cdot 1\text{ year} < 0.001\% \cdot T_2$$

## Derivation

Starting with our objective inequality:

$$\text{Remainder}(F/P) \cdot P \cdot 1\text{ year} < 0.001\% \cdot T_2$$

Substituting our assumptions:

$$\text{Remainder}\left(\frac{0.001\% \cdot T_2 / \text{year}}{0.5 \cdot T_1 / S}\right) \cdot (0.5 \cdot T_1 / S) \cdot 1\text{ year} < 0.001\% \cdot T_2$$

Simplifying:

$$\text{Remainder}\left(\frac{0.002\% \cdot T_2 \cdot S}{T_1 \cdot \text{year}}\right) \cdot \frac{T_1}{2S} \cdot 1\text{ year} < 0.001\% \cdot T_2$$

To ensure this inequality holds, we want the fraction inside the Remainder function to be significantly larger than 1. Let's say we want it to be at least 1000:

$$\frac{0.002\% \cdot T_2 \cdot S}{T_1 \cdot \text{year}} > 1000$$

Solving for $S$:

$$S > \frac{1000 \cdot T_1 \cdot \text{year}}{0.002\% \cdot T_2}$$

$$S > \frac{50,000,000 \cdot T_1 \cdot \text{year}}{T_2}$$

Converting year to seconds (assuming 365 days per year):

$$S > \frac{50,000,000 \cdot T_1 \cdot 365 \cdot 24 \cdot 3600}{T_2}$$

$$S > \frac{1,576,800,000,000,000 \cdot T_1}{T_2}$$

## Conclusion

The scaling factor $S$ should satisfy:

$$S > \frac{1,576,800,000,000,000 \cdot T_1}{T_2}$$

This means that the scaling factor $S$ should be greater than approximately 1.5768 trillion times the ratio of the total supply of the staked token to the total supply of the rewards token.

By using this scaling factor, we ensure that the flow rate per unit is always significantly larger than 1, minimizing the impact of integer division and ensuring that the accumulated remainder over a year is less than 0.001% of the total supply of the reward token.

## Implementation

In the smart contract, when a user stakes an amount $A$ of token $T_1$, we should allocate $A/S$ units to them in the Superfluid pool. This ensures that the total units in the pool remain manageable while still accurately representing each user's stake.

```solidity
function stake(uint256 amount) external {
    // ... other checks and operations ...
    uint128 units = uint128(amount / scalingFactor);
    superToken.updateMemberUnits(pool, address(claimContracts[msg.sender]), units);
    // ... emit events, etc ...
}
```

By implementing this scaling factor, we can maintain precision in reward distribution while working within the constraints of Solidity's integer arithmetic.