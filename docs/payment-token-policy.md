# Payment Token Policy

Statics Lottery accepts governance-configured ERC-20 assets. WETH, STATICS, USDG, and any
future asset all use the same token path; native ETH is never ticket principal and receives no
special treatment.

An approved Payment Token must transfer exactly the requested amount, must not rebase, and must
not change balances outside explicit transfers. Every Lottery ingress and egress measures both the
sender's spend and the receiver's receipt around a `SafeERC20` call. A mismatch reverts the entire
transaction. Token decimals are not normalized: configuration values use the token's base units.

Balance-delta checks cannot guarantee that a token remains compatible after the transaction.
Before governance approves an asset, it must review the token's upgrade authority, fee controls,
rebasing behavior, pause and blocklist controls, callback behavior, and any other mutable mechanism
that could prevent the Diamond from satisfying an outstanding liability. A token whose behavior
can later strand claims is outside the supported V1 asset set even if a test transfer succeeds.

Each Round snapshots its Payment Token. Custody and every accounting category remain scoped to
that token so one asset cannot subsidize another.
