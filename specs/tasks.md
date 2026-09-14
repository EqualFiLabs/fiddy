# Implementation Plan: Statics Lottery

## Overview

Build Statics Lottery as two cooperating systems:

1. a standalone immutable `EqualFiDrandRegistry` providing reusable drand Quicknet verification and cached canonical randomness; and
2. an upgradeable EIP-2535 `StaticsLotteryDiamond` containing governance-enabled ERC-20 Round configurations, concurrent multi-token ticket sales, settlement, claims, per-token Treasury accounting, and Operator revenue routing.

Implementation proceeds bottom-up. The Quicknet registry is built and validated independently first. The Lottery then reuses EqualFi's existing Diamond/progressive-immutability patterns and integrates the existing `OperatorFeeRouter`.

All economic and operational configuration affects future Rounds only. Governance creates immutable Round Configuration Versions and enables or disables them for new Round opening. Each Round snapshots its Payment Token, terms, and integration version, allowing concurrent active Rounds to use different tokens without sharing accounting.

## Tasks

- [ ] 1. Create the shared drand registry project foundation
  - [ ] 1.1 Create the `EqualFiDrandRegistry` project structure
    - Details: Create the standalone registry repository/project with Foundry configuration, source, interfaces, tests, scripts, and deployment directories.
    - New files:
      - `src/EqualFiDrandRegistry.sol`
      - `src/interfaces/IEqualFiDrandRegistry.sol`
      - `src/libraries/QuicknetVerifier.sol`
      - `test/EqualFiDrandRegistry.t.sol`
      - `script/DeployDrandRegistry.s.sol`
    - _Requirements: 7.3, 8.1-8.6, 22.1, 22.5, 23.1-23.4_
  - [ ] 1.2 Pin the BLS12-381 verification dependency
    - Details: Pin a reviewed `bls-solidity` implementation/commit compatible with EIP-2537. Do not modify elliptic-curve primitives except where strictly required for integration.
    - Details: Record the exact upstream commit and any audit lineage in repository documentation.
    - _Requirements: 8.1-8.6, 22.5, 23.4_
  - [ ] 1.3 Define the stable registry interface
    - Details: Implement `firstRoundAfter`, `roundTime`, `hasSig`, `randomnessOf`, `postedAt`, and permissionless `postSig`.
    - _Requirements: 7.3-7.5, 8.1-8.5, 21.8, 22.1_

- [ ] 2. Implement Quicknet verification
  - [ ] 2.1 Add canonical Quicknet constants
    - Details: Add the official Quicknet genesis timestamp, 3-second period, DST, public key, and signature-size constants.
    - Details: Treat these as external network/cryptographic constants rather than Lottery tuning parameters.
    - _Requirements: 1.4, 8.1-8.6, 22.7_
  - [ ] 2.2 Implement Quicknet round arithmetic
    - Details: Implement `roundTime(round)` and `firstRoundAfter(timestamp)` and test pre-genesis and exact-boundary cases.
    - _Requirements: 7.2-7.4, 8.3_
  - [ ] 2.3 Implement 48-byte compressed signature verification
    - Details: Decode native drand compressed G1 signatures and verify against the Quicknet G2 key using EIP-2537.
    - _Requirements: 8.1-8.6, 23.3-23.4_
  - [ ] 2.4 Implement 96-byte uncompressed signature verification
    - Details: Accept valid pre-decompressed G1 signatures and reject unsupported lengths.
    - _Requirements: 8.1-8.6, 23.3-23.4_
  - [ ] 2.5 Normalize verified signatures before deriving randomness
    - Details: Convert both valid representations into one canonical G1 representation before hashing; never hash relayer-supplied raw signature bytes for protocol randomness.
    - _Requirements: 8.1-8.6, 9.1, 22.5_

- [ ] 3. Implement shared registry state and caching
  - [ ] 3.1 Add per-round beacon storage
    - Details: Store canonical randomness and `postedAt` for each verified Quicknet Round.
    - _Requirements: 8.3-8.5, 21.8_
  - [ ] 3.2 Implement permissionless `postSig`
    - Details: First successful verification stores the beacon and returns `true`; cached rounds return `false` without repeating verification.
    - _Requirements: 8.3-8.5, 10.1, 18.1, 22.1_
  - [ ] 3.3 Emit complete registry events
    - Details: Emit round, poster, canonical randomness, and submitted proof representation for provenance without requiring dynamic signature storage.
    - _Requirements: 21.8_
  - [ ] 3.4 Keep registry immutable and administrator-free
    - Details: No proxy, owner controls, mutable Quicknet keys, Lottery-specific logic, or privileged randomness replacement.
    - _Requirements: 8.6, 16.3, 22.1, 22.5, 22.7_

- [ ] 4. Prove the shared registry independently
  - [ ] 4.1 Add official Quicknet test vectors
    - Details: Verify at least one known real Quicknet Round/signature pair and document its source.
    - _Requirements: 8.1-8.6, 23.3-23.4_
  - [ ] 4.2 Test equivalent 48-byte and 96-byte representations
    - Details: Demonstrate that both verify and return identical `randomnessOf(round)`.
    - _Requirements: 8.1-8.6, 9.1_
  - [ ] 4.3 Add adversarial registry tests
    - Details: Wrong Round, wrong signature, malformed points, infinity, invalid lengths, duplicate posting, and precompile failure behavior.
    - _Requirements: 8.3-8.6, 20.6_
  - [ ] 4.4 Add fuzz/property tests for round arithmetic
    - Details: Verify `roundTime(firstRoundAfter(t)) > t` and ordering/boundary properties.
    - _Requirements: 7.3-7.4, 8.3_
  - [ ] 4.5 Define the Registry formal-verification package
    - Details: Specify the machine-checked claims, complete-domain expectations, trusted computing base, proof exclusions, and constrained EIP-2537 summaries. Pin the source revision, compiler/settings, dependencies, formal specifications/tools, and runtime bytecode hash in the proof report.
    - _Requirements: 25.1, 25.9-25.13_
  - [ ] 4.6 Prove contract-side Quicknet transformations
    - Details: Prove Round arithmetic, exact Round serialization, public-key and DST binding, compressed-point parsing/decompression, uncompressed decoding, field and infinity rejection, canonical normalization, and equivalent randomness for matching valid 48-byte and 96-byte representations.
    - _Requirements: 8.1-8.6, 25.2-25.6_
  - [ ] 4.7 Prove Registry acceptance and cache immutability
    - Details: Against compiled EVM runtime bytecode, prove verification-success equivalence under constrained EIP-2537 summaries, failure-path non-mutation, first-write immutability, duplicate-call behavior, and absence of a privileged bypass or replacement path.
    - _Requirements: 8.3-8.6, 25.1, 25.3-25.8_
  - [ ] 4.8 Validate proof soundness and concrete assumptions
    - Details: Add vacuity and mutation checks, reject timeout or unknown results for required rules, differentially test official Quicknet intermediate values, and prepare the target-chain EIP-2537 conformance harness executed in Task 20. Keep runtime results separate from formal results.
    - _Requirements: 23.3-23.4, 25.9-25.13_

- [ ] 5. Checkpoint: shared randomness primitive
  - [ ] 5.1 Run complete registry unit, fuzz, and known-vector suite.
  - [ ] 5.2 Confirm both signature transports remain supported.
  - [ ] 5.3 Run every release-required Registry formal rule with no timeout, unknown, or vacuous result.
  - [ ] 5.4 Confirm the proof report pins its artifacts and states every assumption and exclusion.
  - [ ] 5.5 Ensure all tests and proof gates pass before proceeding.
    - _Requirements: 7, 8, 9, 22, 23, 25_

- [ ] 6. Build the Lottery Diamond foundation
  - [ ] 6.1 Create the Lottery project structure
    - Details: Create `src/facets`, `src/libraries`, `src/interfaces`, `src/shared`, `src/initializers`, `test`, `script`, and deployment directories.
    - _Requirements: 22.1-22.5, 24.1_
  - [ ] 6.2 Adapt the existing EqualFi Diamond implementation
    - Details: Reuse/adapt Burntato selector bookkeeping, fallback routing, loupe, and cut model.
    - New files: `src/StaticsLotteryDiamond.sol`, `src/libraries/LibDiamond.sol`, `src/facets/DiamondCutFacet.sol`, `src/facets/DiamondLoupeFacet.sol`, EIP-2535 interfaces/types.
    - _Requirements: 24.1-24.6, 24.12_
  - [ ] 6.3 Implement irreversible cut disabling
    - Details: Add `cutsDisabled`; all future cuts revert once set; no path may restore upgradeability.
    - _Requirements: 24.3-24.8_
  - [ ] 6.4 Add EIP-2535 introspection
    - _Requirements: 21.1-21.8, 24.1_

- [ ] 7. Define Lottery data models and namespaced storage
  - [ ] 7.1 Add shared Lottery types
    - New file: `src/shared/Types.sol`
    - Details: Define `LotteryConfig` with its ERC-20 Payment Token, `IntegrationConfig`, `RoundConfigSnapshot`, `Round`, `RoundStatus`, `TicketRange`, and per-token `AssetAccounting`.
    - _Requirements: 1, 3, 5, 6, 11, 21_
  - [ ] 7.2 Implement namespaced storage domains
    - New file: `src/libraries/LibLotteryStorage.sol`
    - Details: Add isolated game, integration, per-token accounting, governance, and reentrancy namespaces with stable versioned slots.
    - _Requirements: 3.1-3.6, 19, 24.10-24.12_
  - [ ] 7.3 Implement Lottery configuration validation
    - New file: `src/libraries/LibLotteryConfig.sol`
    - Details: Validate Payment Token code, ticket price/count, duration, BPS, limits, global concurrency, and integration addresses while preserving valid zero semantics. Document the governance obligation to approve only exact-transfer, non-rebasing assets without mutable behavior that can strand liabilities.
    - _Requirements: 1.1-1.9_
  - [ ] 7.4 Implement Diamond-wide reentrancy storage
    - New file: `src/libraries/LibReentrancy.sol`
    - _Requirements: 20.1-20.7_
  - [ ] 7.5 Implement exact ERC-20 transfer helpers
    - New file: `src/libraries/LibExactToken.sol`
    - Details: Implement exact inbound and outbound transfers with `SafeERC20`, measuring both sender-spend and receiver-receipt deltas and reverting atomically on any mismatch.
    - _Requirements: 5.3-5.4, 12.4-12.6, 15.6-15.9, 19.2, 19.5-19.7, 20_

- [ ] 8. Implement governance, configuration, and progressive immutability
  - [ ] 8.1 Implement `GovernanceFacet`
    - Details: Create immutable full-struct Round Configuration Versions through timelocked authority; independently enable or disable versions for new Round opening. Existing versions and Rounds remain unchanged.
    - _Requirements: 1.1-1.9, 2.1-2.5, 3.1-3.6_
  - [ ] 8.2 Add integration-version management
    - Details: Version `EqualFiDrandRegistry` and `OperatorFeeRouter`; never mutate historical versions. Payment Tokens belong to immutable Round Configuration Versions rather than the integration route.
    - _Requirements: 3.1-3.6, 13, 22.1-22.7_
  - [ ] 8.3 Implement Treasury recipient management
    - _Requirements: 14.1-14.6_
  - [ ] 8.4 Implement guardian and pause controls
    - Details: Guardian may pause new participation; only timelocked authority may unpause; settlement, expiry, claims, refunds, and revenue flushing remain live.
    - _Requirements: 17.1-17.7, 18.1-18.6_
  - [ ] 8.5 Implement `finalizeProtocol`
    - Details: Timelocked authority may irreversibly set `cutsDisabled = true`; parameter governance remains available.
    - _Requirements: 24.3-24.12_
  - [ ] 8.6 Implement global active-Round concurrency management
    - Details: Governance controls one global active-Round limit across all enabled configuration versions and Payment Tokens; zero disables new Round opening without affecting existing Rounds.
    - _Requirements: 1.2, 4.1-4.7, 18_

- [ ] 9. Implement ticket ranges and Round lifecycle
  - [ ] 9.1 Implement cumulative ticket range library
    - New file: `src/libraries/LibTicketRanges.sol`
    - Details: Append one range per multi-ticket purchase and resolve ownership by binary search.
    - _Requirements: 5.7-5.9, 6.1-6.5_
  - [ ] 9.2 Implement first-purchase Round creation
    - New file: `src/facets/LotteryFacet.sol`
    - Details: `openRound(configVersion, ticketQuantity)` creates a Round from a governance-enabled immutable configuration and performs its first ERC-20 purchase atomically; snapshot Payment Token, config/integration versions, and enforce global concurrency.
    - _Requirements: 3.1-3.6, 4.1-4.7, 5.1-5.11_
  - [ ] 9.3 Implement additional ticket purchases
    - Details: Pull the Round's Payment Token with `SafeERC20`; require buyer spent and Diamond received exactly `ticketPrice * quantity`; enforce ticket availability, status, expiry, and purchase limits; increment buyer refund credit on every purchase.
    - _Requirements: 5.1-5.11, 6.1-6.5, 19.2_
  - [ ] 9.4 Implement atomic Sellout transition
    - Details: Mark sold out, record `selloutAt`, select future Quicknet round from snapshotted delay, reject already-cached target, and store the target permanently.
    - _Requirements: 7.1-7.7, 16.1-16.5_
  - [ ] 9.5 Implement unsold Round expiry
    - Details: Permissionless expiry; convert escrow to participant refund liabilities; allocate zero protocol revenue.
    - _Requirements: 15.1-15.10, 18.2, 19.4_

- [ ] 10. Checkpoint: Diamond + Round lifecycle
  - [ ] 10.1 Verify Round snapshots never change through configuration updates.
  - [ ] 10.2 Verify disabling a configuration blocks only new Round opening.
  - [ ] 10.3 Verify sold-out Rounds cannot expire or accept more tickets.
  - [ ] 10.4 Verify expired Rounds cannot later sell out or settle.
  - [ ] 10.5 Verify concurrent Rounds using different Payment Tokens preserve isolated escrow and refund accounting.
  - [ ] 10.6 Ensure all lifecycle tests pass.
    - _Requirements: 3-7, 15-19, 24_

- [ ] 11. Implement permissionless settlement
  - [ ] 11.1 Create `SettlementFacet`
    - New file: `src/facets/SettlementFacet.sol`
    - _Requirements: 8.1-8.6, 10.1-10.9, 18.1_
  - [ ] 11.2 Consume cached or newly submitted Quicknet randomness
    - Details: Resolve snapshotted registry version; reuse cached proof or submit supplied 48-byte/96-byte signature through the registry.
    - _Requirements: 8.1-8.5, 22.1_
  - [ ] 11.3 Enforce randomness timing invariants
    - Details: Require the committed target and no alternate randomness path.
    - _Requirements: 7.2-7.6, 8.3-8.7, 16.3_
  - [ ] 11.4 Domain-separate the Lottery seed
    - Details: Hash canonical registry randomness, `block.chainid`, Diamond address, and Round ID.
    - _Requirements: 9.1-9.7_
  - [ ] 11.5 Resolve the winner
    - Details: Map seed to ticket index and resolve buyer via range binary search.
    - _Requirements: 6.2-6.5, 9.6-9.7, 10.2_
  - [ ] 11.6 Calculate exact Round allocations
    - Details: Winner, Protocol, Operator, Treasury, and Finalizer; cap tip to Treasury; deterministic rounding to Treasury.
    - _Requirements: 10.6-10.9, 11.1-11.8, 19.3_
  - [ ] 11.7 Convert settlement into per-token liabilities without transferring tokens
    - Details: Record winner claim, Operator pending revenue, Treasury amount, and finalizer credit in the Round's Payment Token; reduce only that token's active escrow exactly once.
    - _Requirements: 10, 11, 12.1, 13.2-13.3, 19, 20_

- [ ] 12. Implement all pull-based claims
  - [ ] 12.1 Create `ClaimsFacet`
    - New file: `src/facets/ClaimsFacet.sol`
    - _Requirements: 12, 15, 18, 19, 20_
  - [ ] 12.2 Implement winner claiming
    - Details: Transfer the Round's Payment Token to an arbitrary nonzero receiver; clear the per-token liability before interaction; require exact sender and receiver deltas; revert preserves the claim.
    - _Requirements: 12.1-12.6, 19.5, 20.1-20.3_
  - [ ] 12.3 Implement expired-Round refunds
    - Details: Exact principal in the Round's Payment Token, no duplicate claims, and failed or inexact transfers preserve entitlement.
    - _Requirements: 15.6-15.9, 19.6, 20.1, 20.3_
  - [ ] 12.4 Implement finalizer tip claims
    - _Requirements: 10.6-10.9, 19.1, 20.1_

- [ ] 13. Implement Operator and Treasury revenue routing
  - [ ] 13.1 Create `RevenueFacet`
    - New file: `src/facets/RevenueFacet.sol`
    - _Requirements: 13, 14, 19, 20, 22_
  - [ ] 13.2 Add versioned pending Operator revenue
    - Details: Maintain pending Operator liabilities by integration version and Payment Token, plus each token's aggregate pending liability.
    - _Requirements: 3.1-3.6, 13.2-13.12, 22.6-22.7_
  - [ ] 13.3 Implement permissionless Operator revenue flush
    - Details: Validate integration-version, Payment-Token, and amount; force-approve the version's Router for the exact amount; call `addRewards(asset, amount)`; reduce liabilities only if the full transaction succeeds.
    - _Requirements: 13.4-13.12, 19.7, 20.5_
  - [ ] 13.4 Validate Operator Router compatibility
    - Details: Pin the reviewed Router implementation/deployment. Before opening a nonzero-Operator-share Round, verify completed bootstrap, nonzero synchronized weight, and that the Round's Payment Token is registered and enabled. Recheck at flush while treating later failures as retryable.
    - _Requirements: 13.1, 13.5-13.10, 22.2-22.4_
  - [ ] 13.5 Implement Treasury accounting and flushing
    - Details: Permissionless per-token flush only to the governance-configured Treasury recipient, using exact-transfer validation.
    - _Requirements: 14.1-14.6, 19.8_
  - [ ] 13.6 Implement provable per-token surplus handling
    - Details: For each ERC-20, surplus equals Diamond token balance minus that token's recorded liabilities and available Treasury revenue; allow explicit absorption into Treasury without touching any token's liabilities. Treat forced native ETH separately as non-Lottery Treasury surplus.
    - _Requirements: 14.1-14.6, 19.9-19.11_

- [ ] 14. Implement complete read/indexer surface
  - [ ] 14.1 Create `LotteryViewFacet`
    - _Requirements: 21.1-21.8_
  - [ ] 14.2 Expose Round/configuration views.
  - [ ] 14.3 Expose ticket range views.
  - [ ] 14.4 Expose solvency/accounting views.
  - [ ] 14.5 Add lifecycle and accounting events.
    - _Requirements: 5.9, 6.2-6.5, 14, 19, 21_

- [ ] 15. Checkpoint: complete Lottery behavior
  - [ ] 15.1 Execute a complete successful Round locally.
  - [ ] 15.2 Execute a complete expired Round locally.
  - [ ] 15.3 Ensure Operator Router failures do not affect settlement.
  - [ ] 15.4 Execute concurrent active Rounds using different Payment Tokens and verify complete accounting isolation.
  - [ ] 15.5 Ensure all tests pass.
    - _Requirements: 1-24_

- [ ] 16. Build comprehensive security and correctness tests
  - [ ] 16.1 Add `test/LotteryConfig.t.sol`
    - Details: Valid/invalid BPS, zero semantics, Payment Token validation, immutable configuration creation, enable/disable behavior, global limits, versioning, and historical snapshots.
    - _Requirements: 1-3_
  - [ ] 16.2 Add `test/LotteryPurchases.t.sol` and `test/TicketRanges.t.sol`
    - Details: Exact ERC-20 transfers, insufficient allowance/balance, receiver-fee and sender-fee rejection, direct-donation resistance, overselling, purchase limits, ranges, binary search, boundaries, Sellout, and concurrent different-token Rounds.
    - _Requirements: 4-7, 19_
  - [ ] 16.3 Add `test/LotterySettlement.t.sol`
    - Details: Cached/uncached beacons, wrong/stale rounds, deterministic winner, split permutations, rounding, zero/100% shares, tip caps.
    - _Requirements: 7-11, 16, 18-20_
  - [ ] 16.4 Add `test/LotteryClaims.t.sol` and `test/LotteryExpiration.t.sol`
    - Details: Include reverting, paused, blocked, fee-mutated, and inexact token transfers; invalid receivers; preserved liabilities; and double-claim attempts.
    - _Requirements: 12, 15, 18-20_
  - [ ] 16.5 Add `test/LotteryRevenue.t.sol`
    - Details: Direct same-token Router contribution, exact allowance behavior, incomplete Router bootstrap, unregistered/disabled asset, zero effective weight, Router liability/index capacity rejection, Treasury transfers, per-token surplus, cross-token isolation, version preservation, and atomicity.
    - _Requirements: 13, 14, 19, 20, 22_
  - [ ] 16.6 Add `test/LotteryGovernance.t.sol` and `test/LotteryDiamond.t.sol`
    - Details: Timelock-only upgrades/config, guardian limitations, pause, facet changes, irreversible finalization.
    - _Requirements: 1-3, 17, 18, 24_

- [ ] 17. Add fuzzing and stateful invariants
  - [ ] 17.1 Fuzz Round revenue conservation
    - Details: `winner + operator + treasury + finalizer == gross` for all valid economic configurations.
    - _Requirements: 10, 11, 19_
  - [ ] 17.2 Fuzz arbitrary ticket purchase sequences
    - Details: Tickets never exceed supply; every sold ticket resolves to one purchaser.
    - _Requirements: 5, 6, 19_
  - [ ] 17.3 Add `test/LotteryInvariant.t.sol`
    - Details: Exercise opening, purchases, expiry, settlement, claims, refunds, config/integration updates, Operator/Treasury flushes, pause/unpause.
    - _Requirements: 1-24_
  - [ ] 17.4 Assert per-token solvency and cross-token isolation invariants.
    - _Requirements: 14, 19, 20_
  - [ ] 17.5 Assert terminal-state monotonicity.
    - _Requirements: 15, 16, 19_
  - [ ] 17.6 Assert snapshot/integration-version immutability.
    - _Requirements: 2, 3, 13, 22_

- [ ] 18. Add formal verification targets
  - [ ] 18.1 Prove Lottery commitment to immutable Registry randomness.
    - Details: Prove a sold-out Round commits exactly once to the configured strictly-future drand Round and that neither upgrades nor ordinary lifecycle calls can change its target or substitute another randomness source.
    - _Requirements: 7-9, 16, 24.10, 25_
  - [ ] 18.2 Add Halmos proof for `cutsDisabled` irreversibility.
    - _Requirements: 24.5-24.8_
  - [ ] 18.3 Add bounded revenue-conservation proof harness.
    - _Requirements: 10, 11, 19_
  - [ ] 18.4 Add bounded per-token solvency and cross-token isolation proof harness.
    - _Requirements: 14, 19, 20_
  - [ ] 18.5 Add claim non-repeatability proof.
    - _Requirements: 12, 15, 19, 20_
  - [ ] 18.6 Add Operator flush atomicity proof or invariant.
    - _Requirements: 13, 19, 20_
  - [ ] 18.7 Document formal-model bounds explicitly.
    - _Requirements: 19, 20, 24, 25_

- [ ] 19. Checkpoint: security release gate
  - [ ] 19.1 Run formatting, lint, build, unit tests, fuzzing, and stateful invariants.
  - [ ] 19.2 Run the required Registry proof suite and Lottery formal harnesses; archive non-vacuous results and fail the gate on any required timeout or unknown.
  - [ ] 19.3 Review all external-call paths for CEI and liability preservation.
  - [ ] 19.4 Review every governance function against the post-finalization trust model.
  - [ ] 19.5 Ensure all security gates pass.
    - _Requirements: 1-25_

- [ ] 20. Deploy and validate `EqualFiDrandRegistry` on Robinhood Testnet
  - [ ] 20.1 Add chain-guarded testnet deployment script.
  - [ ] 20.2 Deploy registry and record address, code hash, compiler version, dependency commits, and transaction.
  - [ ] 20.3 Verify a real live future Quicknet Round onchain.
  - [ ] 20.4 Where practical, demonstrate equivalent compressed and uncompressed representations against real Quicknet data.
  - [ ] 20.5 Record the deployed runtime bytecode hash and reconcile Robinhood EIP-2537 results with the proof package's concrete-assumption vectors.
    - _Requirements: 8, 23.1-23.4, 25.9-25.12_

- [ ] 21. Deploy Lottery Diamond to Robinhood Testnet
  - [ ] 21.1 Add `LotteryInit`
    - New file: `src/initializers/LotteryInit.sol`
    - Details: Initialize authority, guardian, Treasury, global active-Round limit, initial immutable enabled Round configurations, integration version, and reentrancy state.
    - _Requirements: 1-3, 17, 22, 24_
  - [ ] 21.2 Add deterministic deployment scripts
    - New file: `script/DeployLottery.s.sol`
    - Details: Deploy facets, Diamond, initializer, and initial cuts.
    - _Requirements: 23.1-23.2, 24_
  - [ ] 21.3 Configure testnet integrations.
    - _Requirements: 13, 22, 23_
  - [ ] 21.4 Save deployment manifest including chain ID, Diamond/facets, code hashes, selectors, registry, Operator Router, authority, guardian, global concurrency, and every initial Payment Token/configuration version. WETH is recorded only when selected as one of those Payment Tokens.
    - _Requirements: 21, 23, 24_

- [ ] 22. Execute full Robinhood Testnet lifecycle
  - [ ] 22.1 Run a real successful Lottery Round from open through winner/finalizer claims.
    - _Requirements: 23.3-23.5_
  - [ ] 22.2 Test unsold-Round expiration and full refunds.
    - _Requirements: 23.6_
  - [ ] 22.3 Test unavailable Operator routing while settlement still succeeds.
    - _Requirements: 13.7-13.8, 23.7_
  - [ ] 22.4 Test successful direct Operator routing into `OperatorFeeRouter` in each configured test Payment Token.
    - _Requirements: 13, 23.8_
  - [ ] 22.5 Run concurrent active Rounds using at least two different configured Payment Tokens, including WETH and one of STATICS or USDG, and verify isolated settlement, claims, refunds, Treasury balances, and Operator revenue.
    - _Requirements: 4.6, 5, 13-15, 19, 23.9_
  - [ ] 22.6 Test Diamond upgrade flow and Round storage preservation.
    - _Requirements: 24.1-24.4, 24.10-24.12_
  - [ ] 22.7 Test irreversible finalization; subsequent cuts fail while ordinary Lottery configuration and operation remain available.
    - _Requirements: 24.5-24.9_

- [ ] 23. Documentation and audit preparation
  - [ ] 23.1 Add `docs/architecture.md` for Diamond trust boundary, lifecycle, randomness, accounting, Operator integration, and progressive immutability.
    - _Requirements: 21, 22, 24_
  - [ ] 23.2 Add `docs/randomness.md` for Quicknet trust model, target selection, no fallback, 48/96 support, normalization, and domain separation.
    - Details: Include the exact formal claim, EIP-2537 model, trusted computing base, proof exclusions, pinned artifacts, and distinction between formal, differential, fork, and live evidence.
    - _Requirements: 7-9, 16, 22, 25_
  - [ ] 23.3 Add `docs/accounting.md` for per-token conservation and isolation, liabilities, Treasury, refunds, direct same-token Operator routing, and surplus.
    - _Requirements: 10-15, 19-20_
  - [ ] 23.4 Add `docs/governance.md` distinguishing Diamond upgrades, parameter governance, guardian powers, code finalization, and optional governance renunciation.
    - _Requirements: 1-3, 17-18, 24_
  - [ ] 23.5 Produce audit scope listing contracts, dependencies, invariants, privileged roles, limitations, tests, testnet addresses, and formal-verification bounds.
    - _Requirements: 1-25_

- [ ] 24. Final checkpoint
  - [ ] 24.1 Run all registry and Lottery tests from a clean checkout.
  - [ ] 24.2 Run the Robinhood Testnet end-to-end release gate.
  - [ ] 24.3 Verify deployment manifests and external integration addresses.
  - [ ] 24.4 Verify no unresolved path can alter a live Round's snapshotted terms.
  - [ ] 24.5 Verify no fallback randomness exists anywhere in production code.
  - [ ] 24.6 Verify settlement contains no dependency on Winner, Treasury, Payment Token, or Operator Router transfer success.
  - [ ] 24.7 Verify all ERC-20 ingress and egress paths require exact deltas and cannot cross-subsidize another token.
  - [ ] 24.8 Verify Diamond finalization is irreversible.
  - [ ] 24.9 Verify the Registry proof package matches deployed runtime bytecode, discloses its trusted computing base, and has no unresolved required rule.
  - [ ] 24.10 Ensure all tests and proof gates pass and implementation is ready for audit/release.
    - _Requirements: 1-25_
