# Rewarded ads with server-side verification

**The client never credits a reward.** An app that accepts "I just watched an ad, give me more"
accepts it from anyone. If the reward has real cost (AI calls, currency, content), the only thing
allowed to credit it is Google calling your server with a signature over what it claims.

## Flow

1. User taps "Watch an ad for N more …". Gate: `AdGate.rewarded` (master, entitlement, enabled,
   daily cap).
2. Right before `present`, set on the loaded ad:
   `ad.serverSideVerificationOptions = { userIdentifier = <auth uid>, customRewardString = <optional context> }`.
3. User watches. SDK fires `userDidEarnReward` → **only** show "Reward on its way…".
4. Google sends `GET <your callback URL>?ad_network=…&ad_unit=…&custom_data=…&key_id=…&reward_amount=…&reward_item=…&timestamp=…&transaction_id=…&user_id=…&signature=…`.
5. Server (`templates/server/adReward.ts`):
   - Fetch Google's verifier keys (`https://www.gstatic.com/admob/reward/verifier-keys.json`,
     cache ~24 h, refetch on unknown `key_id`).
   - Verify ECDSA-SHA256 over the **raw query string up to `&signature=`** (cut the string; do
     not parse and re-serialize — re-encoding `%2F` → `/` breaks valid signatures).
     Signature is URL-safe base64, DER-encoded.
   - In one Firestore transaction: create `adRewards/{transaction_id}` (fail if exists → return
     200, already processed), then apply the grant to the user's current quota period.
   - Clamp the amount server-side regardless of what the console says.
   - Return **500 when keys can't be loaded** so Google retries. Returning 200 on an internal
     failure silently swallows the reward.
6. App, after dismissal, **re-reads** the quota a few times with backoff (e.g. 1 s, 2 s, 4 s, 8 s)
   because Google's callback usually lands after the ad closes. Or listen to the document.

## Grant semantics worth copying

- Store the grant on the **current quota period document** so it expires with the period (new
  day ⇒ gone) — no cleanup job needed.
- Grant **raises the ceiling**, it doesn't lower usage: 3/5 used + reward 2 ⇒ 3/7, not 1/5.
- Keep `adRewards/{transaction_id}` with an `expiresAt` field and a Firestore TTL policy.

## Console setup (tell the user; can't be done from code)

- Enable **Server-side verification** on the rewarded unit with the deployed function URL.
- Set reward amount/item in the unit settings.
- The callback function must be public (no Firebase auth — Google has none). Security is the
  signature check.
- Without SSV enabled, nothing gets credited — that's the correct failure mode.

## Tests the server must have

- Valid signature with `%2F` in `custom_data` verifies.
- Tampered `reward_amount` fails.
- Same `transaction_id` twice grants once.
- Key fetch failure returns 500.
- Missing `user_id` returns 400 and grants nothing.
