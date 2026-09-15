#!/usr/bin/env bash
set -euo pipefail

result_dir="${1:?usage: run-halmos.sh RESULT_DIR}"
mkdir -p "$result_dir"

set +e
halmos \
  --match-contract '^(LotteryCommitmentHalmosTest|LotterySettlementHalmosTest|LotteryClaimsHalmosTest|LotteryRevenueHalmosTest|LotteryCutsHalmosTest)$' \
  --solver z3 \
  --storage-layout generic \
  --solver-timeout-branching 0 \
  --solver-timeout-assertion 0 \
  --panic-error-codes '*' \
  --json-output "$result_dir/halmos.json" \
  2>&1 | tee "$result_dir/halmos.log"
status="${PIPESTATUS[0]}"
set -e

printf '%s\n' "$status" > "$result_dir/halmos.exit"
exit "$status"
