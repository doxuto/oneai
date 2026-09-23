# Monitoring as code

`apply.sh` creates (idempotently) one e-mail notification channel, eight
log-based metrics keyed on the structured `message` fields the code emits, and
the alert policies in `policies/`. Run it once per project after the first
deploy:

```bash
PROJECT_ID=oneai-dev NOTIFY_EMAIL=contact@doxutostudio.top ./monitoring/apply.sh
```

| Policy | Fires when | Runbook |
|---|---|---|
| transcriptions failing | >5 permanent `pipeline.error` / 15 min | docs/15 §Sự cố |
| worker not finishing | any `job.reaped` / 15 min | worker OOM/timeout, queue backlog |
| STT vendor 5xx | >3 / 5 min | flip `STT_FALLBACK_VENDOR` / `STT_VENDOR` |
| SSV bad signatures | >10 / h | forgery probing; nothing granted |
| RevenueCat wrong secret | any / 5 min | secret drift |
| Firestore index missing | any | deploy indexes |
| FCM send failing | >3 / 15 min | APNs key |
| callable error rate | 5xx ratio >2 % / 5 min | Cloud Run metrics |
| worker p95 > 8 min | p95 latency >480 s / 15 min | vendor latency, memory |

Billing budget needs the billing account id and is printed as a manual step.
Log messages are the contract: renaming one in code means updating its filter here.
