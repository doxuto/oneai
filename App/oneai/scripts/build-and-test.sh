#!/usr/bin/env bash
# =============================================================================
# One AI — Flutter app: analyze + test + build, và ghi report ra reports/<stamp>/
#
#   bash scripts/build-and-test.sh                 # codegen? + analyze + test + build ios
#   bash scripts/build-and-test.sh --analyze-only
#   bash scripts/build-and-test.sh --test-only
#   bash scripts/build-and-test.sh --build-only
#   bash scripts/build-and-test.sh --codegen       # chạy build_runner trước
#   bash scripts/build-and-test.sh --android       # build apk thay vì ios
#   bash scripts/build-and-test.sh --no-build      # bỏ qua bước build nặng
#
# Biến môi trường:
#   MIN_TESTS=<n>   Fail nếu tổng số test chạy < n (mặc định 0 = không ép)
#   FLUTTER=<path>  Đường dẫn flutter (mặc định: tìm trong PATH)
#
# Exit code ≠ 0 khi analyze / test / build fail.
# Mirror của Server/scripts/build-and-test.sh và của SnapTool.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER="${FLUTTER:-$(command -v flutter || true)}"
if [[ -z "$FLUTTER" ]]; then
  for c in "$HOME/development/flutter/bin/flutter" "$HOME/flutter/bin/flutter" "/opt/homebrew/bin/flutter" "/usr/local/bin/flutter"; do
    [[ -x "$c" ]] && FLUTTER="$c" && break
  done
fi
if [[ -z "$FLUTTER" ]]; then
  echo "[build-and-test] Không tìm thấy 'flutter'. Set FLUTTER=/path/to/flutter rồi chạy lại." >&2
  exit 127
fi

DO_ANALYZE=1; DO_TEST=1; DO_BUILD=1; DO_CODEGEN=0; PLATFORM="ios"
MIN_TESTS="${MIN_TESTS:-0}"

for arg in "$@"; do
  case "$arg" in
    --analyze-only) DO_TEST=0; DO_BUILD=0 ;;
    --test-only)    DO_ANALYZE=0; DO_BUILD=0 ;;
    --build-only)   DO_ANALYZE=0; DO_TEST=0 ;;
    --no-build)     DO_BUILD=0 ;;
    --codegen)      DO_CODEGEN=1 ;;
    --android)      PLATFORM="android" ;;
    --ios)          PLATFORM="ios" ;;
    --both)         PLATFORM="both" ;;
    MIN_TESTS=*)    MIN_TESTS="${arg#MIN_TESTS=}" ;;
    *) echo "[build-and-test] Bỏ qua tham số lạ: $arg" ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$ROOT/reports/$STAMP"
mkdir -p "$REPORT"

PUB_EXIT=0; CODEGEN_EXIT=0; ANALYZE_EXIT=0; TEST_EXIT=0; BUILD_EXIT=0
SKIP_BUILD_NOTE=""

echo "[build-and-test] flutter pub get…"
"$FLUTTER" pub get > "$REPORT/pub-get.log" 2>&1; PUB_EXIT=$?
if [[ $PUB_EXIT -ne 0 ]]; then
  echo "pub get failed — xem $REPORT/pub-get.log"
fi

if [[ $DO_CODEGEN -eq 1 && $PUB_EXIT -eq 0 ]]; then
  echo "[build-and-test] build_runner…"
  "$FLUTTER" pub run build_runner build --delete-conflicting-outputs > "$REPORT/codegen.log" 2>&1; CODEGEN_EXIT=$?
fi

if [[ $DO_ANALYZE -eq 1 && $PUB_EXIT -eq 0 ]]; then
  echo "[build-and-test] flutter analyze…"
  "$FLUTTER" analyze --no-fatal-infos > "$REPORT/analyze.log" 2>&1; ANALYZE_EXIT=$?
fi

TOTAL=0; PASSED=0; FAILED=0
if [[ $DO_TEST -eq 1 && $PUB_EXIT -eq 0 ]]; then
  echo "[build-and-test] flutter test…"
  "$FLUTTER" test --reporter expanded --file-reporter "json:$REPORT/test.json" > "$REPORT/test.log" 2>&1; TEST_EXIT=$?
  if [[ -f "$REPORT/test.json" ]]; then
    read -r TOTAL PASSED FAILED < <(python3 - "$REPORT/test.json" <<'PY' || echo "0 0 0"
import json,sys
ok=err=0
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try: e=json.loads(line)
    except Exception: continue
    if e.get("type")=="testDone" and not e.get("hidden"):
        if e.get("result")=="success": ok+=1
        else: err+=1
print(ok+err, ok, err)
PY
)
  fi
  if [[ "$MIN_TESTS" -gt 0 && "$TOTAL" -lt "$MIN_TESTS" ]]; then
    echo "[build-and-test] Chỉ có $TOTAL test (< MIN_TESTS=$MIN_TESTS) → coi là FAIL"
    TEST_EXIT=2
  fi
fi

if [[ $DO_BUILD -eq 1 && $PUB_EXIT -eq 0 ]]; then
  if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "both" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      echo "[build-and-test] flutter build ios --no-codesign…"
      "$FLUTTER" build ios --no-codesign --debug > "$REPORT/build-ios.log" 2>&1; BUILD_EXIT=$?
    else
      SKIP_BUILD_NOTE="build ios bỏ qua (không phải macOS)"
    fi
  fi
  if [[ $BUILD_EXIT -eq 0 && ( "$PLATFORM" == "android" || "$PLATFORM" == "both" ) ]]; then
    echo "[build-and-test] flutter build apk --debug…"
    "$FLUTTER" build apk --debug > "$REPORT/build-android.log" 2>&1; BUILD_EXIT=$?
  fi
fi

STATUS="PASS"
[[ $PUB_EXIT -ne 0 || $CODEGEN_EXIT -ne 0 || $ANALYZE_EXIT -ne 0 || $TEST_EXIT -ne 0 || $BUILD_EXIT -ne 0 ]] && STATUS="FAIL"

{
  echo "# App build & test report — $STAMP"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| **Kết quả** | **$STATUS** |"
  echo "| Exit codes | pub=$PUB_EXIT codegen=$CODEGEN_EXIT analyze=$ANALYZE_EXIT test=$TEST_EXIT build=$BUILD_EXIT |"
  echo "| Platform | $PLATFORM ${SKIP_BUILD_NOTE:+($SKIP_BUILD_NOTE)} |"
  echo "| Tests | total $TOTAL · passed $PASSED · failed $FAILED |"
  echo "| Logs | \`$REPORT/\` |"
  echo
  echo "## Analyzer"
  { grep -E "^ *(error|warning) " "$REPORT/analyze.log" 2>/dev/null | head -60; } || true
  echo
  echo "## Test fail"
  { grep -E "^( *[0-9]+:[0-9]+ )?(\[E\]|Expected:|Actual:|FAILED|Exception|Error:)" "$REPORT/test.log" 2>/dev/null | head -60; } || true
  echo
  echo "## Build fail"
  { grep -E "(error:|Error:|FAILURE:|BUILD FAILED|Exception)" "$REPORT/build-ios.log" "$REPORT/build-android.log" 2>/dev/null | head -60; } || true
} > "$REPORT/summary.md"

ln -sfn "$REPORT" "$ROOT/reports/latest"
cat "$REPORT/summary.md"
[[ "$STATUS" == "PASS" ]]
