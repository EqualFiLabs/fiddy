# Lottery formal-verification evidence

## Candidate

- Source commit: `0e92aaf7095d212fa9b97f2bed747d5a287306c9`
- Solidity: 0.8.30
- Optimizer: enabled, 200 runs
- EVM target: Osaka
- Foundry: 1.7.1
- Halmos: 0.3.3
- Z3: 4.12.6

The proof ran from the committed checkout in a dedicated verification environment through
`formal/scripts/run-halmos.sh`. The machine-readable public summary is
`formal/evidence/lottery-halmos-0e92aaf.json`.

## Result

All 12 release-required rules completed successfully. The Halmos process and every individual
rule returned exit code zero. The result contains zero counterexample models and zero bounded
loops, and the log contains no timeout, unknown, panic, counterexample, or loop-bound marker.

| Proof contract | Rule | Paths | Result |
|---|---|---:|---|
| `LotteryClaimsHalmosTest` | `check_refundClaimCannotRepeat` | 5 | Pass |
| `LotteryClaimsHalmosTest` | `check_winnerClaimCannotRepeat` | 5 | Pass |
| `LotteryCommitmentHalmosTest` | `check_selloutCommitmentIgnoresCatalogChanges` | 6 | Pass |
| `LotteryCommitmentHalmosTest` | `check_selloutCommitmentIsStrictlyFuture` | 6 | Pass |
| `LotteryCommitmentHalmosTest` | `check_selloutCommitmentMatchesRegistrySelection` | 6 | Pass |
| `LotteryCutsHalmosTest` | `check_cutFinalizationCannotBeReversed` | 1 | Pass |
| `LotteryRevenueHalmosTest` | `check_operatorFlushIsAtomicAndTokenIsolated` | 51 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementConservesRevenue` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementDoesNotMutateIsolatedToken` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementPreservesPaymentTokenSolvency` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementRecordsOperatorAndFinalizerLiabilities` | 6 | Pass |
| `LotterySettlementHalmosTest` | `check_settlementRecordsTerminalStatus` | 6 | Pass |

Raw durable artifacts are bound to this report by digest:

| Artifact | SHA-256 |
|---|---|
| Halmos JSON | `85a59e90db4ce8527f54e4e3c6f0e99a5ba8b06c09607a044f6c1a8c0ffb9cc1` |
| Halmos log | `2da21bf0eb3e3ce41edb91b10e5592bc1818f21d9e5543ff738e39a37baf52b6` |

## Runtime bytecode binding

The following Keccak-256 hashes bind the production runtime bytecode compiled in the proof
environment at the candidate commit and settings above. The full hash includes Solidity's
terminal 51-byte CBOR build-metadata trailer. The logic hash excludes that trailer so an
independent build can compare executable logic even when its build system emits different
metadata.

| Contract | Runtime bytes | Full runtime hash | Metadata-free logic hash |
|---|---:|---|---|
| `StaticsLotteryDiamond` | 260 | `0x7fa423d9c71448d4c24c8cc4591f99a78061ae7c4fcdcccd4f9797b5cd364f29` | `0xd64dfeba7961d9e04de9981cc5a8a5fe48d88d188f2af808a496cfc8f2099535` |
| `DiamondCutFacet` | 3,976 | `0xd2ac2bb785bdc874924b8fe925a7e3a64209c2f0bde645ca4cbe291619034bd2` | `0x76d3863546d900ea27a4655108ce173849b1f6cfc186376b33f6c0e8e775fe0f` |
| `GovernanceFacet` | 4,488 | `0x3fbf80fe77b75166233b75dff9ba36bab6e1f478ffdfba32be5e316539fdd458` | `0x019d7be997a8fcae90681a65594d99e80b8eebac03bfe77fee0abf4dbee6f577` |
| `LotteryFacet` | 6,246 | `0xe0a083c3c00eeef84b8962fe045208624e989c28f583ba417aa423333e5541cb` | `0xf23f7c386a2333f3ad995ba63bc3b1736577552244ec9a8d44c7122fad2436a0` |
| `SettlementFacet` | 3,445 | `0x09a429508c0a8feb27cd8fa590be982d47a49123db049bb02f36fa78c1bdd956` | `0x84188624502243051ccecd33a44f5f1bc0d2f15294397fcf60c7f44622609f8b` |
| `ClaimsFacet` | 2,597 | `0xdb4d2a248bfd010b2a0927dd14c602cbe155b17589cc3bd5e4d6a6cf9f6d16bb` | `0x284df4d474a090d3184332aa6c2cbe05996dc5fc93463735bf92b5631aed2612` |
| `RevenueFacet` | 4,557 | `0xbae29cd29cc06ea6689bb6374f86193799e9926093160d2feafef8690d06ed5e` | `0x41af471f96908b8a040ea78195586f3630123d0eb6b8bef2f967a59e7226d01d` |
| `LotteryViewFacet` | 4,720 | `0x39478b27f7a7b5bdbd05217437587022155991b021bf411a0f866f66ab2daab5` | `0x5c6ebd4e27147dbc0957ec4334bf594e06b492f62b0b8ee700dd39b1db069bc8` |

Proof inputs are bound by SHA-256:

| Input | SHA-256 |
|---|---|
| `foundry.toml` | `d9d07e845d3e994a54b8c26dcebe1bce234bbb45913970df2573766b2ada2067` |
| `formal/README.md` | `400d2faa4003f148d1aa78d79213f23957bd4988eb345750b66b3e8712f12002` |
| `formal/scripts/run-halmos.sh` | `6df24cd4c9f1928fe1611daa3c4f8de27e609778b6996b55da0e1860a1663c46` |
| `test/formal/LotteryFormalHarnesses.sol` | `2cc88d6e9aa73b8b795500518bdc9f944760d74da84167d7db7e70882516f96b` |
| `test/formal/LotteryProperties.halmos.t.sol` | `269516e283a37330469e38ade3e6ee7ff87fdbc8ca803f888555405fda65c749` |

Dependency revisions:

- `forge-std`: `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`
- `openzeppelin-contracts`: `5fd1781b1454fd1ef8e722282f86f9293cacf256`

## Registry proof dependency

The Lottery consumes the separately release-gated `EqualFiDrandRegistry` rather than modeling its
cryptography as a Lottery property. The accepted Registry stack head is
`cdc760a9bf5bbbc1647d13e43b22858677dacad6`; its formally verified production source is
`f8db2a1752d22672d4de1708545e286a32c41497`, with production runtime hash
`0xde08fa453cee52a32750e6ff4f736d28b2a4378494cc699e62d27eb44164c1fc`.

That unchanged Registry candidate retains its prior release evidence: 34 of 34 Halmos rules pass
without counterexamples or bounded loops; the three cache-state, five constrained-acceptance, and
two production-runtime Certora rules pass with sanity witnesses and no timeout; all required
mutation checks are detected. Its machine-readable artifacts and proof report remain versioned in
the Registry repository. This report reuses that exact dependency evidence rather than presenting
the Lottery harness as a cryptographic proof.

## Bounds and exclusions

The exact symbolic domains, synthetic preconditions, dependency summaries, and exclusions are
defined in `formal/README.md`. In particular, the commitment rules prove ordering strictly after
the supplied L2 timestamp boundary, single assignment, and Registry-selection consistency. They
do not prove wall-clock freshness, fair transaction ordering, or resistance to a malicious
Robinhood sequencer. Honest ordering and timestamp progression by the Robinhood-operated sequencer
are an accepted target-chain trust assumption.

This evidence is separate from Registry cryptographic proofs, Foundry tests, static analysis, and
Robinhood Testnet execution. It makes no claim about drand liveness, arbitrary ERC-20 behavior,
compiler correctness, target-client correctness, or production deployment behavior.
