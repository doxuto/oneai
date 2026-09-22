#!/usr/bin/env bash
# =============================================================================
# One AI — Flutter app: Build watcher
#
# Agent (Claude) không có shell trên máy này, nên nó "đặt hàng" build qua file.
# Chạy 1 lần trong Terminal và để đó:
#
#   bash scripts/watch-build.sh
#
# Mỗi khi xuất hiện `.build-request` trong thư mục project, watcher sẽ đọc
# dòng đầu làm tham số cho build-and-test.sh, xoá file, chạy, rồi ghi
# `.build-done` (exit code + tên thư mục report) để agent đọc lại.
#
#   echo "" > .build-request                      # analyze + test + build ios
#   echo "--analyze-only" > .build-request        # chỉ flutter analyze
#   echo "--test-only" > .build-request           # chỉ flutter test
#   echo "--codegen --no-build" > .build-request  # build_runner + analyze + test
#   echo "MIN_TESTS=20 --test-only" > .build-request
#
# Các từ dạng VAR=value ở đầu dòng được truyền làm biến môi trường.
#
# KHÔNG deploy. Watcher này chỉ kiểm tra.
# Ctrl+C để dừng.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
REQUEST="$ROOT/.build-request"
DONE="$ROOT/.build-done"
INTERVAL="${INTERVAL:-3}"

printf '\033[1;32m[watch-build:app]\033[0m Đang chờ %s (Ctrl+C để dừng)\n' "$REQUEST"

while true; do
  if [[ -f "$REQUEST" ]]; then
    sleep 1   # cho file ghi xong
    ARGS="$(cat "$REQUEST" 2>/dev/null | tr -d '\r' | head -n1 || true)"
    rm -f "$REQUEST" "$DONE"
    printf '\n\033[1;32m[watch-build:app]\033[0m %s — nhận yêu cầu (%s)\n' "$(date '+%H:%M:%S')" "${ARGS:-mặc định}"
    ENV_PART=""; REST_PART=""
    for word in $ARGS; do
      if [[ -z "$REST_PART" && "$word" == *=* && "$word" != -* ]]; then
        ENV_PART="$ENV_PART $word"
      else
        REST_PART="$REST_PART $word"
      fi
    done
    # shellcheck disable=SC2086
    env $ENV_PART bash "$ROOT/scripts/build-and-test.sh" $REST_PART
    CODE=$?
    LATEST="$(readlink "$ROOT/reports/latest" 2>/dev/null || true)"
    printf 'exit=%s\nreport=%s\nfinished=%s\n' "$CODE" "$LATEST" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DONE"
    printf '\033[1;32m[watch-build:app]\033[0m Xong (exit %s). Tiếp tục chờ...\n' "$CODE"
  fi
  sleep "$INTERVAL"
done
