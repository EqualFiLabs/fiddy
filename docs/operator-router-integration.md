# Operator Fee Router Integration

Statics Lottery targets the public `EqualFiLabs/operator-fee-router` interface accepted in merged
PR #2. The reviewed merge commit is `f98a17780cb250ce28f446ab54eb078512fb2e0b`; its implementation
parent is `b8faeb839a2e9981b6d6f4fee46b07608481ec64`. That implementation verifies both contributor spend
and Router receipt during `addRewards`.

No deployment address is hard-coded in the Lottery. Each immutable Lottery integration version
pins one Router address, and each deployment manifest must identify that address, chain, runtime
code hash, and reviewed source revision. The reviewed Router repository does not yet contain a
completed deployment manifest, so this document makes no current mainnet-deployment claim. The
Lottery testnet release gate will record its disposable Router deployment separately.

Before a Round whose configuration has a nonzero Operator allocation can open, the Lottery checks
that the selected Router has completed bootstrap, has nonzero effective Operator weight, and marks
the Round's Payment Token as registered and deposit-enabled. The same conditions are checked again
before funding.

Settlement never calls the Router. It records Operator revenue by integration version and Payment
Token. A later permissionless flush reduces that exact liability, approves only the requested
amount, calls `addRewards`, clears the approval, and independently verifies the Lottery's spend and
the Router's receipt. Any failure reverts the entire flush, leaving the liability retryable in the
same token and integration-version bucket.
