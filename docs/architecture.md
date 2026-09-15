# Statics Lottery Architecture

Statics Lottery is a standalone ERC-20 lottery implemented behind one
`StaticsLotteryDiamond` address. Governance creates immutable Round Configuration Versions, and
the first paid ticket purchase opens a Round by snapshotting one version and the current
integration version. Multiple Rounds may be active concurrently, including Rounds whose Payment
Tokens differ.

The Lottery does not modify the Statics protocol. STATICS, USDG, WETH, or another approved asset
is simply the ERC-20 Payment Token selected by a Round Configuration Version. Native ETH is never
ticket principal.

## System boundaries

```text
buyers and public maintainers
            |
            v
  StaticsLotteryDiamond
   |       |        |
   |       |        +---- exact same-token proceeds ----> OperatorFeeRouter
   |       +------------- exact ERC-20 custody ----------> Payment Token
   +--------------------- committed beacon reads --------> EqualFiDrandRegistry
            |
            +------------- pull Treasury delivery -------> Treasury recipient
```

The Lottery owns Round lifecycle and accounting. It deliberately delegates two concerns:

- `EqualFiDrandRegistry` verifies drand Quicknet proofs and caches canonical randomness. The
  Lottery contains no BLS or EIP-2537 implementation.
- `OperatorFeeRouter` applies Operator ownership, activation weight, forfeiture, reward-index, and
  claim rules. The Lottery records and forwards only a versioned same-token Operator share.

The Registry and Router are configured through append-only Integration Versions. A Round keeps
the version it opened with, so later governance changes cannot redirect that Round's randomness
or Operator liability.

## Single-address Diamond

All public Lottery calls use the Diamond address. The fallback looks up `msg.sig` in Diamond
storage and delegates to the selected facet. The initial production surface contains:

| Facet | Responsibility |
|---|---|
| `DiamondCutFacet` | Authority-gated EIP-2535 add, replace, remove, and initializer execution |
| `DiamondLoupeFacet` | Facet and selector introspection |
| `GovernanceFacet` | Configuration versions, integration versions, roles, pause, concurrency, and finalization |
| `LotteryFacet` | Opening, exact ticket purchases, sellout commitment, and unsold expiration |
| `SettlementFacet` | Registry consumption, winner derivation, and accounting-only settlement |
| `ClaimsFacet` | Pull-based winner, refund, and finalizer claims |
| `RevenueFacet` | Retryable Operator/Treasury delivery and canonical-token surplus handling |
| `LotteryViewFacet` | Round, configuration, ticket-range, and accounting reads |

No facet owns an independent balance or proxy. Delegatecalls operate on explicitly namespaced
Diamond storage.

## Storage model

The implementation uses stable `keccak256` namespace slots rather than a shared linear layout:

| Namespace | Contents |
|---|---|
| `statics.lottery.diamond.storage.v1` | selectors, facet indexes, authority, finalization latch |
| `statics.lottery.storage.game.v1` | configurations, Rounds, ticket ranges, refund credits, concurrency indexes |
| `statics.lottery.storage.integration.v1` | append-only Registry/Router versions |
| `statics.lottery.storage.accounting.v1` | per-token liabilities, versioned Operator buckets, finalizer credits, admitted tokens |
| `statics.lottery.storage.governance.v1` | guardian, Treasury recipient, pause state |
| `statics.lottery.storage.reentrancy.v1` | Diamond-wide value-path reentrancy state |

An upgrade must reuse these exact layouts or introduce a new namespace. Adding, reordering, or
retyping fields inside a live namespace is not safe merely because the facet compiles.

## Round lifecycle

```text
None
  |
  | openRound(configVersion, firstPurchase)
  v
Open ---------------------------> Expired
  |                                 |
  | final ticket                    | claimRefund()
  | commits one future beacon       v
  v                               refund paid
SoldOut
  |
  | settleRound(exact beacon proof)
  v
Settled
  |
  +--> claimWinner()
  +--> claimFinalizerTips()
  +--> flushTreasury()
  +--> flushOperatorRevenue()
```

`openRound` is the first purchase, not a free empty-Round operation. It requires an enabled
configuration, global capacity, no other nonterminal Round for that configuration, and a current
Integration Version. When the Operator share is nonzero, the configured Router must also be
bootstrapped, have positive synchronized weight, and accept the Payment Token.

Every successful purchase:

1. records an increasing cumulative ticket range for the buyer;
2. increases Round receipts and the buyer's potential refund credit;
3. increases active escrow for the Round's Payment Token; and
4. pulls exactly `ticketPrice * quantity` by verifying both buyer spend and Diamond receipt.

If the last ticket sells, the same transaction changes the Round to `SoldOut`, records
`selloutAt`, and permanently stores one Quicknet target strictly after the supplied L2 boundary.
A sold-out Round cannot expire, cancel, accept more tickets, or change its beacon.

An unsold Round may be expired after its sales deadline. Expiration moves all of that Round's
receipts from active escrow to participant refund liability. It creates no winner, Operator,
Treasury, or finalizer revenue.

## Settlement and exits

Settlement verifies or reuses only the Round's committed Registry beacon, derives one
domain-separated seed, resolves the winning ticket through cumulative ranges, and records the
result. It performs no Payment Token, winner, Treasury, or Router value transfer.

That separation is intentional. Token delivery and external Router availability cannot reverse or
block the Round's terminal state. Claims and revenue delivery are independent pull operations.
Each guarded value-moving path clears its liability before interaction and relies on atomic EVM
rollback if an external call or exact-delta check fails.

Pausing affects only `openRound` and `buyTickets`. It cannot prevent settlement, expiration,
winner claims, refunds, finalizer claims, Treasury delivery, Operator retries, surplus handling, or
views.

## Progressive immutability

Before finalization, the configured authority can add, replace, or remove selectors and can run an
initializer through delegatecall. Production governance is therefore expected to put the Lottery
authority behind an external timelock and review every selector and storage-layout change. The
Lottery contract itself does not implement that delay.

`finalizeProtocol` irreversibly sets `cutsDisabled`. Afterward every Diamond cut reverts and no
callable path can restore code mutability. Finalization does not remove ordinary configuration
governance: new immutable versions, enable flags, concurrency, roles, and pause controls remain
available for future Rounds. Existing Round snapshots and liabilities remain unchanged in either
case.

See [governance.md](governance.md) for the role model and the distinction between code
finalization and optional external governance renunciation.

## Chain trust boundary

drand removes application-level entropy selection by buyers, proof submitters, finalizers, and
ordinary configuration governance. It does not provide transaction inclusion or L2 timestamp
freshness. Statics Lottery assumes Robinhood Chain supplies canonical ordering, state availability,
and eventual inclusion according to its rules.

A sequencer that deliberately withholds or reorders the final purchase, or holds permitted L2 time
stale until a favorable public beacon exists, violates that accepted chain assumption. This is a
chain-level trust failure, not a capability the Lottery or drand can independently repair. See
[randomness.md](randomness.md) for the exact claim boundary.

## Testnet realization

The disposable Robinhood Testnet release preserves the single-address architecture and records:

- the Diamond, facets, selectors, code hashes, roles, integrations, and initial configurations in
  [`deployments/robinhood-testnet/lottery.json`](../deployments/robinhood-testnet/lottery.json);
- the Registry deployment and concrete EIP-2537 checks in
  [`deployments/robinhood-testnet/registry.json`](../deployments/robinhood-testnet/registry.json);
  and
- concurrent WETH/STATICS Rounds, live Quicknet settlement, refunds, claims, Router retries,
  upgrade storage preservation, and finalization in
  [`deployments/robinhood-testnet/lifecycle.json`](../deployments/robinhood-testnet/lifecycle.json).

Those addresses and roles are a bounded test rehearsal. They are not a production governance or
deployment recommendation.
