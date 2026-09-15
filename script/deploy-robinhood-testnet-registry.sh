#!/usr/bin/env bash
set -euo pipefail

readonly ROBINHOOD_TESTNET_CHAIN_ID=46630
readonly EXPECTED_DEPLOYER=0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316
readonly EXPECTED_FOUNDRY_VERSION=1.7.1
readonly EXPECTED_REGISTRY_COMMIT=cdc760a9bf5bbbc1647d13e43b22858677dacad6
readonly EXPECTED_REGISTRY_RUNTIME_HASH=0xde08fa453cee52a32750e6ff4f736d28b2a4378494cc699e62d27eb44164c1fc

usage() {
    echo "Usage: $0 [--check]" >&2
}

check_only=false
if [[ ${1:-} == "--check" ]]; then
    check_only=true
elif [[ $# -ne 0 ]]; then
    usage
    exit 2
fi

: "${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET must be set}"
: "${ROBINHOOD_TESTNET_DEPLOYER_KEY:?ROBINHOOD_TESTNET_DEPLOYER_KEY must be set}"

forge_bin=${FOUNDRY_BIN:-forge}
cast_bin=${CAST_BIN:-cast}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
registry_root="$repo_root/lib/drand-registry"

foundry_version=$(
    "$forge_bin" --version | sed -n 's/^forge Version: //p' | head -n 1
)
if [[ $foundry_version != "$EXPECTED_FOUNDRY_VERSION" ]]; then
    echo "Unexpected Foundry version: $foundry_version" >&2
    exit 1
fi

chain_id=$("$cast_bin" chain-id --rpc-url "$ROBINHOOD_TESTNET")
if [[ $chain_id != "$ROBINHOOD_TESTNET_CHAIN_ID" ]]; then
    echo "Unexpected chain ID: $chain_id" >&2
    exit 1
fi

deployer=$(
    "$cast_bin" wallet address --private-key "$ROBINHOOD_TESTNET_DEPLOYER_KEY"
)
if [[ ${deployer,,} != ${EXPECTED_DEPLOYER,,} ]]; then
    echo "Unexpected deployer: $deployer" >&2
    exit 1
fi

registry_commit=$(git -C "$registry_root" rev-parse HEAD)
if [[ $registry_commit != "$EXPECTED_REGISTRY_COMMIT" ]]; then
    echo "Unexpected Registry commit: $registry_commit" >&2
    exit 1
fi

runtime_bytecode=$(
    cd -- "$registry_root"
    "$forge_bin" inspect src/EqualFiDrandRegistry.sol:EqualFiDrandRegistry deployedBytecode
)
runtime_hash=$("$cast_bin" keccak "$runtime_bytecode")
if [[ $runtime_hash != "$EXPECTED_REGISTRY_RUNTIME_HASH" ]]; then
    echo "Unexpected Registry runtime hash: $runtime_hash" >&2
    exit 1
fi

balance=$("$cast_bin" balance "$deployer" --rpc-url "$ROBINHOOD_TESTNET")
if [[ $balance == 0 ]]; then
    echo "Deployer has no native gas balance" >&2
    exit 1
fi

echo "Deployment checks passed"
echo "Chain ID: $chain_id"
echo "Deployer: $deployer"
echo "Registry commit: $registry_commit"
echo "Registry runtime hash: $runtime_hash"
echo "Native gas balance: $balance wei"

if $check_only; then
    exit 0
fi

cd -- "$registry_root"
ETH_PRIVATE_KEY="$ROBINHOOD_TESTNET_DEPLOYER_KEY" "$forge_bin" script \
    script/DeployDrandRegistry.s.sol:DeployDrandRegistry \
    --rpc-url "$ROBINHOOD_TESTNET" \
    --sender "$deployer" \
    --private-key "$ROBINHOOD_TESTNET_DEPLOYER_KEY" \
    --broadcast \
    --slow
