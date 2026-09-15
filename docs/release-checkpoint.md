# Statics Lottery Release Checkpoint

This checkpoint consolidates the release evidence for Statics Lottery. It is an audit-readiness
decision, not a production deployment approval. The Robinhood Testnet deployment remains a
disposable lifecycle rehearsal, and production governance, roles, integrations, and Payment Tokens
must be approved separately.

## Candidate lineage

- The deployed Lottery source snapshot is
  `bdd725d809d16812ab910e5add937d76223814c6`.
- The documentation and audit package reviewed independently is
  `562db0ee6888fcaabba2cc70f303792fdc09854e`.
- Commit `8849e0c` corrects the normative accounting-storage sketch to match the deployed
  append-only layout.
- Commit `15f1179` makes the lifecycle validator compatible with both bare and enveloped Cast JSON
  output.
- No production Solidity changed after the deployed source snapshot. The exact pull-request head
  and its terminal CI run are the authoritative final candidate evidence.

The source of truth and complete review boundary are listed in
[`audit-scope.md`](audit-scope.md).

## Independent review disposition

An independent checklist-based review of the committed candidate covered general Solidity risks,
precision and arithmetic, ERC-20 integration, Diamond upgradeability, randomness, inline assembly,
chain-specific behavior, and access control.

- No Critical, High, or Medium production finding was confirmed.
- One Low documentation finding was confirmed: the normative `AccountingStorage` sketch omitted
  the deployed `admittedPaymentToken` field. Commit `8849e0c` records the field in its deployed
  position and states the append-only rule for future upgrades.
- One release-evidence tooling gap was confirmed: current Cast JSON output can wrap decoded values,
  blocks, receipts, and transactions in a `data` member. Commit `15f1179` normalizes both supported
  shapes, and the complete lifecycle manifest subsequently validated on Robinhood Testnet chain
  `46630`.

These results do not remove the explicit trust assumptions and production-deployment gaps in
[`audit-scope.md`](audit-scope.md).

## Final invariant review

| Release property | Evidence and disposition |
|---|---|
| Immutable live-Round terms | Opening copies an enabled immutable configuration and current integration version into Round storage. Later governance actions affect only future opening. |
| Exclusive drand entropy | A sold-out Round commits once to one strictly future Quicknet Round. Production code contains no fallback beacon, block entropy, administrator entropy, or replacement path. |
| Honest-sequencer boundary | Canonical execution, ordering, inclusion, data availability, and permitted timestamp progression are Robinhood chain-level assumptions. A rogue sequencer is a chain-wide failure; the Lottery does not claim a local remedy or weaken its no-fallback rule. |
| Accounting-only settlement | Settlement records terminal state and token-denominated liabilities without transferring the Payment Token or depending on winner, Treasury, Router, or claimant cooperation. |
| Exact ERC-20 accounting | Ingress and egress validate both sender spend and recipient receipt. Liabilities, escrow, revenue, refunds, and surplus remain scoped to the Round's admitted Payment Token. |
| Concurrent token isolation | The lifecycle rehearsal ran concurrent WETH and STATICS Rounds and reconciled their independent settlement, claims, refund, Treasury, and Operator balances. |
| External deployment provenance | The Lottery manifest pins the reused Statics Genesis source/manifest, five dependency runtimes, and the Router-owned deployment evidence; the composition document separates reused, fresh, exercised, and untested components. |
| Retryable liability reduction | Winner, refund, finalizer, Treasury, and Operator paths are pull-based. Failed external interactions preserve their corresponding liabilities. |
| Irreversible code finalization | The cut-disabled latch is monotonic; the testnet lifecycle preserved storage across an upgrade, finalized the Diamond, rejected a later cut, and retained ordinary Lottery operation. |
| Registry deployment binding | The pinned Registry proof package binds its production runtime hash, Quicknet trust anchor, compiler configuration, proof assumptions, and per-rule results. The testnet manifest reconciles the deployed runtime and live compressed and uncompressed proofs. |

## Validation boundary

The release gate uses distinct forms of evidence:

- GitHub CI owns formatting, compilation, lint, the complete Foundry unit/fuzz/invariant suite,
  and Slither for the exact pull-request head. A previous green run is not evidence for a later
  commit; the final review must wait for terminal CI on the current head.
- Focused local checks cover changed documentation, shell syntax, both Cast JSON shapes, and the
  live lifecycle validator. They do not replace the CI suite.
- The Lottery formal report records 12 passing Halmos properties for proof candidate
  `0e92aaf7095d212fa9b97f2bed747d5a287306c9`, with Solidity 0.8.30, optimizer 200, Osaka EVM,
  Halmos 0.3.3, and Z3 4.12.6. The report has no counterexample, timeout, unknown result, or bounded
  loop among required rules.
- The Registry report records 34 passing Halmos rules and passing Certora groups of three cache,
  five constrained-acceptance, and two production-runtime rules, with required sanity witnesses
  and no unresolved required result.
- Metadata-free executable hashes reconcile the eight proof-bound Lottery runtimes with the
  deployed source snapshot. `DiamondLoupeFacet` and `LotteryInit` remain outside those eight formal
  runtime bindings and are covered by review, tests, and deployment evidence.
- Robinhood Testnet validators and the committed lifecycle manifest establish concrete behavior on
  chain `46630`. They do not establish production configuration, mainnet readiness, network
  liveness, cryptographic hardness, compiler/client correctness, or malicious-sequencer resistance.
- [`robinhood-testnet.md`](robinhood-testnet.md) and the
  [`deployment index`](../deployments/README.md) define the provenance boundary for the reused
  Statics Genesis contracts and the freshly deployed Registry, Router, and Lottery components.

The audit-ready decision requires terminal green CI on the final pull-request head, no unresolved
confirmed finding, and review of every production configuration against
[`governance.md`](governance.md), [`accounting.md`](accounting.md), and
[`randomness.md`](randomness.md). Production deployment additionally requires a separately approved
timelocked authority, separated operational roles, and freshly verified integration manifests.
