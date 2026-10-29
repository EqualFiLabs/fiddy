# Implementation Plan: Deadline Draws

This change supersedes the original sellout-only/refund implementation plan. The normative requirements and design describe the new behavior; historical deployment/proof artifacts describe only their pinned revisions.

## Delivery sequence

1. Synchronize requirements, design, operational docs, and repository instructions for sellout-or-deadline draws with configurable positive duration (including week-long Rounds).
2. Schedule the deadline beacon at opening; permit only deterministic atomic early-Sellout rescheduling. Extend permissionless settlement to deadline Rounds; select only sold tickets and allocate actual receipts. Retire expiry/refund selectors without changing storage positions or enum ordinals.
3. Update selectors, local integration suites, adversarial claim tests, stateful handlers, and fresh-testnet rehearsal scripts/validators. Preserve historical manifests and expose no default historical Diamond target in the new rehearsal script.
4. Add formal deadline scheduling, purchase-cutoff, premature-settlement, sold-ticket selection, and revenue-conservation properties. Run all required Lottery properties on TFDEVM001 with pinned candidate/toolchain and durable results. Keep the Registry proof boundary separate.
5. Commit the candidate, prepare the audit scope, complete independent agent security review, remediate findings, and rerun affected gates. Push only the feature branch, open a PR, and require terminal green Foundry/Slither CI on the final head.

## Acceptance

- Both early sellout and partial-sale deadline draws complete through the Diamond with actual ERC-20 custody, winner/finalizer claims, Treasury delivery, and retryable Operator funding.
- One-ticket Rounds draw normally; purchases at/after the deadline fail; late callers cannot choose a beacon; pause cannot censor settlement or claims.
- Concurrent tokens remain isolated, refunds are unreachable, and next opening is permitted only after prior settlement.
- New deployment tooling covers both paths; the new live testnet rehearsal is pending separate authorization and is not claimed as executed.
- Historical finalized deployments are not upgraded. No mainnet deployment or merge is part of this delivery.

## Deployment defaults

- Set initial deployment economics to 50% Winner, 30% Treasury before the Finalizer Tip, and 20% Operators using `winnerBps = 5000` and `operatorProtocolBps = 4000`.
- Set the initial global concurrency limit to 100 active Rounds, retaining governance control and one active Round per Configuration Version.
- Exercise the deployment configuration through actual ERC-20 purchases, settlement and payouts; verify that changing configuration after code finalization preserves existing Round economics.
- Preserve historical deployment manifests and their recorded economics.
