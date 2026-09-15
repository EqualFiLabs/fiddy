# Randomness and Verification Boundary

Every sold-out Statics Lottery Round uses exactly one drand Quicknet beacon verified by the
external immutable `EqualFiDrandRegistry`. There is no Lottery-local BLS implementation and no
fallback randomness.

## Exact formal claim

The release-critical Registry claim is:

> Assuming the documented EIP-2537 and cryptographic model, every beacon newly stored by
> `EqualFiDrandRegistry` corresponds to a valid Quicknet signature for exactly that Round,
> produces one canonical Round-bound randomness value, and can never be replaced.

The Lottery formal package proves a different and narrower connection: once a Round sells out,
the production commitment routine stores the Registry-selected target strictly after the supplied
L2 timestamp boundary, later configuration-catalog changes do not alter it, and settlement/accounting
uses the resulting immutable Round state. It does not re-prove Registry cryptography.

## Sellout commitment

The last ticket purchase and commitment occur atomically. For the Round's snapshotted values:

```text
commitmentBoundary = block.timestamp + randomnessDelay
target = snapshottedRegistry.firstRoundAfter(commitmentBoundary)

require(target != 0)
require(snapshottedRegistry.roundTime(target) > commitmentBoundary)
require(!snapshottedRegistry.hasSig(target))

round.selloutAt = block.timestamp
round.drandRound = target
round.status = SoldOut
```

The target is written once. Governance cannot move a sold-out Round to a different Registry,
Quicknet Round, or configuration. If that exact beacon is delayed, the Round waits.

The cache-absence check proves only that the Registry has not already stored the signature on that
chain. Under the accepted sequencer-honesty assumption, the strict scheduled-time check means the
beacon is not yet available when sellout is ordered. Neither check proves that public drand data is
unknown offchain if a malicious sequencer withholds inclusion or keeps L2 time stale.

## Proof transports and normalization

The Registry accepts two encodings of the same Quicknet G1 signature:

- 48-byte compressed G1, the native drand transport; or
- 96-byte uncompressed G1, for callers that decompress before submission.

Both paths validate the point and normalize it to the same canonical 96-byte G1 representation
before randomness is derived. Raw relayer-supplied proof bytes are never used as Lottery entropy.
Equivalent valid encodings therefore produce the same value:

```text
registryRandomness = keccak256(canonicalG1Signature || bigEndianUint64(drandRound))
```

The first valid posting stores `registryRandomness` and `postedAt`. Later submissions for that
Round return `false` without verification or storage mutation.

## Settlement and domain separation

A finalizer may provide proof bytes only when the committed Round is not already cached. Settlement
then requires:

1. `hasSig(round.drandRound) == true`;
2. `postedAt(round.drandRound) > round.selloutAt`; and
3. randomness read from that exact Round.

The Lottery seed is:

```text
applicationSeed = keccak256(
    abi.encode(
        registry.randomnessOf(round.drandRound),
        block.chainid,
        address(StaticsLotteryDiamond),
        roundId
    )
)

winningTicket = uint256(applicationSeed) % ticketCount
```

Chain ID, Diamond address, and Round ID prevent the same Registry value from producing a shared
application seed across deployments or Rounds. The zero-based ticket is resolved against the
Round's immutable cumulative ticket ranges.

## No fallback

Production code has no `blockhash`, `prevrandao`, sequencer random value, administrator entropy,
VRF, CCIP, alternate Registry, later-beacon substitution, or local pseudo-random path. A sold-out
Round either settles from its committed Quicknet Round or remains pending.

This choice makes the failure mode visible and non-selective. Adding any alternate entropy source
would be an explicit protocol-design change, not an operational recovery action.

## EIP-2537 model

The production Registry uses:

| Primitive | Required behavior |
|---|---|
| EIP-198 modular exponentiation | Exact 64-byte result for field exponentiation |
| EIP-2537 map FP to G1 | Exact 128-byte mapped point |
| EIP-2537 G1 addition | Exact 128-byte sum |
| EIP-2537 pairing | Exact 32-byte result restricted to `0` or `1` |

Production rejects call failure, unexpected return length, invalid flags, infinity, non-canonical
field elements, invalid points, and pairing results outside `{0,1}`.

The formal acceptance summary is constrained to the submitted proof hash, exact Round, normalized
signature point, mapped message point, compiled Quicknet DST, compiled public key, and production
pairing transcript. `accepted` represents the pairing relation for that specific transcript; it is
not an unconstrained oracle and cannot authorize another proof or Round.

## Pinned formal artifacts

### Registry

| Item | Pinned value |
|---|---|
| Accepted Registry stack head | `cdc760a9bf5bbbc1647d13e43b22858677dacad6` |
| Formally verified source | `f8db2a1752d22672d4de1708545e286a32c41497` |
| Production runtime Keccak-256 | `0xde08fa453cee52a32750e6ff4f736d28b2a4378494cc699e62d27eb44164c1fc` |
| Solidity / optimizer / EVM | `0.8.30`, 200 runs, Osaka |
| `bls-solidity` | `11af179a8287d978659aae07adb66aa60f64b8a6` |
| Halmos / Certora CLI | `0.3.3` / `8.18.0` |

The Registry report records 34 passing Halmos rules, three passing cache-state Certora rules, five
passing constrained-acceptance rules, and two passing production-runtime Certora rules. Every
Certora rule has a sanity witness; no required rule timed out or returned unknown. Mutations to
strict-future selection, first-write immutability, and rejection gating were all detected.

The public proof inputs, per-rule outcomes, hashes, bounds, and exclusions are in the pinned
Registry dependency at `docs/formal-verification.md` and `formal/results/f8db2a17/summary.json`.

### Lottery

| Item | Pinned value |
|---|---|
| Proof candidate | `0e92aaf7095d212fa9b97f2bed747d5a287306c9` |
| Solidity / optimizer / EVM | `0.8.30`, 200 runs, Osaka |
| Halmos / Z3 | `0.3.3` / `4.12.6` |
| Result | 12 of 12 required rules pass; no counterexamples, bounded loops, timeout, or unknown |

The Lottery report and machine-readable evidence are
[`formal/reports/lottery-security-gate.md`](../formal/reports/lottery-security-gate.md) and
[`formal/evidence/lottery-halmos-0e92aaf.json`](../formal/evidence/lottery-halmos-0e92aaf.json).
They bind the proof inputs and compiled production runtime hashes.

## Evidence classes

These evidence types answer different questions and must not be collapsed into one claim:

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Registry solver proof | Round arithmetic, parsing/normalization transformations, constrained acceptance, cache immutability, and production non-posting selectors under the stated model | Cryptographic hardness, client correctness, network liveness, or Lottery behavior |
| Lottery solver proof | Bounded production commitment, allocation, solvency transition, token isolation, claim non-repeatability, Router atomicity, and cut finalization properties | Registry cryptography, arbitrary ERC-20s, live dispatch, or sequencer fairness |
| Official Quicknet differential vectors | Concrete serialization, mapping, point representation, pairing transcript, and equal 48/96 normalization for known beacons | Complete-domain proof or Robinhood client behavior |
| Fork execution | Target-client behavior at a pinned fork state, if run and recorded | This release claims no separate fork-evidence artifact |
| Robinhood Testnet execution | Deployed runtime hashes, concrete EIP-2537 calls, live future beacons, settlement, and lifecycle behavior on chain 46630 | Mainnet readiness, malicious-sequencer resistance, or broader formal coverage |

The deployed Registry runtime hash in
[`deployments/robinhood-testnet/registry.json`](../deployments/robinhood-testnet/registry.json)
matches the formally verified production runtime. Live compressed and uncompressed proof paths are
recorded there. The full Lottery lifecycle used compressed Quicknet Rounds `32209045` and
`32209112`; their official source, proof hashes, posting times, transaction receipts, and derived
outcomes are recorded in
[`deployments/robinhood-testnet/lifecycle.json`](../deployments/robinhood-testnet/lifecycle.json).

## Trusted computing base and exclusions

The verification claim trusts:

- the pinned Solidity compiler, optimizer, and formal-engine EVM semantics;
- Robinhood's EIP-198 and EIP-2537 implementations and ordinary EVM execution;
- SHA-256, Keccak-256, BLS12-381, RFC 9380, and standard cryptographic assumptions;
- authenticity of the compiled Quicknet chain identity, public key, DST, genesis timestamp, and
  period;
- drand threshold-operator honesty for beacon integrity and network liveness for availability; and
- honest Robinhood ordering and L2 timestamp progression for the sellout freshness interpretation.

The package does not prove cryptographic hardness, compiler correctness, formal-tool correctness,
target-client correctness, drand liveness, threshold-operator honesty, governance honesty,
transaction inclusion, wall-clock freshness, fair ordering, or resistance to a rogue sequencer.

If the Robinhood sequencer violates canonical ordering, inclusion, or permitted timestamp
progression, the failure is within the chain's trusted computing base. The Lottery still has no
application-level fallback or beacon-selection function, but it cannot independently restore the
chain guarantees on which all contracts depend.
