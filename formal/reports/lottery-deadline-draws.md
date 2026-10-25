# Deadline-draw formal verification

## Cleanup revalidation

Current executable candidate: `459d63832e3a807824940cc52c542f05b5aedced`. The following evidence commit changes documentation only. All **15 required rules pass again** on TFDEVM001 with zero counterexamples, bounded-loop warnings, or failed rules and at least one successful path per rule. Proof inputs, dependency file hashes, compiler, tools, configuration, bounds, and assumptions match the original run below. Path counts and all current runtime hashes are recorded in the [cleanup evidence](../evidence/lottery-halmos-459d638.json).

The clean source and raw results are retained in `~/formal-workspaces/fiddy-deadline-draws-459d638/` on TFDEVM001 and locally in ignored `.tooling/formal-459d638/`. SettlementFacet now has 3460 runtime bytes, full Keccak-256 `0xbd4a101703dca284518fbb33c9a34e4642ea506853bfb4ac116dedf0876a4a6a`, and metadata-stripped logic hash `0xac89ca98bc620e80ba5c7f9203021059a36a25c9e5ff06d8a7b7e7d4c0af1570`. The production change removes redundant registry cache checks; unit tests separately cover posting, cached randomness, rejected proofs, reentrancy, and unavailable cache regardless of the posting return value. The formal deadline settlement model uses a cached Registry summary and does not prove Registry posting behavior.

The cutoff mutation was not rerun: its production guard and proof inputs are unchanged. That mutation result remains bound to the original candidate below. No live deployment or new real Registry/Router rehearsal is claimed.

## Original deadline-draw candidate

Source candidate: `46eac320393f9258370522e7c923220da7a6571e`. The following documentation-only evidence commit does not change executable source or proof inputs.

## Result

All **15 required rules pass** on TFDEVM001, including the four deadline properties. The process and every rule exit zero, with no counterexample models, bounded-loop warnings, timeout, unknown assertion result, or all-paths-reverted result. A separate deletion of the production purchase deadline guard produces counterexamples and fails the cutoff property. The mutated checkout is not release source.

| Contract | Rule | Paths | Result |
|---|---|---:|---|
| `LotteryClaimsHalmosTest` | `check_winnerClaimCannotRepeat(uint256)` | 11 | Pass |
| `LotteryCommitmentHalmosTest` | `check_selloutCommitmentIgnoresCatalogChanges(uint256)` | 10 | Pass |
| `LotteryCommitmentHalmosTest` | `check_selloutCommitmentIsStrictlyFuture(uint256)` | 10 | Pass |
| `LotteryCommitmentHalmosTest` | `check_selloutCommitmentMatchesRegistrySelection(uint256)` | 10 | Pass |
| `LotteryCutsHalmosTest` | `check_cutFinalizationCannotBeReversed()` | 1 | Pass |
| `LotteryDeadlineHalmosTest` | `check_deadlineCommitmentIsFutureAndFixed(uint256,uint256)` | 50 | Pass |
| `LotteryDeadlineHalmosTest` | `check_deadlineRejectsPrematureSettlement(uint256)` | 1 | Pass |
| `LotteryDeadlineHalmosTest` | `check_deadlineRejectsPurchasesAtOrAfterClose(uint256)` | 9 | Pass |
| `LotteryDeadlineHalmosTest` | `check_deadlineWinnerIsSoldAndRevenueConserved(uint256)` | 10 | Pass |
| `LotteryRevenueHalmosTest` | `check_operatorFlushIsAtomicAndTokenIsolated(uint256,uint256,bool)` | 73 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementConservesRevenue(uint64,uint16,uint16,uint64)` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementDoesNotMutateIsolatedToken(uint64,uint16,uint16,uint64)` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementPreservesPaymentTokenSolvency(uint64,uint16,uint16,uint64)` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementRecordsOperatorAndFinalizerLiabilities(uint64,uint16,uint16,uint64)` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementRecordsTerminalStatus(uint64,uint16,uint16,uint64)` | 6 | Pass |

## Reproduction and toolchain

The exact clean committed checkout and dependencies are retained in `~/formal-workspaces/fiddy-deadline-draws-46eac32/` on the dedicated verification box. Raw logs, JSON, build output, environment metadata, dependency checks, and mutation artifacts are in its `results/` directory, with a local ignored copy under `.tooling/formal-46eac32/`. They are bound by hashes in the [machine-readable summary](../evidence/lottery-halmos-46eac32.json).

Run `formal/scripts/run-halmos.sh RESULT_DIR` on the approved verification box. This run uses Solidity 0.8.30+commit.73712a01, optimizer 200, Osaka, no via-IR; Foundry 1.7.1 (`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`), Halmos 0.3.3, external assertion solver Z3 4.16.0, and internal branching library z3py 4.12.6. Solver resolution confirms the external binary is `/home/hooftly/.local/bin/z3`. The compiler binary SHA-256 is recorded in the summary.

Configuration: Z3, generic storage, all panic codes checked, loop bound 2, unlimited assertion-solving time, and a 45-minute outer process limit. Branch feasibility pruning has a 1 ms solver budget; undecided branches are explored, not dropped. Zero bounded loops are required. An interrupted, timed-out, unknown, or vacuous run is not a pass.

The initial harness revision had mismatched precomputed/runtime mapping keys and an alternative-revert cutoff check. Remediation uses runtime keys, a funded successful predeadline purchase control, and the exact expiry error. Concrete Foundry controls pass 3/3. An earlier unlimited-branch-pruning run was interrupted and superseded; it is not counted as successful evidence.

## Runtime binding

Full Keccak-256 hashes include Solidity metadata. Logic hashes remove the CBOR trailer plus its two-byte length suffix (53 bytes in these builds). These are compiled artifacts, not deployed runtime attestations.

| Contract | Runtime bytes | Full runtime hash | Logic hash |
|---|---:|---|---|
| `StaticsLotteryDiamond` | 260 | `0x5f2151c4dba1b0be499c0b275e5c1bacb9f07229b69d3462c18516272b681302` | `0xd64dfeba7961d9e04de9981cc5a8a5fe48d88d188f2af808a496cfc8f2099535` |
| `DiamondCutFacet` | 3976 | `0x7c68c77a32f1cc2af785a594eeb6e71a4c87445c4a82659b7f80eb36b269b33e` | `0x76d3863546d900ea27a4655108ce173849b1f6cfc186376b33f6c0e8e775fe0f` |
| `DiamondLoupeFacet` | 1464 | `0x55fd04f8b8d5bd5140b6ec8668e14a0b6fee3b9c6b95f88b57bd8273e408f3f7` | `0x469863bdd4bff2dc5353b0b17a745f79b6e8a0ffd867f7078114a61e54f8712f` |
| `GovernanceFacet` | 4488 | `0x9bdf585dc18cb83976fcc4c930cf5dfcffa81d022aa332a7d4e3ca59645d01c3` | `0x019d7be997a8fcae90681a65594d99e80b8eebac03bfe77fee0abf4dbee6f577` |
| `LotteryFacet` | 5810 | `0x66c8d4d4f3cf8f7421eaae22df3fd8d6b497cbaa5cb06605dd7ffd09393fb4c9` | `0xc32b365df19fc2387c6f6dc2f6ff3569962184a86a788f29d9db32e242adc553` |
| `SettlementFacet` | 3628 | `0xfee71a78de926d94d0d05cb88f1b2fe3e0faa8b17fa2648ef0495b706f3ab75b` | `0x1085251927d2e3790c239b51cc035132133ef4fc1d130d5a3730378d6e27e174` |
| `ClaimsFacet` | 2055 | `0x0c49ae788fdcf08e83d286559ec6227858fcffa2079b8e5be1abac135c314783` | `0x50d8117500a3c8f05ef6e8cb3d30b7dbcb51b0d953c68184e61408d8c25fad13` |
| `RevenueFacet` | 4557 | `0x23bcc1ef0a42698a70722cb5a9173787a7cd93f8d67994f5d5789d809d891ef4` | `0x41af471f96908b8a040ea78195586f3630123d0eb6b8bef2f967a59e7226d01d` |
| `LotteryViewFacet` | 4575 | `0xb755983e8e8cac286472a20b3760f2e259389c44d8b30fcf69b59f8bf1c63170` | `0xce09cc07caa38f3fba805bba93687dbac648907fed7d4f928f85ed5d1a08a34f` |
| `LotteryInit` | 3684 | `0xeaf3ff6d5d6eafff97ca6a937903d881c76f6f1b35472211e60b6f8780aa4773` | `0x12120e8326e8691ffa78bf100b1efd9c89a866ee3c3db8c969ca0c378701ce57` |

## Bounds and assumptions

The [formal model](../README.md) defines each property. Deadline scheduling covers positive uint32 duration and uint32 delay at the model timestamp with a deterministic Registry summary. Deadline settlement covers every sold count from 1 through 4,294,967,294 inclusive, with cap one larger, unit receipts per sold ticket, one cumulative owner range, fixed valid BPS, and one canonical cached Registry seed. It executes production readiness, seed derivation, winner lookup, allocation, and accounting, but seeds the initial state directly. The cutoff proof establishes the guard after a real funded purchase; its earlier sold/receipt history is synthetic. These are bounded transition proofs, not proofs of every opening or purchase history.

The existing allocation/claim/Operator/finalization domains remain documented in the formal model. Dependency files are SHA-256 checked against the candidate checkout before the run. Gitlinks are unchanged: forge-std `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`, OpenZeppelin `5fd1781b1454fd1ef8e722282f86f9293cacf256`, Registry `cdc760a9bf5bbbc1647d13e43b22858677dacad6`, Router `f98a17780cb250ce28f446ab54eb078512fb2e0b`.

The trusted base includes Solidity compilation, Halmos EVM semantics, Z3, Keccak, exact-transfer token summaries, dependency summaries, and seeded preconditions. Registry cryptography, Router distribution, arbitrary ERC-20 behavior, external liveness, governance honesty, compiler/client correctness, and malicious sequencer ordering or timestamps are outside this proof. Honest Robinhood ordering and timestamp progression remain an explicit assumption.

This is fresh-deployment source evidence. It does not attest to a deployed deadline-draw Diamond. Full CI, independent agent review, local tests, historical Registry assurance, and any future real Registry/Router testnet rehearsal are separate evidence layers. Historical refund proofs remain pinned to their original release.

## Dependency pin recovery

The Router gitlink now points to reachable commit `a6afe541c6261f1febb2eaf0f4d68ef5aa16548e`
in place of unavailable commit `f98a17780cb250ce28f446ab54eb078512fb2e0b`. Comparing the two
Router snapshots shows only the removal of two README lines; contracts, tests, compiler
configuration, dependency pins, and all other files are identical. The original proof commits,
dependency hashes, bounds, and results above remain unchanged. This checkout repair does not
claim a new formal run or alter the historical deployment records.
