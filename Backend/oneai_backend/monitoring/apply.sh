#!/usr/bin/env bash
# Alerting as code (docs/15-RUNBOOK.md §"Alert nên đặt"). Idempotent: re-running
# updates metrics in place and skips policies that already exist by display name.
#
#   PROJECT_ID=oneai-dev NOTIFY_EMAIL=contact@doxutostudio.top ./monitoring/apply.sh
#
# Needs: gcloud authed with roles/monitoring.editor + roles/logging.configWriter.
set -euo pipefail
: "${PROJECT_ID:?set PROJECT_ID}"
: "${NOTIFY_EMAIL:?set NOTIFY_EMAIL}"
cd "$(dirname "$0")"

# ---- 1. one e-mail notification channel (reused by every policy) ----
CHANNEL=$(gcloud monitoring channels list --project "$PROJECT_ID" \
  --filter="type=email AND labels.email_address=$NOTIFY_EMAIL" --format="value(name)" | head -n1)
if [ -z "$CHANNEL" ]; then
  CHANNEL=$(gcloud monitoring channels create --project "$PROJECT_ID" \
    --display-name="One AI on-call" --type=email --channel-labels="email_address=$NOTIFY_EMAIL" --format="value(name)")
fi
echo "channel: $CHANNEL"

# ---- 2. log-based metrics: one counter per structured log event we alert on ----
metric() { # name filter description
  if gcloud logging metrics describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud logging metrics update "$1" --project "$PROJECT_ID" --log-filter="$2" --description="$3" >/dev/null
  else
    gcloud logging metrics create "$1" --project "$PROJECT_ID" --log-filter="$2" --description="$3" >/dev/null
  fi
  echo "metric: $1"
}
FN='resource.type="cloud_run_revision" OR resource.type="cloud_function"'
metric oneai_pipeline_failed      "$FN AND jsonPayload.message=\"pipeline.error\" AND jsonPayload.retryable=false" "Transcription failed permanently (credit refunded)"
metric oneai_job_reaped           "$FN AND jsonPayload.message=\"job.reaped\""                                          "Worker never finished; reaper failed the job"
metric oneai_stt_upstream_5xx     "$FN AND (jsonPayload.message=\"elevenlabs.upstream_5xx\" OR jsonPayload.message=\"gemini-stt.upstream_5xx\")" "STT vendor 5xx"
metric oneai_stt_fallback         "$FN AND jsonPayload.message=\"stt.fallback\""                                        "Primary STT vendor failed; fallback used"
metric oneai_revenuecat_unauth    "$FN AND jsonPayload.message=\"revenuecat.unauthorized\""                             "RevenueCat webhook with wrong secret"
metric oneai_index_missing        "$FN AND jsonPayload.message=\"minute.list.index_missing\""                            "Firestore index missing (listMinutes)"
metric oneai_push_failed          "$FN AND jsonPayload.message=\"push.minute.failed\""                                   "FCM send threw"

# ---- 3. alert policies ----
policy() { # file
  local name; name=$(python3 -c "import json,sys;print(json.load(open('$1'))['displayName'])")
  if gcloud alpha monitoring policies list --project "$PROJECT_ID" --filter="displayName=\"$name\"" --format="value(name)" | grep -q .; then
    echo "policy exists: $name"; return
  fi
  sed -e "s|__PROJECT_ID__|$PROJECT_ID|g" -e "s|__CHANNEL__|$CHANNEL|g" "$1" > /tmp/policy.json
  gcloud alpha monitoring policies create --project "$PROJECT_ID" --policy-from-file=/tmp/policy.json >/dev/null
  echo "policy: $name"
}
for f in policies/*.json; do policy "$f"; done

cat <<MSG

Done. Still manual (needs the billing account id):
  gcloud billing budgets create --billing-account=BILLING_ID --display-name="One AI monthly" \\
    --budget-amount=100USD --threshold-rule=percent=0.8 --threshold-rule=percent=1.0 \\
    --filter-projects=projects/$PROJECT_ID
MSG
