# Statics Lottery formal targets

This package defines bounded symbolic properties over the production Lottery facets. Formal
execution is allowed only in CI or on the dedicated verification system described in the private
operator tooling. Do not install, probe, or invoke Halmos on an ordinary development host.

## Required Halmos rules

- `check_selloutCommitmentIsStrictlyFuture`
- `check_selloutCommitmentMatchesRegistrySelection`
- `check_selloutCommitmentIgnoresCatalogChanges`
- `check_settlementConservesRevenueAndIsolatesTokens`
- `check_winnerClaimCannotRepeat`
- `check_refundClaimCannotRepeat`
- `check_operatorFlushIsAtomicAndTokenIsolated`
- `check_cutFinalizationCannotBeReversed`

Every required rule must complete without a counterexample, timeout, unknown result, panic, or
bounded-loop warning. A compiled harness is not a proof result.

## Model bounds

The commitment rule calls the shared production `_commitSelloutTarget` implementation with every
`uint32` randomness delay and a deterministic Registry summary whose first future round is exactly
`timestamp + 1`. The live `_commitSellout` path resolves its Registry and delay from the Round's
snapshotted integration and configuration before calling this same helper. The rule proves the
stored target is strictly future, uncached when selected, and unchanged by later mutation of the
configuration catalog. It does not prove the preceding ticket purchase, integration-version
resolution, the one-way lifecycle gate around `_commitSellout`, or Diamond dispatch; Foundry
integration and stateful invariants cover those paths. The Registry summary does not prove
Quicknet arithmetic or cryptography; those belong to the separate `EqualFiDrandRegistry` proof
package.

The settlement rule calls the shared production allocation and accounting implementations for one
bounded Round. It covers every nonzero `uint96` gross amount, every valid Winner and Operator BPS
value, and every `uint96` Finalizer Tip. The harness starts the payment token and one unrelated
token exactly solvent, then proves revenue conservation, payment-token solvency,
aggregate/versioned Operator equality, and no mutation of the unrelated token's custody or
accounting. It does not prove Registry acquisition, ticket-owner lookup, or the external
`settleRound` state gate; concrete integration tests cover those paths.

The claim rules call the production `ClaimsFacet` for every nonzero `uint96` winner or refund
amount using an exact-transfer ERC-20. They prove one successful delivery clears the matching
claim and aggregate liability, transfers the exact amount, and makes an identical second claim
fail without additional delivery.

The Operator rule calls the production `RevenueFacet` for payment and isolated-token amounts in
`[1, type(uint64).max]`. It explores both exact Router acceptance and atomic Router rejection. It
proves the payment-token liability, custody, and exact allowance either all advance together or
all remain unchanged, while the unrelated token is untouched. Router reward-index math and
Operator ownership accounting remain outside this Lottery model.

The cut rule deploys the production Diamond, `DiamondCutFacet`, and `GovernanceFacet`, installs
only the finalization selectors, finalizes once, and proves both later Diamond cuts and repeated
finalization fail while the finalized flag remains set. It does not prove governance-key honesty
or timelock liveness.

## Trusted computing base and exclusions

The proofs trust Solidity 0.8.30 compilation, Halmos EVM semantics, Keccak-256, exact behavior of
the bounded ERC-20 and external-dependency summaries, and the synthetic initial states documented
above. Direct storage seeding establishes reachable preconditions only; each claimed transition
then calls production facet code.

The package does not prove drand cryptography or network liveness, `OperatorFeeRouter` internal
distribution, arbitrary ERC-20 behavior, governance honesty, compiler correctness, target-client
correctness, or Robinhood runtime behavior. Foundry fuzz/invariant tests, the Registry proof
package, integration tests, audit review, and Robinhood testnet validation are separate evidence.
