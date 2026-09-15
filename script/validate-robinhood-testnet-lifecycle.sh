#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET must be set}"

cast_bin=${CAST_BIN:-cast}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
manifest="$repo_root/deployments/robinhood-testnet/lifecycle.json"

assert_equal() {
    local actual=$1
    local expected=$2
    local label=$3
    if [[ ${actual,,} != "${expected,,}" ]]; then
        echo "$label mismatch: expected $expected, got $actual" >&2
        exit 1
    fi
}

scalar_call() {
    $cast_bin call "$@" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" | awk '{print $1}'
}

cast_json_payload() {
    jq -c 'if type == "object" and has("data") then .data else . end'
}

assert_code_hash() {
    local address=$1
    local expected=$2
    local label=$3
    local code
    code=$($cast_bin code "$address" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")
    assert_equal "$($cast_bin keccak "$code")" "$expected" "$label runtime hash"
}

chain_id=$($cast_bin chain-id --rpc-url "$ROBINHOOD_TESTNET")
assert_equal "$chain_id" "$(jq -r '.network.chainId' "$manifest")" "chain ID"
state_block=$(jq '[.transactions[].blockNumber] | max' "$manifest")

diamond=$(jq -r '.contracts.diamond' "$manifest")
registry=$(jq -r '.contracts.drandRegistry' "$manifest")
router=$(jq -r '.contracts.operatorFeeRouter' "$manifest")
weth=$(jq -r '.contracts.weth' "$manifest")
statics=$(jq -r '.contracts.statics' "$manifest")
deployer=$(jq -r '.execution.deployer' "$manifest")
flush_probe=$(jq -r '.contracts.flushProbe.address' "$manifest")
upgrade_facet=$(jq -r '.contracts.upgradeFacet.address' "$manifest")

assert_code_hash \
    "$flush_probe" "$(jq -r '.contracts.flushProbe.runtimeKeccak256' "$manifest")" \
    "Operator flush probe"
assert_code_hash \
    "$upgrade_facet" "$(jq -r '.contracts.upgradeFacet.runtimeKeccak256' "$manifest")" \
    "upgrade facet"

assert_equal \
    "$(scalar_call "$diamond" 'latestRoundId()(uint256)')" \
    "$(jq -r '.finalState.latestRoundId' "$manifest")" \
    "latest Round ID"
assert_equal \
    "$(scalar_call "$diamond" 'activeRoundCount()(uint256)')" \
    "$(jq -r '.finalState.activeRoundCount' "$manifest")" \
    "active Round count"
assert_equal \
    "$(scalar_call "$diamond" 'protocolFinalized()(bool)')" \
    "$(jq -r '.finalState.protocolFinalized' "$manifest")" \
    "protocol finalization"

for version in 1 2; do
    config=$(
        $cast_bin call "$diamond" \
            'lotteryConfig(uint64)((address,uint96,uint32,uint32,uint32,uint32,uint16,uint16,uint96),bool)' \
            "$version" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json
    )
    assert_equal "$(jq -r '.[1]' <<<"$config")" "true" "configuration $version enabled"
done

round_signature='round(uint256)((address,uint96,uint32,uint32,uint32,uint32,uint16,uint16,uint96,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint32,uint32,uint8,address,uint256,uint256,bytes32))'
while IFS= read -r encoded_round; do
    expected=$(base64 --decode <<<"$encoded_round")
    round_id=$(jq -r '.roundId' <<<"$expected")
    live=$(
        $cast_bin call "$diamond" "$round_signature" "$round_id" \
            --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json
    )
    fields=(
        paymentToken _ticketPrice _ticketCount _salesDuration _randomnessDelay
        _maxTicketsPerPurchase _winnerBps _operatorProtocolBps _finalizerTip
        configVersion integrationVersion openedAt expiresAt selloutAt settledAt
        drandRound soldTickets winningTicket status winner receipts
        winnerClaimableAfterClaims applicationSeed
    )
    for index in "${!fields[@]}"; do
        field=${fields[$index]}
        [[ $field == _* ]] && continue
        assert_equal \
            "$(jq -r ".[0][$index]" <<<"$live")" \
            "$(jq -r ".$field" <<<"$expected")" \
            "Round $round_id $field"
    done
    if jq -e 'has("refund")' <<<"$expected" >/dev/null; then
        assert_equal \
            "$(scalar_call "$diamond" 'refundableAmount(uint256,address)(uint256)' "$round_id" "$deployer")" \
            "0" \
            "Round $round_id refund credit"
    fi
done < <(jq -r '.rounds[] | @base64' "$manifest")

for asset_name in weth statics; do
    if [[ $asset_name == weth ]]; then
        asset=$weth
    else
        asset=$statics
    fi
    live_accounting=$(
        $cast_bin call "$diamond" \
            'assetAccounting(address)((uint256,uint256,uint256,uint256,uint256,uint256))' \
            "$asset" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json \
            | jq -c '.[0] | map(tostring)'
    )
    expected_accounting=$(jq -c ".finalState.${asset_name}Accounting" "$manifest")
    assert_equal "$live_accounting" "$expected_accounting" "$asset_name accounting"
    assert_equal \
        "$(scalar_call "$asset" 'balanceOf(address)(uint256)' "$diamond")" \
        "$(jq -r ".finalState.diamond${asset_name^}" "$manifest")" \
        "$asset_name Diamond balance"
    assert_equal \
        "$(scalar_call "$asset" 'balanceOf(address)(uint256)' "$deployer")" \
        "$(jq -r ".finalState.deployer${asset_name^}" "$manifest")" \
        "$asset_name deployer balance"
done

assert_equal \
    "$($cast_bin balance "$deployer" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.finalState.deployerNative' "$manifest")" \
    "deployer native balance"

assert_equal \
    "$(scalar_call "$weth" 'balanceOf(address)(uint256)' "$router")" \
    "$(jq -r '.operatorRouting.routerBalances.weth' "$manifest")" \
    "Router WETH balance"
assert_equal \
    "$(scalar_call "$statics" 'balanceOf(address)(uint256)' "$router")" \
    "$(jq -r '.operatorRouting.routerBalances.statics' "$manifest")" \
    "Router STATICS balance"

for asset_name in weth statics; do
    if [[ $asset_name == weth ]]; then
        asset=$weth
    else
        asset=$statics
    fi
    book=$(
        $cast_bin call "$router" \
            'rewardBook(address)((uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool))' \
            "$asset" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json
    )
    assert_equal \
        "$(jq -r '.[0][2]' <<<"$book")" \
        "$(jq -r ".operatorRouting.rewardBooks.${asset_name}TotalAdded" "$manifest")" \
        "$asset_name Router total added"
    assert_equal \
        "$(jq -r '.[0][4]' <<<"$book")" \
        "$(jq -r ".operatorRouting.rewardBooks.${asset_name}AccountedLiability" "$manifest")" \
        "$asset_name Router liability"
    assert_equal "$(jq -r '.[0][7]' <<<"$book")" "true" "$asset_name registered"
    assert_equal "$(jq -r '.[0][8]' <<<"$book")" "true" "$asset_name enabled"
done

live_upgrade_selectors=$(
    $cast_bin call "$diamond" 'facetFunctionSelectors(address)(bytes4[])' "$upgrade_facet" \
        --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json \
        | jq -c '.[0] | map(ascii_downcase)'
)
expected_upgrade_selectors=$(jq -c '.contracts.upgradeFacet.selectors | map(ascii_downcase)' "$manifest")
assert_equal "$live_upgrade_selectors" "$expected_upgrade_selectors" "upgrade selectors"
assert_equal \
    "$(scalar_call "$diamond" 'lifecycleMarker()(bytes32)')" \
    "$(jq -r '.contracts.upgradeFacet.marker' "$manifest")" \
    "upgrade marker"
for selector in $(jq -r '.contracts.upgradeFacet.selectors[]' "$manifest"); do
    assert_equal \
        "$(scalar_call "$diamond" 'facetAddress(bytes4)(address)' "$selector")" \
        "$upgrade_facet" \
        "upgrade selector $selector"
done

while IFS= read -r encoded_beacon; do
    beacon_record=$(base64 --decode <<<"$encoded_beacon")
    round=$(jq -r '.targetRound' <<<"$beacon_record")
    round_id=$(jq -r '.roundId' <<<"$beacon_record")
    beacon=$(curl --fail --silent --show-error "$(jq -r '.officialBeaconUrl' <<<"$beacon_record")")
    signature=0x$(jq -r '.signature' <<<"$beacon")
    assert_equal "$(jq -r '.round' <<<"$beacon")" "$round" "official beacon Round"
    assert_equal \
        "0x$(jq -r '.randomness' <<<"$beacon")" \
        "$(jq -r '.officialApiRandomness' <<<"$beacon_record")" \
        "official beacon randomness"
    assert_equal \
        "$($cast_bin keccak "$signature")" \
        "$(jq -r '.submittedProofKeccak256' <<<"$beacon_record")" \
        "submitted proof hash"
    assert_equal \
        "$(((${#signature} - 2) / 2))" \
        "$(jq -r '.proofBytes' <<<"$beacon_record")" \
        "proof length"
    assert_equal "$(scalar_call "$registry" 'hasSig(uint64)(bool)' "$round")" "true" "cached beacon"
    assert_equal \
        "$(scalar_call "$registry" 'roundTime(uint64)(uint64)' "$round")" \
        "$(jq -r '.targetRoundTime' <<<"$beacon_record")" \
        "target Round time"
    assert_equal \
        "$(scalar_call "$registry" 'randomnessOf(uint64)(bytes32)' "$round")" \
        "$(jq -r '.registryRandomness' <<<"$beacon_record")" \
        "Registry randomness"
    assert_equal \
        "$(scalar_call "$registry" 'postedAt(uint64)(uint64)' "$round")" \
        "$(jq -r '.postedAt' <<<"$beacon_record")" \
        "Registry posting time"
    sellout=$(jq -r --argjson round_id "$round_id" '.rounds[] | select(.roundId == $round_id) | .selloutAt' "$manifest")
    delay=$(
        $cast_bin call "$diamond" "$round_signature" "$round_id" \
            --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" --json | jq -r '.[0][4]'
    )
    target_time=$(jq -r '.targetRoundTime' <<<"$beacon_record")
    if (( target_time <= sellout + delay )); then
        echo "Quicknet target for Round $round_id is not strictly future" >&2
        exit 1
    fi
done < <(jq -r '.quicknet[] | @base64' "$manifest")

failure_tx=$(jq -r '.operatorRouting.unavailableWethProbe.transactionHash' "$manifest")
failure_receipt=$(
    $cast_bin receipt "$failure_tx" --rpc-url "$ROBINHOOD_TESTNET" --json \
        | cast_json_payload
)
failure_log=$(
    jq -c --arg address "${flush_probe,,}" \
        '.logs[] | select((.address | ascii_downcase) == $address)' <<<"$failure_receipt"
)
assert_equal \
    "0x$(jq -r '.topics[1]' <<<"$failure_log" | tail -c 41)" \
    "${diamond,,}" \
    "Operator failure Diamond topic"
assert_equal \
    "0x$(jq -r '.topics[3]' <<<"$failure_log" | tail -c 41)" \
    "${weth,,}" \
    "Operator failure asset topic"
decoded_failure=$(
    $cast_bin decode-abi 'decode()(uint256,bytes)' "$(jq -r '.data' <<<"$failure_log")" --json \
        | cast_json_payload
)
assert_equal \
    "$(jq -r '.[0]' <<<"$decoded_failure")" \
    "$(jq -r '.operatorRouting.unavailableWethProbe.pendingBefore' "$manifest")" \
    "Operator failure amount"
assert_equal \
    "$(jq -r '.[1]' <<<"$decoded_failure" | cut -c 1-10)" \
    "$(jq -r '.operatorRouting.unavailableWethProbe.observedRevertSelector' "$manifest")" \
    "Operator failure selector"

while IFS= read -r encoded_transaction; do
    expected=$(base64 --decode <<<"$encoded_transaction")
    transaction_hash=$(jq -r '.hash' <<<"$expected")
    receipt=$(
        $cast_bin receipt "$transaction_hash" --rpc-url "$ROBINHOOD_TESTNET" --json \
            | cast_json_payload
    )
    assert_equal \
        "$(jq -r '.status' <<<"$receipt")" \
        "0x$(jq -r '.status' <<<"$expected")" \
        "transaction $transaction_hash status"
    assert_equal \
        "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$receipt")")" \
        "$(jq -r '.blockNumber' <<<"$expected")" \
        "transaction $transaction_hash block"
    assert_equal \
        "$($cast_bin to-dec "$(jq -r '.gasUsed' <<<"$receipt")")" \
        "$(jq -r '.gasUsed' <<<"$expected")" \
        "transaction $transaction_hash gas"
    block=$(
        $cast_bin block "$(jq -r '.blockNumber' <<<"$receipt")" \
            --rpc-url "$ROBINHOOD_TESTNET" --json | cast_json_payload
    )
    assert_equal \
        "$($cast_bin to-dec "$(jq -r '.timestamp' <<<"$block")")" \
        "$(jq -r '.blockTimestamp' <<<"$expected")" \
        "transaction $transaction_hash timestamp"
done < <(jq -r '.transactions[] | @base64' "$manifest")

rejected_cut=$(jq -r '.transactions[] | select(.operation == "reject cut after finalization") | .hash' "$manifest")
rejected_transaction=$(
    $cast_bin tx "$rejected_cut" --rpc-url "$ROBINHOOD_TESTNET" --json \
        | cast_json_payload
)
assert_equal "$(jq -r '.from' <<<"$rejected_transaction")" "$deployer" "rejected cut caller"
assert_equal "$(jq -r '.to' <<<"$rejected_transaction")" "$diamond" "rejected cut target"
assert_equal \
    "$(jq -r '.input' <<<"$rejected_transaction" | cut -c 1-10)" \
    "$($cast_bin sig 'diamondCut((address,uint8,bytes4[])[],address,bytes)')" \
    "rejected cut selector"
if $cast_bin call "$diamond" 'diamondCut((address,uint8,bytes4[])[],address,bytes)' \
    '[]' 0x0000000000000000000000000000000000000000 0x \
    --from "$deployer" --block "$state_block" --rpc-url "$ROBINHOOD_TESTNET" >/dev/null 2>&1; then
    echo "Post-finalization cut unexpectedly succeeds" >&2
    exit 1
fi

echo "Lottery lifecycle manifest validated on chain $chain_id"
