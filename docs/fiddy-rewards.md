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
