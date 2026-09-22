# Monitoring

v2 functions are Cloud Run services. Logs go to Cloud Logging, thrown errors to Error Reporting, metrics to Cloud Monitoring under both `cloud_run_revision` and the Cloud Functions views. Set up structured logs, three alerting policies, and an uptime check with the first staging deploy.

## Structured logging

```ts
import { logger } from "firebase-functions";   // same as "firebase-functions/logger"

logger.info("extractText.start", { uid, scanId, pages, revision: process.env.K_REVISION });
logger.warn("extractText.quota", { uid, used, quota });
logger.error("extractText.failed", { uid, scanId, err });      // pass the Error object → stack in Error Reporting
logger.debug("gemini.usage", { promptTokens: res.usageMetadata?.promptTokenCount, outputTokens: res.usageMetadata?.candidatesTokenCount });
logger.write({ severity: "NOTICE", message: "custom severity", uid });
```

Conventions:

- First argument is a stable, dotted event name (`<function>.<event>`); everything else is a field. Query on `jsonPayload.message="extractText.failed"` and group on fields — never grep free text.
- Always include `uid` (or `"anon"`), the primary entity id, and `revision`. Never include tokens, emails, raw document text, or full Gemini prompts.
- `console.log` prints a plain string with no severity — fine for a one-off, wrong for anything you will query.
- One `info` at start and one at end per invocation with a `ms` field is enough; per-step logs go to `debug` and stay off in prod (`logger.debug` is emitted at `DEBUG` severity; exclude it with a log sink filter or leave it — Cloud Logging's free tier is 50 GiB/month per project).
- Uncaught errors and rejected promises from a handler are logged at `ERROR` with the stack by the framework and recorded in Error Reporting. An `HttpsError` you throw deliberately is **not** an error — it is logged as a normal response; log a `warn` yourself if it matters.

## Reading logs

```bash
firebase functions:log -P prod                        # recent, all functions
firebase functions:log -P prod --only extractText,sendPush -n 200
```

Cloud Logging (console → Logs Explorer, or `gcloud logging read`):

```
# One v2 function (Cloud Run service names are lowercase)
resource.type="cloud_run_revision"
resource.labels.service_name="extracttext"

# Only errors from any function, last hour
resource.type="cloud_run_revision"
severity>=ERROR

# A structured event with a field filter
jsonPayload.message="extractText.failed"
jsonPayload.uid="u_123"

# One request end to end (v2 attaches a trace id)
trace="projects/snaptool-prod/traces/<id>"
```

```bash
gcloud logging read 'resource.type="cloud_run_revision" AND severity>=ERROR' --project snaptool-prod --freshness 1h --limit 50 --format json
```

The Firebase console → Functions → Logs tab wraps the same data with a per-function filter; the Cloud Run console for the service shows the same logs plus revision and instance metrics.

## Error Reporting

- Every thrown non-`HttpsError` and every `logger.error(msg, { err })` with an `Error` instance is grouped by stack trace in Error Reporting (console → Error Reporting). Groups have a first-seen / last-seen and a per-revision histogram — the fastest way to see "new since deploy".
- Turn on email/Slack notifications for **new** error groups in prod; do not notify on every occurrence.
- Errors from an `HttpsError("internal", ...)` you throw on purpose do not appear — wrap the underlying error: `logger.error("x.failed", { err }); throw new HttpsError("internal", "Try again later");`.

## Alerting policies

Three policies per environment (prod gets a pager channel; staging gets a Slack channel). Notification channels are created once (`gcloud beta monitoring channels create` or the console) and referenced by id.

### 1. Error rate > 2 % for 5 minutes

```json
{
  "displayName": "functions: 5xx ratio > 2% (5m)",
  "combiner": "OR",
  "conditions": [{
    "displayName": "5xx / all requests",
    "conditionThreshold": {
      "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\"",
      "denominatorFilter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\"",
      "aggregations": [{ "alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_RATE", "crossSeriesReducer": "REDUCE_SUM", "groupByFields": ["resource.labels.service_name"] }],
      "denominatorAggregations": [{ "alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_RATE", "crossSeriesReducer": "REDUCE_SUM", "groupByFields": ["resource.labels.service_name"] }],
      "comparison": "COMPARISON_GT",
      "thresholdValue": 0.02,
      "duration": "300s",
      "trigger": { "count": 1 }
    }
  }],
  "notificationChannels": ["projects/snaptool-prod/notificationChannels/CHANNEL_ID"]
}
```

```bash
gcloud alpha monitoring policies create --project snaptool-prod --policy-from-file alerts/error-rate.json
```

(`gcloud alpha monitoring policies` — verify the command group's current release track against gcloud docs; the console's "Create policy → JSON" path accepts the same document.)

The callable protocol maps `HttpsError` codes to HTTP statuses (`invalid-argument` → 400, `unauthenticated` → 401, `permission-denied` → 403, `not-found` → 404, `resource-exhausted` → 429, `internal` → 500, `unavailable` → 503, …). A 5xx alert therefore catches unexpected throws and `internal`/`unavailable`, but a spike of `invalid-argument` after an iOS release (a contract break) is 4xx — add a second policy on `response_code_class="4xx"` with a higher threshold, or a log-based metric on `jsonPayload.message=~".*\\.failed$"` (below).

### 2. p95 latency over budget

Same shape with `metric.type="run.googleapis.com/request_latencies"`, `perSeriesAligner: "ALIGN_PERCENTILE_95"`, `thresholdValue` in ms per function group (e.g. 2000 for `createnote`, 60000 for `extracttext`). Group by `service_name` and use separate policies for fast and slow functions rather than one loose threshold.

### 3. Instances near `maxInstances`

`metric.type="run.googleapis.com/container/instance_count"`, `metric.labels.state="active"`, `ALIGN_MAX`, threshold = 80 % of the function's `maxInstances`. Firing means either a traffic spike or a retry storm — both need eyes. Pair with the budget alert in `cost.md`.

### Other useful policies

- **No invocations** of a schedule function in 26 h (`run.googleapis.com/request_count` `ALIGN_COUNT` < 1 over 1 day) — catches a silently deleted or failing Cloud Scheduler job.
- **Firestore document reads** > N/min (`firestore.googleapis.com/document/read_count`) — a listener bug on iOS or a trigger loop shows up here first.
- **Cloud Tasks queue depth** growing (`cloudtasks.googleapis.com/queue/depth`).

## Uptime check on `/health`

```ts
export const health = onRequest({ invoker: "public", maxInstances: 2, memory: "128MiB", timeoutSeconds: 10 }, async (_req, res) => {
  // cheap: no Firestore, no auth. Optionally one tiny read to prove the DB path, cached for 60 s.
  res.set("Cache-Control", "no-store").status(200).json({ ok: true, revision: process.env.K_REVISION ?? "local" });
});
```

```bash
gcloud monitoring uptime create "functions health (prod)" --project snaptool-prod \
  --resource-type uptime-url --resource-labels host=asia-southeast1-snaptool-prod.cloudfunctions.net,project_id=snaptool-prod \
  --path /health --port 443 --protocol https --period 5 --timeout 10
```

(Flag names: verify against gcloud docs; the console equivalent is Monitoring → Uptime checks → Create.) Attach an alerting policy on `monitoring.googleapis.com/uptime_check/check_passed` failing from ≥ 2 regions. A public `/health` is the one `invoker: "public"` endpoint in the project; it must not touch user data or secrets.

## Log-based metrics

Turn a structured event into a metric you can chart and alert on:

```bash
gcloud logging metrics create ocr_failed --project snaptool-prod \
  --description "extractText.failed events" \
  --log-filter 'resource.type="cloud_run_revision" AND jsonPayload.message="extractText.failed"'

# distribution metric from a numeric field (e.g. Gemini tokens per call)
gcloud logging metrics create gemini_output_tokens --project snaptool-prod \
  --log-filter 'jsonPayload.message="gemini.usage"' \
  --value-extractor 'EXTRACT(jsonPayload.outputTokens)' \
  --bucket-name gemini_output_tokens --bucket-options-type exponential ...   # verify exact flags against gcloud docs; the console form is simpler
```

Metric type becomes `logging.googleapis.com/user/ocr_failed`. Alert on `ALIGN_RATE` > threshold. Log-based metrics are free up to the standard Monitoring allotment; charges apply beyond it — keep the count small.

## Dashboard

One Cloud Monitoring dashboard per environment with: request count by service, 5xx ratio, p50/p95 latency by service, active instances, Firestore reads/writes, Cloud Tasks depth, budget spend-to-date. Export it as JSON into `Server/monitoring/dashboard.json` and create it with `gcloud monitoring dashboards create --config-from-file` so staging and prod stay identical.

## What to look at after every prod deploy

1. Error Reporting → "new in the last hour" filtered by the new revision.
2. Logs Explorer: `severity>=ERROR` for 15 minutes.
3. The latency and instance charts for the changed functions.
4. `/health` uptime check green.
5. If anything moved, `rollback-and-incidents.md`.

## Does not exist / common mistakes

- `resource.type="cloud_function"` for a v2 function's request logs — v2 logs live under `cloud_run_revision`; the `cloud_function` resource carries only some system events. Query both when unsure.
- `firebase functions:log --function name` — the flag is `--only`.
- `logger.error(err)` with only an Error and no message — works, but the group name becomes the error message; use `logger.error("event.failed", { err })`.
- Alerting on `execution_count` with `status!="ok"` from the v1 metric set for a v2 function — use the Cloud Run metrics.
- A `/health` that reads the caller's Firestore doc or calls Gemini — it is public and unauthenticated; it will be scraped.
- Sending `logger.debug` with full prompts and Gemini responses in prod — PII in logs and 10× log volume. Log token counts, not content.
- Assuming an `HttpsError` shows in Error Reporting — it does not; it is a handled response.
