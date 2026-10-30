# FIDDY rewards

## Token and custody

FIDDY is the Lottery Diamond's restricted ERC-20, backed one-for-one in STATICS
base units. Exact STATICS funding credits unallocated inventory. Issuance moves
inventory into allocated backing and mints the same FIDDY to protocol custody,
credited to a canonical PositionNFT account. Inventory exhaustion issues only
available units, reports the shortfall and creates no debt.

Ordinary transfers require either endpoint to be an explicitly approved consumer.
There is no implicit governance exemption. Exact protocol movements handle account
deposits/withdrawals; raw transfers into custody do not credit accounts. External
FIDDY can be deposited into an owned PositionNFT and unstaked account FIDDY can
be withdrawn. Approval does not confer account authority. Consumer approval
does not confer mint, redemption or reserve authority. Revocation affects future
ordinary transfers; consumers are trusted integration contracts and must not
trap their users' holdings. No AMM is installed by this extension.

Wrap and unwrap launch independently disabled, with zero public wrap cap. When
explicitly enabled, wrapping pulls exact STATICS, credits an owned account and
increments public-wrap outstanding. Unwrapping burns unstaked account FIDDY and
returns exact STATICS; outstanding decreases by min(redemption, outstanding).
Participation issuance consumes no public wrap capacity. Unwrap does not change
the cap. No arbitrary inventory/backing withdrawal or unbacked mint exists.

## Configuration and participation

Reward settings are additional immutable per-version state and separately
snapshotted per round. Existing embedded configurations, round fields, enums and
reserved historical slots keep their layout. Missing settings mean no rewards.
New reward configurations require explicit rates/splits and start disabled.
The 50% winner baseline remains; no illustrative staker split is a launch choice.

Winner = floor(gross * winnerBps / 10000). Operators and stakers each receive
their configured percentage of the protocol remainder; their BPS sum cannot
exceed 10000. Treasury receives the remainder, with the finalizer tip capped
by that Treasury allocation. Existing rounds retain their original economics.
Both opening (including its initial purchase) and later buying accept explicit
PositionNFT selection. Reward-enabled configurations cannot use accountless
entrypoints. Tickets/winner claims remain wallet-owned under existing semantics.

## Account authority and lifecycle

Financial actions require current ownerOf, never NFT approvals. One aggregate
Fiddy external leg attaches atomically with the first financial state and remains
for token holdings, stake or pending/indexed entitlement. NFT transfer changes
financial control and carries prior rewards without moving reserves. The seller
must claim before sale if desired. Unstaking does not redeem underlying.

One Operator may register to one PositionNFT per module and vice versa. Both
NFTs must be owned by the registering caller. Read activation directly, retain
the applied multiplier and both transfer markers. Base weight is 10000 BPS.
Explicit refresh applies higher activation prospectively. Ownership-changing
transfers of either NFT invalidate boosts, including round trips and recovery;
raw stake and prior earnings remain intact. Statics linking is unrelated.

## Funded ordering and bounded progress

Settlement reserves the staker allocation immediately and enqueues asset, amount
and observed shared transfer head. A single FIFO and transfer cursor preserve
order. Before indexing a batch, replay transfers through its original head,
checkpoint affected accounts at the old per-asset indexes, then adjust weights.
No later transfer or refreshed activation may affect an earlier funded batch.

Processing accepts a bounded work budget and retains transfer/asset cursors.
A partial transfer checkpoint prevents indexing until completed. Permissionless
account checkpoint pagination prepares denominator changes; new indexed revenue
invalidates completion until caught up. Earlier funded batches and current
transfer/checkpoint synchronization are required before stake/unstake or
registration changes. Claims of indexed earnings remain independent of backlog.

Zero-weight batches route to Treasury. Global division dust is separately
reserved and never reinjected into indexes. Accounts retain fractional earnings;
empty-account cleanup may explicitly surrender only sub-unit fractions. No
whole claim or FIDDY balance is erased to detach a leg. Pending becomes indexed
without reserving funds twice. All payment assets remain independent.

## Integration, trust and release boundaries

Pin the generic Statics candidate at
5027bfaa58af7309d53fca0f32ae574d87420f83 for actual-source tests. Statics supplies
lifecycle, discovery and ordered history, with no product callbacks. Boosts
require qualified registry-consumer handoff and continuous history coverage.
Moving the upstream consumer away and back can create an undetectable recording
gap; governance must preserve coverage. There is no fabricated history fallback.

Lottery governance retains configuration, consumer and conversion permissions,
and pre-finalization upgrade power. Accounts/actions are public and directly
callable without a mandatory relayer. Catch-up requires someone to submit its
permissionless transactions. Chain ordering and token operational assumptions
remain those of the base Lottery. Existing source licensing is unchanged.

Actual-candidate local integration and block-pinned fork evidence are separate
from deployment. This extension authorizes no live transactions or conversion
activation. Historical formal reports do not prove the new system.

## Client and deployment preparation

Install token, staking and view selector groups together with the updated purchase, governance,
settlement and surplus facets. Existing round and configuration layouts are unchanged; reward
extensions use a separate namespace and default to zero for existing rounds. The deployment script
installs these selectors but leaves FIDDY uninitialized until governance supplies verified bindings
through `initializeFiddy(STATICS, PositionNFT, Operators, activationRegistry)`. This is one-time.
No reward configuration is enabled by this initialization. Both conversions, wrap capacity, boosts
and external consumer approval launch at zero/false.

Before enabling boosts, qualify both history coverage records and the registry's actual consumer
handoff. Continuous recording after that handoff is an integration trust assumption. Missing history
cannot be reconstructed by this module. Do not enable against unqualified or interrupted history.

Clients read `fiddyReserve`, `fiddyAccount`, `fiddyOperatorAccount`, `fiddyAsset`, `fiddyCredit`,
`indexedFiddyRevenue`, `fiddyProcessing`, `fiddyBatch` and paginated `fiddyRevenueAssets` separately.
Account balance includes raw stake; available FIDDY is balance minus stake. Pending batch revenue
is not an indexed claim. Show checkpoint revision/cursor and processing progress before proposing
stake or registration changes. Anyone may process up to 100 units or checkpoint up to 100 assets
per call. Continue until transfers and earlier funded batches are drained, then checkpoint the
selected account through every asset at the current revision. An index update invalidates that
completion. Claims remain available during catch-up and pause.

`registerFiddyOperator` also switches or explicitly refreshes a registration. Activation alone does
not increase Fiddy weight. Statics link/unlink has no Fiddy weight effect. Account cleanup is also
paginated and can detach only an empty account after whole claims have been paid.

Run the independent pinned Statics build before Fiddy tests, then the ABI parity check:

```sh
bash script/build-legacy-baseline.sh
forge build --config-path integration/foundry.toml
forge build
python3 script/check-statics-abi.py
forge test --match-path 'test/Fiddy*.t.sol'
```

The Statics fixture uses its compiler/EVM/optimizer settings and local launch funding. Fiddy tests
deploy its resulting artifacts with their actual bytecode. These local fixtures are distinct from
block-pinned live dependency qualification. Neither executes a deployment transaction.

Fork qualification uses Robinhood L2 block 101439372, hash `0x81582e4e3659a1e4ad74399fc8ea090acfe2878468029d7dedf3f54e5ec988f4`. Its `NUMBER` opcode returns L1 block 26303058. The test performs only local fork impersonation and candidate creation; it does not broadcast. Runtime code hashes are checked against the pinned deployment manifest before the registry handoff.
