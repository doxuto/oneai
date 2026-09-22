#!/usr/bin/env bash
# =============================================================================
# One AI backend — lint + build + test codebase v2 (TypeScript), ghi report ra
# reports/<stamp>/. v1 (functions/, JavaScript) chỉ được syntax-check, KHÔNG sửa.
#
#   bash scripts/build-and-test.sh              # v1 check + lint + build + test v2
#   bash scripts/build-and-test.sh --lint-only  # chỉ eslint + tsc --noEmit
#   bash scripts/build-and-test.sh --test-only  # chỉ vitest
#   bash scripts/build-and-test.sh --v1-check   # chỉ node --check trên functions/
#
# Biến môi trường:
#   MIN_TESTS=<n>  Fail nếu tổng số test < n (mặc định 0)
#
# KHÔNG deploy — đẩy lên Firebase vẫn là việc của người, vì một lần deploy
# thay đổi thứ người dùng thật đang gọi.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
V1="$ROOT/functions"
V2="$ROOT/functions-v2"
MODE="${1:-all}"
MIN_TESTS="${MIN_TESTS:-0}"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$ROOT/reports/$STAMP"
mkdir -p "$REPORT"

V1_EXIT=0; LINT_EXIT=0; BUILD_EXIT=0; TEST_EXIT=0
TOTAL=0; PASSED=0; FAILED=0
NOTES=""

# ---- v1: chỉ kiểm tra cú pháp, không đụng vào ------------------------------
if [[ "$MODE" == "all" || "$MODE" == "--v1-check" ]]; then
  echo "[build-and-test] v1 syntax check (node --check)…"
  {
    find "$V1" -name '*.js' -not -path '*/node_modules/*' -print0 \
      | xargs -0 -n1 node --check 2>&1
  } > "$REPORT/v1-check.log" 2>&1; V1_EXIT=$?
fi
[[ "$MODE" == "--v1-check" ]] && MODE="__v1only"

if [[ "$MODE" != "__v1only" ]]; then
  if [[ ! -d "$V2" ]]; then
    NOTES="functions-v2/ chưa tồn tại — bỏ qua lint/build/test v2 (Sprint 1 sẽ tạo)."
    echo "[build-and-test] $NOTES"
  else
    cd "$V2"
    if [[ ! -d node_modules ]]; then
      echo "[build-and-test] npm ci…"
      npm ci --no-audit --no-fund > "$REPORT/npm-ci.log" 2>&1 \
        || { echo "npm ci failed — xem $REPORT/npm-ci.log"; exit 1; }
    fi

    if [[ "$MODE" != "--test-only" ]]; then
      echo "[build-and-test] lint…"
      npm run -s lint > "$REPORT/lint.log" 2>&1; LINT_EXIT=$?
      echo "[build-and-test] build (tsc)…"
      npm run -s build > "$REPORT/build.log" 2>&1; BUILD_EXIT=$?
    fi

    if [[ "$MODE" != "--lint-only" ]]; then
      echo "[build-and-test] vitest…"
      npx vitest run --reporter=verbose --reporter=json \
        --outputFile="$REPORT/vitest.json" > "$REPORT/test.log" 2>&1; TEST_EXIT=$?
      if [[ -f "$REPORT/vitest.json" ]]; then
        read -r TOTAL PASSED FAILED < <(node -e '
          const r = require(process.argv[1]);
          console.log(r.numTotalTests ?? 0, r.numPassedTests ?? 0, r.numFailedTests ?? 0);
        ' "$REPORT/vitest.json" 2>/dev/null || echo "0 0 0")
      fi
      if [[ "$MIN_TESTS" -gt 0 && "$TOTAL" -lt "$MIN_TESTS" ]]; then
        echo "[build-and-test] Chỉ có $TOTAL test (< MIN_TESTS=$MIN_TESTS) → FAIL"
        TEST_EXIT=2
      fi
    fi
    cd "$ROOT"
  fi
fi

STATUS="PASS"
[[ $V1_EXIT -ne 0 || $LINT_EXIT -ne 0 || $BUILD_EXIT -ne 0 || $TEST_EXIT -ne 0 ]] && STATUS="FAIL"

{
  echo "# Server build & test report — $STAMP"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| **Kết quả** | **$STATUS** |"
  echo "| Exit codes | v1check=$V1_EXIT lint=$LINT_EXIT build=$BUILD_EXIT test=$TEST_EXIT |"
  echo "| Mode | ${1:-all} |"
  echo "| Tests | total $TOTAL · passed $PASSED · failed $FAILED |"
  echo "| Logs | \`$REPORT/\` |"
  [[ -n "$NOTES" ]] && { echo; echo "> $NOTES"; }
  echo
  echo "## v1 syntax errors"
  { grep -E "SyntaxError|Error" "$REPORT/v1-check.log" 2>/dev/null | head -30; } || true
  echo
  echo "## Lỗi type-check / lint"
  { grep -E "error TS|error |✖" "$REPORT/lint.log" "$REPORT/build.log" 2>/dev/null | head -60; } || true
  echo
  echo "## Test fail"
  { grep -E "^\s*(✗|×|FAIL|AssertionError|Error:)" "$REPORT/test.log" 2>/dev/null | head -60; } || true
} > "$REPORT/summary.md"

ln -sfn "$REPORT" "$ROOT/reports/latest"
cat "$REPORT/summary.md"
[[ "$STATUS" == "PASS" ]]
