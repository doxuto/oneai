# Measuring ads

The AdMob console sees every impression and every cent. It **cannot** see a request the app
decided not to make — and that's the number that separates "this market has no fill" from "our
thresholds are too tight". From outside, a placement that shows nothing looks the same whether
the reason is the daily cap, the 180 s spacing, a paid user, or no bidder.

So record two streams:

| Record | Source |
|---|---|
| `AdImpression` — format, placement, value (micros), currency, precision, adapter/fill source | `paidEventHandler` on every loaded ad, all formats |
| `AdEvent` — `filled`, `noFill`, `notReady`, `shown`, `dismissed`, `rewardEarned`, **`refused(reason)`** | `AdGate.Refusal` from the lifecycle reducer + load/present results in the live client |

Nothing in either identifies the user: a placement, a number, a currency, a reason.

## Where to send it

Start with **unified log only** (`Logger(subsystem:category: "ads")`) — readable in Console.app
or a sysdiagnose on a real device. Sending it to an analytics backend means collecting behavioral
data from every user; that's a privacy-label and privacy-policy decision for the owner, not a
code decision. Keep the sink behind one file (`AdAnalytics+Live.swift`) so pointing it at Firebase
Analytics later is a one-file change plus a label update.

## Reading the numbers when tuning

1. Refusals dominated by one reason → that threshold is the bottleneck; loosen it via a console
   condition for a % of users.
2. Few refusals but many `noFill` → market/fill issue; thresholds won't help (consider mediation
   or accept it).
3. Impressions fine but uninstalls up → tighten App Open first, then interstitial.
4. Never judge a change in less than a week of data; weekday patterns are strong.
