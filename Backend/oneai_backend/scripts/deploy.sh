#!/usr/bin/env bash
# =============================================================================
# Deploy backend v2 với chốt chặn. Không bao giờ đụng codebase v1.
#
#   bash scripts/deploy.sh dev            # lint + unit + build → deploy functions:v2 + rules + indexes lên oneai-dev
#   bash scripts/deploy.sh staging
#   bash scripts/deploy.sh prod           # thêm: phải gõ lại "prod" để xác nhận
#   bash scripts/deploy.sh prod --only-rules      # chỉ firestore.rules + storage.rules + indexes
#   bash scripts/deploy.sh dev --skip-tests       # khi vừa chạy test xong ở watcher
#
# Agent KHÔNG chạy script này. Deploy là việc của người.
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
ALIAS="${1:-}"; shift || true
[[ "$ALIAS" =~ ^(dev|staging|prod)$ ]] || { echo "usage: deploy.sh dev|staging|prod [--only-rules] [--skip-tests]"; exit 2; }
ONLY_RULES=0; SKIP_TESTS=0
for a in "$@"; do case "$a" in --only-rules) ONLY_RULES=1;; --skip-tests) SKIP_TESTS=1;; esac; done

PROJECT="$(node -e 'console.log(require("./.firebaserc").projects[process.argv[1]] ?? "")' "$ALIAS")"
[[ -n "$PROJECT" ]] || { echo ".firebaserc: alias $ALIAS chưa có project"; exit 2; }
echo "→ alias $ALIAS = project $PROJECT"

if [[ "$ALIAS" == "prod" ]]; then
  read -r -p "Deploy lên PROD ($PROJECT). Gõ 'prod' để tiếp tục: " ans
  [[ "$ans" == "prod" ]] || { echo "huỷ"; exit 1; }
fi

if [[ $SKIP_TESTS -eq 0 && $ONLY_RULES -eq 0 ]]; then
  ( cd functions-v2 && npm run lint && npm test && npm run build )
fi

# secrets phải tồn tại trước khi deploy function dùng chúng
if [[ $ONLY_RULES -eq 0 ]]; then
  for s in ELEVENLABS_API_KEY OPENAI_API_KEY GEMINI_API_KEY REVENUECAT_WEBHOOK_SECRET; do
    firebase functions:secrets:access "$s" -P "$ALIAS" >/dev/null 2>&1 || { echo "thiếu secret $s trên $PROJECT → firebase functions:secrets:set $s -P $ALIAS"; exit 3; }
  done
fi

# Bucket lifecycle = backstop cho retention (functions xoá theo plan; rule này xoá mọi source > 180 ngày).
BUCKET="$(node -e 'const p=process.argv[1]; console.log(p + ".appspot.com")' "$PROJECT")"
if command -v gsutil >/dev/null 2>&1; then
  gsutil lifecycle set storage.lifecycle.json "gs://$BUCKET" && echo "→ lifecycle đã áp lên gs://$BUCKET"
else
  echo "⚠ không có gsutil: chạy tay  gsutil lifecycle set storage.lifecycle.json gs://$BUCKET"
fi

if [[ $ONLY_RULES -eq 1 ]]; then
  firebase deploy --only firestore:rules,firestore:indexes,storage -P "$ALIAS"
else
  # Thứ tự: rules/indexes trước (an toàn, không có function nào cần index chưa tồn tại), rồi v2.
  firebase deploy --only firestore:rules,firestore:indexes,storage -P "$ALIAS"
  firebase deploy --only functions:v2 -P "$ALIAS"
fi

echo
echo "→ xong. Việc còn lại (một lần, trên console):"
echo "   • TTL policy: field expiresAt trên collection group quota và collection adRewards"
echo "   • AdMob: SSV URL của rewarded unit = URL function adRewardSsv"
echo "   • RevenueCat: webhook URL = URL function revenueCatWebhook, Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>"
echo "   • Remote Config: xem remote-config/README.md (merge, KHÔNG deploy thẳng)"
firebase functions:list -P "$ALIAS" 2>/dev/null | grep -E "adRewardSsv|revenueCatWebhook" || true
