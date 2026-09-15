#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET must be set}"

cast_bin=${CAST_BIN:-cast}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
manifest="$repo_root/deployments/robinhood-testnet/lottery.json"

assert_equal() {
    local actual=$1
    local expected=$2
    local label=$3
    if [[ ${actual,,} != "${expected,,}" ]]; then
        echo "$label mismatch: expected $expected, got $actual" >&2
        exit 1
    fi
}

assert_code_hash() {
    local address=$1
    local expected=$2
    local label=$3
    local code
    code=$($cast_bin code "$address" --rpc-url "$ROBINHOOD_TESTNET")
    assert_equal "$($cast_bin keccak "$code")" "$expected" "$label runtime hash"
}

chain_id=$($cast_bin chain-id --rpc-url "$ROBINHOOD_TESTNET")
assert_equal "$chain_id" "$(jq -r '.network.chainId' "$manifest")" "chain ID"

assert_equal \
    "$(jq -r '.externalDependencies.operatorFeeRouter.operatorCollection' "$manifest")" \
    "$(jq -r '.externalDependencies.staticsGenesisReplica.contracts.operatorCollection.address' "$manifest")" \
    "Router Operator collection provenance"
assert_equal \
    "$(jq -r '.externalDependencies.operatorFeeRouter.activationRegistry' "$manifest")" \
    "$(jq -r '.externalDependencies.staticsGenesisReplica.contracts.activationRegistry.address' "$manifest")" \
    "Router activation registry provenance"
assert_equal \
    "$(jq -r '.externalDependencies.operatorFeeRouter.operatorVault' "$manifest")" \
    "$(jq -r '.externalDependencies.staticsGenesisReplica.contracts.operatorVault.address' "$manifest")" \
    "Router Operator vault provenance"
assert_equal \
    "$(jq -r '.externalDependencies.paymentTokens[] | select(.symbol == "WETH") | .address' "$manifest")" \
    "$(jq -r '.externalDependencies.staticsGenesisReplica.contracts.weth.address' "$manifest")" \
    "WETH provenance"
assert_equal \
    "$(jq -r '.externalDependencies.paymentTokens[] | select(.symbol == "STATICS") | .address' "$manifest")" \
    "$(jq -r '.externalDependencies.staticsGenesisReplica.contracts.statics.address' "$manifest")" \
    "STATICS provenance"

diamond=$(jq -r '.deployment.diamond.address' "$manifest")
state_block=$(jq -r '.deployment.initialCut.blockNumber' "$manifest")
assert_code_hash \
    "$diamond" \
    "$(jq -r '.deployment.diamond.runtimeKeccak256' "$manifest")" \
    "Diamond"
assert_code_hash \
    "$(jq -r '.deployment.initializer.address' "$manifest")" \
    "$(jq -r '.deployment.initializer.runtimeKeccak256' "$manifest")" \
    "initializer"

while IFS= read -r encoded_facet; do
    facet=$(base64 --decode <<<"$encoded_facet")
    address=$(jq -r '.address' <<<"$facet")
    name=$(jq -r '.name' <<<"$facet")
    assert_code_hash "$address" "$(jq -r '.runtimeKeccak256' <<<"$facet")" "$name"

    live_selectors=$(
        $cast_bin call "$diamond" 'facetFunctionSelectors(address)(bytes4[])' \
            "$address" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json \
            | jq -c '.[0] | map(ascii_downcase)'
    )
    expected_selectors=$(jq -c '.selectors | map(ascii_downcase)' <<<"$facet")
    assert_equal "$live_selectors" "$expected_selectors" "$name selectors"
done < <(jq -r '.deployment.facets[] | @base64' "$manifest")

live_facet_addresses=$(
    $cast_bin call "$diamond" 'facetAddresses()(address[])' \
        --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json \
        | jq -c '.[0] | map(ascii_downcase)'
)
expected_facet_addresses=$(jq -c '[.deployment.facets[].address | ascii_downcase]' "$manifest")
assert_equal "$live_facet_addresses" "$expected_facet_addresses" "facet address list"

assert_equal \
    "$($cast_bin call "$diamond" 'guardian()(address)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.roles.guardian' "$manifest")" \
    "guardian"
assert_equal \
    "$($cast_bin call "$diamond" 'treasuryRecipient()(address)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.roles.treasuryRecipient' "$manifest")" \
    "Treasury recipient"
authority=$(jq -r '.roles.authority' "$manifest")
$cast_bin call "$diamond" 'setMaxActiveRounds(uint16)' \
    "$(jq -r '.initialState.maxActiveRounds' "$manifest")" \
    --from "$authority" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" >/dev/null
if $cast_bin call "$diamond" 'setMaxActiveRounds(uint16)' \
    "$(jq -r '.initialState.maxActiveRounds' "$manifest")" \
    --from 0x0000000000000000000000000000000000000001 \
    --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" >/dev/null 2>&1; then
    echo "Unauthorized authority probe unexpectedly succeeded" >&2
    exit 1
fi
assert_equal \
    "$($cast_bin call "$diamond" 'maxActiveRounds()(uint16)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.initialState.maxActiveRounds' "$manifest")" \
    "maximum active Rounds"
assert_equal \
    "$($cast_bin call "$diamond" 'activeRoundCount()(uint256)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.initialState.activeRoundCount' "$manifest")" \
    "active Round count"
assert_equal \
    "$($cast_bin call "$diamond" 'latestRoundId()(uint256)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.initialState.latestRoundId' "$manifest")" \
    "latest Round ID"
assert_equal \
    "$($cast_bin call "$diamond" 'paused()(bool)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.initialState.paused' "$manifest")" \
    "pause state"
assert_equal \
    "$($cast_bin call "$diamond" 'protocolFinalized()(bool)' --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.initialState.protocolFinalized' "$manifest")" \
    "finalization state"

integration=$(
    $cast_bin call "$diamond" 'currentIntegration()((address,address),uint64)' \
        --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json
)
assert_equal \
    "$(jq -r '.[0][0]' <<<"$integration")" \
    "$(jq -r '.externalDependencies.drandRegistry.address' "$manifest")" \
    "drand Registry"
assert_equal \
    "$(jq -r '.[0][1]' <<<"$integration")" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.address' "$manifest")" \
    "Operator Fee Router"
assert_equal \
    "$(jq -r '.[1]' <<<"$integration")" \
    "$(jq -r '.initialState.integrationVersion' "$manifest")" \
    "integration version"

while IFS= read -r encoded_config; do
    config=$(base64 --decode <<<"$encoded_config")
    version=$(jq -r '.version' <<<"$config")
    live=$(
        $cast_bin call "$diamond" \
            'lotteryConfig(uint64)((address,uint96,uint32,uint32,uint32,uint32,uint16,uint16,uint96),bool)' \
            "$version" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json
    )
    fields=(
        paymentToken ticketPrice ticketCount salesDuration randomnessDelay
        maxTicketsPerPurchase winnerBps operatorProtocolBps finalizerTip
    )
    for index in "${!fields[@]}"; do
        field=${fields[$index]}
        assert_equal \
            "$(jq -r ".[0][$index]" <<<"$live")" \
            "$(jq -r ".$field" <<<"$config")" \
            "configuration $version $field"
    done
    assert_equal \
        "$(jq -r '.[1]' <<<"$live")" \
        "$(jq -r '.enabled' <<<"$config")" \
        "configuration $version enabled state"
done < <(jq -r '.initialState.configurations[] | @base64' "$manifest")

registry=$(jq -r '.externalDependencies.drandRegistry.address' "$manifest")
assert_code_hash \
    "$registry" \
    "$(jq -r '.externalDependencies.drandRegistry.runtimeKeccak256' "$manifest")" \
    "drand Registry"

while IFS= read -r encoded_dependency; do
    dependency=$(base64 --decode <<<"$encoded_dependency")
    assert_code_hash \
        "$(jq -r '.value.address' <<<"$dependency")" \
        "$(jq -r '.value.runtimeKeccak256' <<<"$dependency")" \
        "Statics Genesis $(jq -r '.key' <<<"$dependency")"
done < <(jq -r '.externalDependencies.staticsGenesisReplica.contracts | to_entries[] | @base64' "$manifest")

router=$(jq -r '.externalDependencies.operatorFeeRouter.address' "$manifest")
admin=$(jq -r '.externalDependencies.operatorFeeRouter.testnetAdmin.address' "$manifest")
assert_code_hash \
    "$router" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.runtimeKeccak256' "$manifest")" \
    "Operator Fee Router"
assert_code_hash \
    "$admin" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.testnetAdmin.runtimeKeccak256' "$manifest")" \
    "testnet Router admin"
assert_equal \
    "$($cast_bin call "$admin" 'owner()(address)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.testnetAdmin.owner' "$manifest")" \
    "testnet Router admin owner"
assert_equal \
    "$($cast_bin call "$admin" 'router()(address)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$router" \
    "testnet Router admin binding"
assert_equal \
    "$($cast_bin call "$router" 'bootstrapFinalized()(bool)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "true" \
    "Router bootstrap state"
assert_equal \
    "$($cast_bin call "$router" 'nextOperatorId()(uint256)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.nextOperatorId' "$manifest")" \
    "Router bootstrap cursor"
assert_equal \
    "$($cast_bin call "$router" 'totalEffectiveWeight()(uint256)' --rpc-url "$ROBINHOOD_TESTNET" | awk '{print $1}')" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.totalEffectiveWeight' "$manifest")" \
    "Router effective weight"

while IFS= read -r asset; do
    assert_code_hash \
        "$asset" \
        "$(jq -r --arg asset "$asset" '.externalDependencies.paymentTokens[] | select((.address | ascii_downcase) == ($asset | ascii_downcase)) | .runtimeKeccak256' "$manifest")" \
        "Payment Token $asset"
    assert_equal \
        "$($cast_bin call "$router" 'isRewardAsset(address)(bool)' "$asset" --rpc-url "$ROBINHOOD_TESTNET")" \
        "true" \
        "Router registration for $asset"
    assert_equal \
        "$($cast_bin call "$router" 'rewardAssetEnabled(address)(bool)' "$asset" --rpc-url "$ROBINHOOD_TESTNET")" \
        "true" \
        "Router enabled state for $asset"
done < <(jq -r '.externalDependencies.paymentTokens[].address' "$manifest")

while IFS= read -r encoded_transaction; do
    transaction=$(base64 --decode <<<"$encoded_transaction")
    transaction_hash=$(jq -r '.transactionHash' <<<"$transaction")
    receipt=$($cast_bin receipt "$transaction_hash" --rpc-url "$ROBINHOOD_TESTNET" --json)
    assert_equal "$(jq -r '.status' <<<"$receipt")" "0x1" "transaction $transaction_hash"
    assert_equal \
        "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$receipt")")" \
        "$(jq -r '.blockNumber' <<<"$transaction")" \
        "transaction $transaction_hash block"
    assert_equal \
        "$($cast_bin to-dec "$(jq -r '.gasUsed' <<<"$receipt")")" \
        "$(jq -r '.gasUsed' <<<"$transaction")" \
        "transaction $transaction_hash gas"
done < <(
    jq -r '
        .externalDependencies.operatorFeeRouter.deploymentTransactions[],
        .deployment.diamond,
        .deployment.initializer,
        .deployment.initialCut,
        .deployment.facets[]
        | @base64
    ' "$manifest"
)

mapfile -t configuration_transactions < <(
    jq -r '.externalDependencies.operatorFeeRouter.configurationTransactionHashes[]' "$manifest"
)
for transaction_hash in "${configuration_transactions[@]}"; do
    receipt=$($cast_bin receipt "$transaction_hash" --rpc-url "$ROBINHOOD_TESTNET" --json)
    assert_equal "$(jq -r '.status' <<<"$receipt")" "0x1" "transaction $transaction_hash"
done
first_configuration_receipt=$(
    $cast_bin receipt "${configuration_transactions[0]}" --rpc-url "$ROBINHOOD_TESTNET" --json
)
last_configuration_index=$((${#configuration_transactions[@]} - 1))
last_configuration_receipt=$(
    $cast_bin receipt "${configuration_transactions[$last_configuration_index]}" \
        --rpc-url "$ROBINHOOD_TESTNET" --json
)
assert_equal \
    "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$first_configuration_receipt")")" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.configurationBlockRange.first' "$manifest")" \
    "first Router configuration block"
assert_equal \
    "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$last_configuration_receipt")")" \
    "$(jq -r '.externalDependencies.operatorFeeRouter.configurationBlockRange.last' "$manifest")" \
    "last Router configuration block"

echo "Lottery testnet manifest validated on chain $chain_id"
