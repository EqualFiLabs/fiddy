# Statics Lottery Audit Scope

This document defines the release-review boundary for Statics Lottery. Reviewers should audit the
committed repository candidate they receive, using the specifications and deployment evidence
listed here. The Robinhood Testnet deployment is a disposable release rehearsal, not a production
governance recommendation.

## Candidate and source of truth

The normative product and architecture sources are:

- [`specs/requirements.md`](../specs/requirements.md);
- [`specs/design.md`](../specs/design.md); and
- [`specs/tasks.md`](../specs/tasks.md).

The public security model is further explained in:

- [`architecture.md`](architecture.md);
- [`randomness.md`](randomness.md);
- [`accounting.md`](accounting.md);
- [`governance.md`](governance.md);
- [`payment-token-policy.md`](payment-token-policy.md); and
- [`operator-router-integration.md`](operator-router-integration.md).

The deployed Lottery source snapshot is commit
`bdd725d809d16812ab910e5add937d76223814c6` of `EqualFiLabs/fiddy`. An audit conclusion must bind
itself to an exact later release-candidate commit if documentation, tests, or remediation changes
after that snapshot.

## In-scope production contracts

All production behavior is reached through one `StaticsLotteryDiamond` address. Interfaces define
the external surface but contain no implementation. The production implementation scope is:

| Source | Review focus |
|---|---|
| `src/StaticsLotteryDiamond.sol` | Constructor authority, native-ETH rejection, fallback dispatch |
| `src/facets/DiamondCutFacet.sol` | Authority-gated EIP-2535 upgrades and initializer execution |
| `src/facets/DiamondLoupeFacet.sol` | Selector and facet introspection |
| `src/facets/GovernanceFacet.sol` | Configuration and integration versions, roles, pause, concurrency, finalization |
| `src/facets/LotteryFacet.sol` | Round opening, ticket purchases, expiration, sellout beacon commitment |
| `src/facets/SettlementFacet.sol` | Registry interaction, application seed, winner resolution, allocation |
| `src/facets/ClaimsFacet.sol` | Winner, refund, and finalizer pull claims |
| `src/facets/RevenueFacet.sol` | Operator and Treasury delivery, token and native surplus |
| `src/facets/LotteryViewFacet.sol` | Round, configuration, ownership, and accounting reads |
| `src/initializers/LotteryInit.sol` | One-time initial selector-state configuration |
| `src/libraries/LibDiamond.sol` | Diamond storage, selector mutation, authority, irreversible cut latch |
| `src/libraries/LibExactToken.sol` | Exact sender-spend and receiver-receipt enforcement |
| `src/libraries/LibLotteryConfig.sol` | Configuration and integration validation and Round snapshots |
| `src/libraries/LibLotteryStorage.sol` | Namespaced layouts and cross-facet state |
| `src/libraries/LibOperatorFeeRouter.sol` | Router readiness and exact same-token contribution |
| `src/libraries/LibReentrancy.sol` | Diamond-wide value-path reentrancy state |
| `src/libraries/LibTicketRanges.sol` | Cumulative ticket ranges and binary-search ownership |
| `src/shared/DiamondTypes.sol` | Diamond-cut shared types |
| `src/shared/Errors.sol` | Shared failure surface |
| `src/shared/Types.sol` | Lifecycle, configuration, Round, and accounting types |

Review all `src/interfaces/*.sol` for ABI consistency with the implementation and external
dependencies. Deployment and lifecycle scripts are in scope for release correctness, but a script
finding is not automatically a production-contract finding.

## External dependencies

| Dependency | Pinned revision or deployment | Boundary |
|---|---|---|
| `EqualFiDrandRegistry` | Stack `cdc760a9bf5bbbc1647d13e43b22858677dacad6`; verified source `f8db2a1752d22672d4de1708545e286a32c41497`; testnet `0x61388A94B429A04cAC0357485c12F68f706d7b57` | Immutable Quicknet verification and canonical randomness cache |
| `bls-solidity` | `11af179a8287d978659aae07adb66aa60f64b8a6` | BLS12-381/EIP-2537 primitives used by the Registry, not the Lottery |
| Statics Genesis replica | Manifest `31e870900615197277bcccef6bfdb06dba452930`; Genesis source `43018f109006aa2c2eef2808adc2aa74dfc9a6d4b`; reused testnet collection, activation registry, vault, WETH, and STATICS | External Operator identity/activation/custody inputs and configured Payment Token contracts; the Genesis launch itself was not replayed |
| `OperatorFeeRouter` | Source `f98a17780cb250ce28f446ab54eb078512fb2e0b`; deployment evidence `5454f935a2037453f5d2f819d64c864f16363df4`; testnet `0xE7Bb1D2766377984546611291732cED1833C0c36` | Operator ownership, weights, reward-index accounting, and claims |
| OpenZeppelin Contracts | `5fd1781b1454fd1ef8e722282f86f9293cacf256` | ERC-20 interfaces and safe-call behavior |
| Forge Standard Library | `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` | Test and script support; not deployed Lottery logic |

The Registry and Router internals are separate review domains. Their Lottery-facing interfaces,
configuration pinning, failure handling, and accounting effects are in scope here. Payment Tokens
are external contracts governed by the admission policy rather than arbitrary supported ERC-20s.

## Privileged roles

| Actor | Capability | Explicit limit |
|---|---|---|
| Authority | Diamond cuts before finalization; append configurations and integrations; enable future opening; set concurrency, Treasury, guardian, and pause; finalize code | Cannot edit a stored version or Round through the intended facets; cannot cut after finalization |
| Guardian | Pause new opening and purchases | Cannot unpause, change parameters, upgrade, settle, or move funds |
| Treasury recipient | Receives permissionlessly flushed Treasury revenue and surplus | Has no privileged call authority solely by being recipient |
| Public opener/buyer | Opens an enabled configuration by buying tickets; buys within configured limits | Cannot override token, economics, integration, deadline, or concurrency |
| Public maintainer/finalizer | Expires eligible Rounds, submits or reuses the committed beacon, settles, and retries revenue delivery | Cannot choose a replacement beacon, winner, Router, Treasury recipient, or liability amount |
| Winner/refund claimant/finalizer | Pulls only the caller's recorded entitlement to an allowed receiver | Cannot claim another account's credit or claim twice |

Before finalization, the authority can install arbitrary delegatecall code and is trusted to
preserve live Rounds, liabilities, selectors, and storage. The Lottery contains no timelock or
authority-transfer mechanism; production must provide the intended delay and access policy in the
external authority.

## Security invariants

Reviewers should treat at least the following as release-critical:

1. A Round snapshots immutable configuration and integration versions; later catalog changes do
   not alter its token, terms, Registry, Router, deadline, or committed beacon.
2. The global concurrency limit applies across configurations while each configuration has at most
   one nonterminal Round.
3. Native ETH is never ticket principal. WETH has no privileged path and behaves as an ordinary
   configured ERC-20.
4. Every ERC-20 ingress and egress verifies both sender spend and recipient receipt. Inexact,
   fee-on-transfer, sender-fee, rebasing, or drifting behavior reverts atomically.
5. Every liability, revenue bucket, balance check, and surplus calculation is scoped to the
   Round's canonical Payment Token. No token or Round may subsidize another.
6. Successful allocation conserves receipts exactly: winner, Operator, Treasury, and finalizer
   amounts sum to the Round's gross receipts.
7. An expired unsold Round converts all receipts to refunds and earns no revenue share or tip.
8. A sold-out Round cannot expire or refund and is permanently bound to one strictly future drand
   Quicknet Round.
9. There is no fallback entropy, administrator selection, alternate Registry, later-beacon
   substitution, or local randomness path.
10. Settlement is accounting-only. Token, winner, Treasury, Router, or claimant behavior cannot
    prevent the Round from entering its terminal settled state.
11. Claims and revenue delivery are pull-based, individually retryable, non-reentrant, and clear
    liabilities only on exact successful transfer.
12. Operator revenue remains bucketed by Integration Version and Payment Token and is forwarded in
    that same token to that version's configured Router.
13. Pausing blocks new exposure only; it cannot block settlement, expiration, claims, retries,
    Treasury delivery, or surplus reduction.
14. Token surplus includes only balance above all recorded liabilities and available Treasury
    revenue for an admitted canonical token address.
15. Namespaced storage and selector mappings remain collision-free across facets and upgrades.
16. `finalizeProtocol` makes Diamond cuts irreversibly unavailable without silently removing
    ordinary configuration governance.

## Trust assumptions and known limitations

- **Robinhood Chain:** canonical ordering, valid state execution, data availability, eventual
  inclusion, and permitted L2 timestamp progression are accepted chain-level assumptions. A rogue
  sequencer threatens the validity and usability of the whole chain; Statics Lottery does not
  claim an application-local remedy for that failure.
- **Sequencer freshness:** a strictly future scheduled beacon prevents honest ordering from using
  an already cached result. It does not prove wall-clock freshness if a malicious sequencer keeps
  L2 time stale or withholds inclusion until public drand output is known.
- **No randomness fallback:** if the committed beacon or Registry is unavailable, a sold-out Round
  waits. This deliberate liveness tradeoff removes a selective recovery path.
- **drand:** Quicknet threshold integrity and availability, the compiled network identity, public
  key, DST, genesis, period, and standard cryptographic assumptions are trusted as documented in
  [`randomness.md`](randomness.md).
- **Payment Tokens:** runtime delta checks reject inexact transfers when exercised but cannot prove
  future token behavior. Upgradeability, freezes, blocklists, pausing, rebases, hooks, and multiple
  addresses controlling one ledger are governance and monitoring risks.
- **Canonical-token aliases:** the Diamond cannot detect two ERC-20 addresses backed by the same
  ledger. Deployment governance must admit at most one address for each underlying ledger.
- **Operator Router:** the Lottery checks readiness and exact transfer. Operator identities,
  synchronized weights, forfeiture, internal allocation, and downstream claims belong to the
  Router.
- **Governance:** before code finalization, arbitrary delegatecall authority can violate all
  intended invariants. A timelock supplies review time, not code safety. Parameter governance
  remains after code finalization.
- **Liveness:** hostile or unavailable tokens, recipients, Routers, drand relayers, governance, or
  chain infrastructure may delay an individual pull action. They must not corrupt accounting or
  block unrelated exits.
- **Testnet evidence:** Robinhood Testnet confirms concrete behavior for the recorded deployment;
  it does not establish production configuration, mainnet governance, or malicious-sequencer
  resistance.

## Test and analysis surface

The repository includes focused unit, integration, fuzz, stateful invariant, formal-property, and
testnet lifecycle coverage:

| Area | Principal evidence |
|---|---|
| Diamond and initialization | `LotteryDiamond.t.sol`, `LotteryInit.t.sol`, `LotteryStorage.t.sol` |
| Configuration and governance | `LotteryConfig.t.sol`, `LotteryGovernance.t.sol` |
| Purchases and token behavior | `LotteryPurchases.t.sol`, `ExactToken.t.sol`, `ReentrancyGuard.t.sol` |
| Ticket ranges and views | `TicketRanges.t.sol`, `LotteryViews.t.sol` |
| Settlement and randomness use | `LotterySettlement.t.sol`, `LotteryEndToEnd.t.sol` |
| Claims, expiration, and refunds | `LotteryClaims.t.sol`, `LotteryExpiration.t.sol` |
| Operator, Treasury, and surplus | `LotteryRevenue.t.sol`, `LotteryEndToEnd.t.sol` |
| Stateful and fuzz properties | `LotteryInvariant.t.sol` and fuzz targets across focused suites |
| Bounded symbolic properties | `test/formal/LotteryProperties.halmos.t.sol` |
| Deployment/lifecycle helpers | `TestnetLifecycleHelpers.t.sol`, deployment validators and manifests |

CI runs formatting, compilation, linting, the complete Foundry test/fuzz/invariant suite, and
Slither with high-severity findings as failures. A green CI job proves only those configured checks;
it is separate from formal results, independent review, and testnet execution.

## Formal-verification boundary

### Lottery

The pinned Lottery proof candidate is
`0e92aaf7095d212fa9b97f2bed747d5a287306c9`, compiled with Solidity 0.8.30, optimizer 200, and
Osaka EVM settings. Halmos 0.3.3 with Z3 4.12.6 reports all 12 required rules passing, with no
counterexample, bounded loop, timeout, or unknown result.

The rules cover bounded production paths for sellout commitment, settlement conservation and
solvency, isolated-token non-mutation, winner/refund claim non-repeatability, Operator-flush
atomicity and token isolation, and irreversible cut finalization. Bounds include every `uint32`
randomness delay, every nonzero `uint64` settlement gross amount under valid BPS constraints,
every nonzero `uint96` modeled winner/refund amount, and Operator amounts from 1 through
`type(uint64).max` under documented synthetic preconditions.

The model does not prove Registry cryptography, the entire external lifecycle and Diamond dispatch,
arbitrary ERC-20 behavior, Router distribution, governance honesty, sequencer fairness or wall-clock
freshness, compiler correctness, target-client correctness, or network liveness. Full definitions
and per-rule results are in [`formal/README.md`](../formal/README.md) and
[`formal/reports/lottery-security-gate.md`](../formal/reports/lottery-security-gate.md).

Eight proof-bound production runtimes—`StaticsLotteryDiamond`, `DiamondCutFacet`,
`GovernanceFacet`, `LotteryFacet`, `SettlementFacet`, `ClaimsFacet`, `RevenueFacet`, and
`LotteryViewFacet`—rebuild to the proof report's metadata-free executable hashes at the deployed
source snapshot. Their deployment-manifest full runtime hashes differ from the older proof
candidate where Solidity build metadata changed. `DiamondLoupeFacet` and `LotteryInit` are not
among those eight runtime bindings; review and concrete test/deployment evidence cover them.

### Registry

The Registry proof binds source `f8db2a1752d22672d4de1708545e286a32c41497` and production
runtime hash `0xde08fa453cee52a32750e6ff4f736d28b2a4378494cc699e62d27eb44164c1fc`.
Its release evidence reports 34 passing Halmos rules, three passing cache-state Certora rules, five
passing constrained-acceptance rules, and two passing production-runtime rules, all with required
sanity witnesses and no timeout or unknown result. Mutation checks detect changes to strict-future
selection, cache immutability, and rejection gating.

The acceptance proofs constrain the EIP-2537 result to the exact submitted proof, Round,
normalized point, mapped message, compiled Quicknet DST and public key, and production pairing
transcript. They do not prove cryptographic hardness, compiler or client correctness, drand or
chain liveness, threshold-operator honesty, or the Lottery lifecycle. The Registry report and
machine-readable results live in the pinned `lib/drand-registry` dependency.

## Robinhood Testnet deployment

Chain ID: `46630`.

| Component | Address |
|---|---|
| Statics Lottery Diamond | `0x89373b3946818811d9421a48410a6164D4608680` |
| Lottery initializer | `0xCfa89d0265b5D8F2c4d8192C781Cf1D1b3f762ad` |
| Diamond cut facet | `0x84252778E142BE6Da4d2bB94402F455E92d01E4D` |
| Diamond loupe facet | `0x5b3F75f7095bF1ea4dE0745620322bCA4eC85b34` |
| Governance facet | `0x9c700997F2deaE5043bFec18b99A4c79e191F403` |
| Lottery facet | `0xAD8e9A81a972822D24662Ce824d103c61A1E2529` |
| Settlement facet | `0x2f1422ac19246f6631A884c1883db65C073a73FF` |
| Claims facet | `0xD405ABaCf1939097EC807D09524e66D8B09c040c` |
| Revenue facet | `0xc9D0946Fbf63057EB46934b8D883E917C2eEDe1e` |
| Lottery view facet | `0x0334Ca067C05deA3d3664Bf36748526E69F5e185` |
| EqualFi drand Registry | `0x61388A94B429A04cAC0357485c12F68f706d7b57` |
| Operator Fee Router | `0xE7Bb1D2766377984546611291732cED1833C0c36` |
| WETH Payment Token | `0x33e4191705c386532ba27cBF171Db86919200B94` |
| STATICS Payment Token | `0xb6Cc79B2d892798d8e469A1efBF0713Fc2e51f86` |

The deployment uses one disposable testnet EOA for authority, guardian, Treasury, buyer, winner,
and finalizer roles. That concentration is intentional for rehearsal and is unsafe as a production
role model.

The committed manifests are the authoritative address and transaction evidence:

- [`robinhood-testnet.md`](robinhood-testnet.md) maps reused and fresh components and states which
  Statics Genesis behaviors the Lottery rehearsal did not exercise;
- [`deployments/README.md`](../deployments/README.md) indexes the deployment evidence by claim;
- [`deployments/robinhood-testnet/lottery.json`](../deployments/robinhood-testnet/lottery.json)
  records source/toolchain pins, selectors, runtime hashes, roles, integrations, and initial
  configuration;
- [`deployments/robinhood-testnet/registry.json`](../deployments/robinhood-testnet/registry.json)
  records the Registry runtime match plus live compressed and uncompressed Quicknet verification;
  and
- [`deployments/robinhood-testnet/lifecycle.json`](../deployments/robinhood-testnet/lifecycle.json)
  records concurrent WETH/STATICS Rounds, live delayed Quicknet settlement, unsold refunds,
  successful and retryable Operator routing, winner/finalizer/Treasury delivery, upgrade storage
  preservation, irreversible finalization, and post-finalization operation.

## Reviewer priorities

Reviewers should prioritize cross-facet storage and authority interactions, lifecycle terminality,
token-ledger isolation, exact-transfer rollback, reentrancy across the Diamond, cumulative ticket
range boundaries, beacon freshness and domain separation, settlement independence, Router retry
atomicity, surplus solvency, initializer safety, selector manifests, and the transition from
upgradeable to permanently finalized code.
