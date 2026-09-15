# Payment Token Accounting

Statics Lottery accounts independently in each Round's ERC-20 Payment Token. It does not normalize
decimals, quote values in USD, swap assets, or privilege WETH. Every ticket price, claim, fee, and
surplus amount is expressed in the selected token's base units.

## Supported token policy

Governance may configure an ERC-20 only when it has one canonical ledger address and is expected
to remain:

- exact-transfer in both directions;
- non-rebasing and balance-stable outside explicit transfers;
- compatible with `SafeERC20` calls and repeated balance queries; and
- operational for claims and Router/Treasury delivery.

Runtime code checks each transfer, but it cannot prove future behavior. Token upgrades, fees,
rebases, pauses, blocklists, callbacks, or alternate facades over the same ledger remain governance
and monitoring concerns. The complete admission policy is in
[payment-token-policy.md](payment-token-policy.md).

Native ETH is not a Payment Token. The Diamond rejects ordinary native transfers. WETH is an
ordinary configurable ERC-20; forced native ETH is tracked only as separate Treasury surplus.

## Per-token accounting

For each admitted token address `asset`, the Diamond stores:

| Field | Meaning |
|---|---|
| `activeRoundEscrow` | Ticket receipts still backing open or sold-out Rounds |
| `winnerLiability` | Settled proceeds not yet claimed by winners |
| `refundLiability` | Expired-Round principal not yet refunded |
| `finalizerLiability` | Recorded settlement tips not yet claimed |
| `pendingOperatorRevenueTotal` | Operator proceeds not yet accepted by a Router |
| `treasuryAvailable` | Treasury proceeds or absorbed surplus not yet delivered |

The recorded amount for one token is:

```text
accounted(asset) =
    activeRoundEscrow
  + winnerLiability
  + refundLiability
  + finalizerLiability
  + pendingOperatorRevenueTotal
  + treasuryAvailable
```

For a compatible canonical token, the solvency condition is:

```text
IERC20(asset).balanceOf(StaticsLotteryDiamond) >= accounted(asset)
```

Every mapping key is the Round's snapshotted Payment Token. A WETH Round cannot debit a STATICS
liability, and one token's excess balance cannot satisfy another token's shortage.

## Purchase accounting

For ticket quantity `q`:

```text
amount = ticketPrice * q
```

Before calling the token, the transaction records:

```text
round.soldTickets                  += q
round.receipts                     += amount
refundCredit[roundId][buyer]       += amount
assetAccounting[token].activeRoundEscrow += amount
```

It then calls `transferFrom(buyer, Diamond, amount)` and measures four balances:

```text
buyerBefore - buyerAfter       == amount
diamondAfter - diamondBefore   == amount
```

Both equalities are required. Receiver-fee, sender-fee, rebasing, balance-drift, false-return, or
otherwise inexact behavior reverts the complete transaction, including the earlier storage writes.
A direct token transfer to the Diamond never creates tickets or refund credit.

## Successful settlement

Let `gross = round.receipts` and `D = 10_000`:

```text
winner       = floor(gross * winnerBps / D)
protocol     = gross - winner
operator     = floor(protocol * operatorProtocolBps / D)
treasuryGross = protocol - operator
finalizer    = min(finalizerTip, treasuryGross)
treasury     = treasuryGross - finalizer
```

The final subtraction gives all division remainder to Treasury. The exact conservation identity is:

```text
winner + operator + treasury + finalizer == gross
```

Settlement performs only storage reclassification:

```text
activeRoundEscrow                              -= gross
winnerLiability                               += winner
pendingOperatorRevenue[integration][token]    += operator
pendingOperatorRevenueTotal                   += operator
treasuryAvailable                             += treasury
finalizerCredits[token][settler]              += finalizer
finalizerLiability                            += finalizer
```

It does not call the Payment Token, winner, Treasury recipient, or Operator Router. A blocked
recipient or unavailable Router therefore cannot prevent the Round from becoming `Settled`.

## Unsold expiration and refunds

After an unsold open Round reaches `expiresAt`, anyone may expire it:

```text
activeRoundEscrow -= round.receipts
refundLiability   += round.receipts
```

No winner, Operator, Treasury, or finalizer allocation is created. Each successful purchase has
already increased that buyer's `refundCredit` by the exact principal paid, so the sum of credits
equals the Round's receipts.

`claimRefund` clears the caller's credit and reduces aggregate refund liability before pushing the
same amount. A transfer failure or inexact delta reverts both changes. A successful claim cannot be
repeated.

## Winner and finalizer claims

The recorded winner alone may claim `round.winnerClaimable`, but may select any nonzero receiver
other than the Diamond. Finalizer tips are aggregated by token and finalizer address. Each claim:

1. reads the caller's recorded credit;
2. sets that credit to zero;
3. decreases the matching per-token aggregate liability;
4. transfers the exact amount; and
5. verifies Diamond spend and receiver receipt.

The shared Diamond-wide reentrancy guard covers every value-moving claim. Atomic rollback preserves
the entitlement if the receiver or token interaction fails.

## Operator revenue

Operator proceeds remain bucketed by both the Round's snapshotted Integration Version and Payment
Token:

```text
pendingOperatorRevenue[integrationVersion][asset]
```

The per-token aggregate changes by the same amount on every settlement and flush. A caller cannot
flush more than the selected bucket. Before delivery, the Lottery rechecks Router bootstrap,
positive synchronized weight, asset registration, and deposit enablement.

Delivery uses an exact temporary allowance:

1. decrement the version/token bucket and aggregate liability;
2. force-approve the configured Router for exactly `amount`;
3. call `addRewards(asset, amount)`;
4. clear the allowance; and
5. require exact Lottery spend and Router receipt.

Any readiness, token, allowance, or Router failure reverts the whole transaction and preserves the
pending liability for retry. The Lottery never swaps, wraps, or converts the Operator share.
Individual Operator entitlement begins only after the Router accepts the contribution and applies
its own then-current synchronized weights. See
[operator-router-integration.md](operator-router-integration.md).

## Treasury accounting

`flushTreasury(asset, amount)` is permissionless, but its receiver is always the current
governance-configured Treasury recipient. The caller cannot redirect it. The function caps `amount`
at `treasuryAvailable`, decreases that field before interaction, and requires an exact outbound
transfer. Winner, refund, finalizer, and Operator liabilities are never Treasury-withdrawable.

Changing the Treasury recipient affects later delivery of already-recorded Treasury funds, but it
does not change any participant or Operator entitlement.

## Surplus

For a governance-admitted canonical token:

```text
availableSurplus(asset) = max(balanceOf(Diamond) - accounted(asset), 0)
```

Any account may absorb that amount into `treasuryAvailable`; a later Treasury flush performs the
actual transfer. Arbitrary unadmitted addresses are rejected before a balance query. Absorption
cannot decrease or reclassify participant or Operator liabilities.

The address-based model cannot discover that two token addresses control the same underlying
ledger. Governance and deployment validation must never admit both aliases. This is an explicit
offchain admission invariant, not an onchain guarantee.

Forced native ETH is separate. `flushNativeSurplus` sends the Diamond's native balance only to the
configured Treasury recipient and never touches ERC-20 accounting.

## Evidence

The following layers exercise the accounting model independently:

- unit and integration tests cover exact ingress/egress, fee and sender-fee tokens, rebasing or
  drift behavior, claims, refunds, Router rollback, surplus, and same-ledger aliases;
- fuzz and stateful invariant tests cover revenue conservation, solvency, terminal monotonicity,
  concurrent Rounds, and cross-token isolation;
- the Lottery Halmos report proves bounded allocation/accounting transitions, claim
  non-repeatability, Operator flush atomicity, and isolated-token non-mutation; and
- [`deployments/robinhood-testnet/lifecycle.json`](../deployments/robinhood-testnet/lifecycle.json)
  records concurrent WETH and STATICS Rounds whose claims, refund, Treasury proceeds, and Operator
  funding return the Diamond's recorded liabilities and token balances to zero.

The proof bounds and exclusions are summarized in
[audit-scope.md](audit-scope.md#formal-verification-boundary).
