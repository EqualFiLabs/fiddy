#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET must be set}"

cast_bin=${CAST_BIN:-cast}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
manifest="$repo_root/deployments/robinhood-testnet/registry.json"

assert_equal() {
    local actual=$1
    local expected=$2
    local label=$3
    if [[ ${actual,,} != ${expected,,} ]]; then
        echo "$label mismatch: expected $expected, got $actual" >&2
        exit 1
    fi
}

chain_id=$("$cast_bin" chain-id --rpc-url "$ROBINHOOD_TESTNET")
assert_equal "$chain_id" "$(jq -r '.chainId' "$manifest")" "chain ID"

registry=$(jq -r '.registryDeployment.address' "$manifest")
registry_code=$("$cast_bin" code "$registry" --rpc-url "$ROBINHOOD_TESTNET")
assert_equal \
    "$("$cast_bin" keccak "$registry_code")" \
    "$(jq -r '.registryDeployment.runtimeKeccak256' "$manifest")" \
    "Registry runtime hash"

helper=$(jq -r '.conformanceHarness.address' "$manifest")
helper_code=$("$cast_bin" code "$helper" --rpc-url "$ROBINHOOD_TESTNET")
assert_equal \
    "$("$cast_bin" keccak "$helper_code")" \
    "$(jq -r '.conformanceHarness.runtimeKeccak256' "$manifest")" \
    "conformance harness runtime hash"

while IFS= read -r encoded_validation; do
    validation=$(base64 --decode <<<"$encoded_validation")
    round=$(jq -r '.targetRound' <<<"$validation")
    boundary_timestamp=$(jq -r '.boundary.timestamp' <<<"$validation")
    expected_round_time=$(jq -r '.targetRoundTime' <<<"$validation")

    selected_output=$(
        "$cast_bin" call "$registry" 'firstRoundAfter(uint256)(uint64)' \
            "$boundary_timestamp" --rpc-url "$ROBINHOOD_TESTNET"
    )
    selected=${selected_output%% *}
    assert_equal "$selected" "$round" "selected Quicknet round"

    round_time_output=$(
        "$cast_bin" call "$registry" 'roundTime(uint64)(uint64)' \
            "$round" --rpc-url "$ROBINHOOD_TESTNET"
    )
    round_time=${round_time_output%% *}
    assert_equal "$round_time" "$expected_round_time" "Quicknet round time"
    if (( round_time <= boundary_timestamp )); then
        echo "Quicknet round $round is not strictly after its boundary" >&2
        exit 1
    fi

    assert_equal \
        "$("$cast_bin" call "$registry" 'hasSig(uint64)(bool)' "$round" \
            --rpc-url "$ROBINHOOD_TESTNET")" \
        "true" \
        "cached state"
    assert_equal \
        "$("$cast_bin" call "$registry" 'randomnessOf(uint64)(bytes32)' "$round" \
            --rpc-url "$ROBINHOOD_TESTNET")" \
        "$(jq -r '.registryRandomness' <<<"$validation")" \
        "Registry randomness"

    posted_output=$(
        "$cast_bin" call "$registry" 'postedAt(uint64)(uint64)' \
            "$round" --rpc-url "$ROBINHOOD_TESTNET"
    )
    posted=${posted_output%% *}
    assert_equal "$posted" "$(jq -r '.postedAt' <<<"$validation")" "posting timestamp"

    beacon=$(curl --fail --silent --show-error "$(jq -r '.officialBeaconUrl' <<<"$validation")")
    assert_equal "$(jq -r '.round' <<<"$beacon")" "$round" "official beacon round"
    assert_equal \
        "0x$(jq -r '.randomness' <<<"$beacon")" \
        "$(jq -r '.officialApiRandomness' <<<"$validation")" \
        "official API randomness"

    compressed_signature=0x$(jq -r '.signature' <<<"$beacon")
    representation=$(jq -r '.proofRepresentation' <<<"$validation")
    if [[ $representation == compressed ]]; then
        assert_equal \
            "$("$cast_bin" keccak "$compressed_signature")" \
            "$(jq -r '.submittedProofKeccak256' <<<"$validation")" \
            "compressed proof hash"
    else
        canonical=$(
            "$cast_bin" call "$helper" 'decodeSignature(bytes)(bytes)' \
                "$compressed_signature" --rpc-url "$ROBINHOOD_TESTNET"
        )
        assert_equal \
            "$("$cast_bin" keccak "$canonical")" \
            "$(jq -r '.submittedProofKeccak256' <<<"$validation")" \
            "uncompressed proof hash"

        compressed_result=$(
            "$cast_bin" call "$helper" \
                'verifyAndNormalize(uint64,bytes)(bytes32,bytes)' \
                "$round" "$compressed_signature" --rpc-url "$ROBINHOOD_TESTNET" --json
        )
        uncompressed_result=$(
            "$cast_bin" call "$helper" \
                'verifyAndNormalize(uint64,bytes)(bytes32,bytes)' \
                "$round" "$canonical" --rpc-url "$ROBINHOOD_TESTNET" --json
        )
        assert_equal \
            "$(jq -r '.[0]' <<<"$compressed_result")" \
            "$(jq -r '.[0]' <<<"$uncompressed_result")" \
            "normalized randomness"
        assert_equal \
            "$(jq -r '.[1]' <<<"$compressed_result")" \
            "$(jq -r '.[1]' <<<"$uncompressed_result")" \
            "canonical signature"
    fi
done < <(jq -r '.quicknet.validations[] | @base64' "$manifest")

for transaction_path in \
    '.registryDeployment.transactionHash' \
    '.conformanceHarness.transactionHash' \
    '.quicknet.validations[0].transactionHash' \
    '.quicknet.validations[1].transactionHash'; do
    transaction_hash=$(jq -r "$transaction_path" "$manifest")
    receipt=$("$cast_bin" receipt "$transaction_hash" --rpc-url "$ROBINHOOD_TESTNET" --json)
    assert_equal "$(jq -r '.status' <<<"$receipt")" "0x1" "transaction status"
done

echo "Registry testnet manifest validated on chain $chain_id"
