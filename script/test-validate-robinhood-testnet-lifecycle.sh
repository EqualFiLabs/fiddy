#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
fixtures=$(mktemp -d)
trap 'rm -rf -- "$fixtures"' EXIT

# Stop at the first RPC boundary. No network connection is made.
cat > "$fixtures/cast" <<'CAST'
#!/usr/bin/env bash
: > "$RPC_MARKER"
exit 42
CAST
chmod +x "$fixtures/cast"
export CAST_BIN="$fixtures/cast" RPC_MARKER="$fixtures/rpc-called"
export ROBINHOOD_TESTNET=offline

assert_mode() {
    local label=$1 expected=$2
    shift 2
    rm -f "$RPC_MARKER"
    local status=0
    bash "$script_dir/validate-robinhood-testnet-lifecycle.sh" "$@" > "$fixtures/output" 2>&1 || status=$?
    if [[ $expected == accepted ]]; then
        [[ $status == 42 && -f $RPC_MARKER ]] || {
            echo "$label: valid mode did not reach RPC boundary" >&2
            cat "$fixtures/output" >&2
            exit 1
        }
    else
        [[ $status != 0 && ! -f $RPC_MARKER ]] || {
            echo "$label: invalid mode did not fail before RPC" >&2
            exit 1
        }
    fi
    echo "PASS: $label"
}

assert_mode default-historical accepted
assert_mode explicit-historical-path accepted "$repo_root/deployments/robinhood-testnet/lifecycle.json"
cp "$repo_root/deployments/robinhood-testnet/lifecycle.json" "$fixtures/copied-history.json"
assert_mode copied-history-needs-model rejected "$fixtures/copied-history.json"

for model in '"legacy"' '"deadline-draws"'; do
    printf '{"lifecycleModel":%s}\n' "$model" > "$fixtures/manifest.json"
    assert_mode "$model" accepted "$fixtures/manifest.json"
done
for model in '"deadline-draw"' '"unspecified"' '""' 'null' 'false' '0' '[]' '{}'; do
    printf '{"lifecycleModel":%s}\n' "$model" > "$fixtures/manifest.json"
    assert_mode "$model" rejected "$fixtures/manifest.json"
done
printf '{}\n' > "$fixtures/manifest.json"
assert_mode missing-model rejected "$fixtures/manifest.json"
printf '{\n' > "$fixtures/manifest.json"
assert_mode malformed-json rejected "$fixtures/manifest.json"
