#!/usr/bin/env bash
# =============================================================================
# One AI — Git watcher: cho phép agent (Claude) chạy git qua file.
#
#   bash scripts/watch-git.sh      # chạy 1 lần, để mở
#
# Khi xuất hiện `.git-request` (ở thư mục project hoặc repo gốc):
#   - dòng đầu bắt đầu bằng `#cmd:` → chạy lệnh git sau đó
#     (chỉ cho phép: status log diff add commit branch checkout switch stash
#                    pull push restore rm mv tag fetch show rev-parse)
#   - ngược lại: `git add -A` rồi `git commit -F .git-request`
#
# Kết quả ghi vào `.git-done` để agent đọc lại. File request bị xoá sau khi xử lý.
#
# LƯU Ý: `push` nằm trong danh sách cho phép. Bỏ nó khỏi $ALLOWED nếu bạn muốn
# tự tay đẩy code.
# =============================================================================
set -u
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")"
REQUESTS=("$PROJECT_DIR/.git-request" "$REPO_DIR/.git-request")
DONE="$PROJECT_DIR/.git-done"
ALLOWED="status|log|diff|add|commit|branch|checkout|switch|stash|pull|push|restore|rm|mv|tag|fetch|show|rev-parse"

printf '\033[1;32m[watch-git]\033[0m repo %s — đang chờ .git-request (Ctrl+C để dừng)\n' "$REPO_DIR"
while true; do
  for REQ in "${REQUESTS[@]}"; do
    [[ -f "$REQ" ]] || continue
    sleep 1   # cho file ghi xong
    cd "$REPO_DIR" || exit 1
    FIRST="$(head -n1 "$REQ")"
    {
      echo "started=$(date -u +%FT%TZ)"
      if [[ "$FIRST" == "#cmd:"* ]]; then
        CMD="${FIRST#\#cmd:}"
        SUB="$(echo "$CMD" | awk '{print $1}')"
        if [[ "$SUB" =~ ^($ALLOWED)$ ]]; then
          echo "\$ git $CMD"
          eval "git $CMD" 2>&1
          echo "exit=$?"
        else
          echo "refused: git $SUB không nằm trong danh sách cho phép"
          echo "exit=126"
        fi
      else
        echo "\$ git add -A && git commit -F .git-request"
        git add -A 2>&1
        git commit -F "$REQ" 2>&1
        echo "exit=$?"
        git log -1 --oneline 2>&1
      fi
      echo "finished=$(date -u +%FT%TZ)"
    } > "$DONE" 2>&1
    rm -f "$REQ"
    printf '\033[1;32m[watch-git]\033[0m xong → %s\n' "$DONE"
    sed -n '1,15p' "$DONE"
  done
  sleep 3
done
