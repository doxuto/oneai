# 08 — Ads flow v2 (AdMob, port skill iOS sang Flutter)

> ⚠️ Mã sprint (S3-05, S7-12…) trong file này là của **roadmap bản 1**.
> `09-ROADMAP.md` đã được đánh số lại cho hướng build-lại-từ-đầu.
> Tra cứu theo tên task, đừng theo mã.


Nguồn: `.claude/skills/ios-admob-ads-skill/` — chắt lọc ở `03-SKILLS-RULESET.md` §6.
Hiện trạng: `02-AUDIT-APP.md` §6.

Skill viết cho Swift. Luật (thời điểm, tần suất, consent, SSV) là **platform-neutral**
và port thẳng. Phần code (`AdGate.swift`, `AdLedger`, `NativeAdView`) phải viết
lại bằng Dart. Phần Android (app-id meta-data, test unit id, Play Data Safety)
skill không có — phải tự bổ sung.

---

## 1. Khoảng cách giữa hiện tại và chuẩn

| | Hiện tại | Chuẩn của skill |
|---|---|---|
| Gate | nằm rải trong 3 service, gọi `DateTime.now()` và `SharedPreferences` trực tiếp | một hàm **thuần**, thời gian và calendar truyền vào ⇒ test được |
| Master switch | không có | `enabled`, **mặc định `false`** |
| Consent | chỉ ATT trên iOS | **UMP** trước, ATT chỉ là bước phụ của iOS |
| Cooldown | 1 khoá `ad_fullscreen_global_freq_seconds` (120s) | cooldown toàn cục **+** spacing riêng từng format **+** cap/ngày từng format |
| Interstitial | bắn theo điều hướng, không đếm "việc đã xong" | phải sau `recordCompletion()`, tối thiểu **2** completion giữa hai lần (sàn cứng trong code) |
| App Open | bỏ qua lần mở đầu tiên | bỏ qua **3 session đầu** |
| Rewarded | client tự gọi `POST /user/reward` | **SSV** — chữ ký ECDSA, client không bao giờ tự cộng |
| Remote Config | 21 key phẳng | **một** key `ads_config` dạng JSON, default an toàn nhúng trong bundle |
| Native ads | không có | có, chèn theo thuật toán `nativeRows` |
| Test | không có | gate là hàm thuần ⇒ bắt buộc unit test |

---

## 2. Kiến trúc đích

```
lib/data/services/ads/
  ad_gate.dart          PURE. Không SDK, không DateTime.now(), không prefs.
  ad_ledger.dart        value type, JSON trong SharedPreferences
  ads_config.dart       parse ads_config từ Remote Config, có default
  ad_consent.dart       UMP (+ ATT ở iOS, sau UMP)
  ad_unit_ids.dart      resolver theo platform + debug/release
  ads_controller.dart   nơi duy nhất chạm GMA SDK; gọi gate rồi mới load/show
  native_ad_placement.dart   nativeRows / nativeChunks
```

`ad_gate.dart` không import `google_mobile_ads`. Đó là điều kiện để test nó.

### Kiểu

```dart
sealed class AdDecision { }
final class AdAllowed extends AdDecision { const AdAllowed(); }
final class AdRefused  extends AdDecision { final AdRefusal reason; const AdRefused(this.reason); }

enum AdRefusal {
  masterSwitchOff, notEntitledToAds, formatDisabled, placementDisabled,
  dailyCap, tooSoonSinceSameFormat, fullScreenCooldown,
  tooFewCompletionsSinceLast, tooFewLifetimeCompletions,
  sessionTooYoung, earlySession, backgroundTooShort,
}

class AdContext {
  final AdLedger ledger;
  final bool adsEntitled;     // true = user NÀY nên thấy quảng cáo
  final DateTime now;
}
```

### Ledger

```dart
class AdLedger {
  int sessionCount = 0;
  DateTime? sessionStartedAt;
  int lifetimeCompletions = 0;
  int completionsSinceInterstitial = 0;
  Map<AdFormat, DateTime> lastShownAt = {};
  DateTime? lastFullScreenDismissedAt;
  String dayKey = '';                      // "yyyy-MM-dd"
  Map<AdFormat, int> shownToday = {};
}
```

- `recordSessionStart(at:)` → `sessionCount++`, set `sessionStartedAt`.
- `recordCompletion()` → tăng cả `lifetimeCompletions` và `completionsSinceInterstitial`.
- `recordShown(format, at:)` → normalize ngày, `shownToday[format]++`,
  set `lastShownAt`, **và reset `completionsSinceInterstitial = 0` nếu format là interstitial**.
- `recordFullScreenDismissed(at:)` → đây mới là lúc cooldown bắt đầu tính.
- Persist sau **mỗi** lần mutate.

### Chuỗi kiểm tra — đúng thứ tự

`common` (luôn chạy trước): `!config.enabled` → `masterSwitchOff`;
`!adsEntitled` → `notEntitledToAds`.

**appOpen(secondsInBackground)**
1. `common`
2. `!rules.enabled` → `formatDisabled`
3. `ledger.sessionCount > skipFirstSessions` (**lớn hơn hẳn** — với `3`, session thứ 4 là lần đầu đủ điều kiện) else `earlySession`
4. `secondsInBackground >= minimumBackgroundSeconds` else `backgroundTooShort`
5. cooldown toàn cục → `fullScreenCooldown`
6. spacing appOpen → `tooSoonSinceSameFormat`
7. cap/ngày → `dailyCap`
8. `allow`

**interstitial** — gọi ở khoảnh khắc "xong việc", **sau** `recordCompletion()`
1. `common`
2. `!rules.enabled` → `formatDisabled`
3. `lifetimeCompletions >= minimumLifetimeCompletions` else `tooFewLifetimeCompletions`
4. `between = max(2, minimumCompletionsBetween)` — **sàn 2 là chính sách AdMob, hard-code trong code chứ không để config**. Nếu đã từng show interstitial và `completionsSinceInterstitial < between` → `tooFewCompletionsSinceLast`
5. `now - sessionStartedAt >= minimumSessionSeconds` else `sessionTooYoung`
6. cooldown toàn cục
7. spacing interstitial
8. cap/ngày
9. `allow`

**rewarded** — ngắn nhất vì user chủ động
1. `common` 2. `!enabled` → `formatDisabled` 3. cap/ngày 4. `allow`
Không cooldown, không spacing, không luật session.

**banner / native** — không ledger, không thời gian
1. `!config.enabled` 2. `!adsEntitled` 3. `!format.enabled` 4. `!placements.contains(placement)` 5. `allow`

### Hợp đồng gate ↔ SDK

- Gate cho phép nhưng **chưa có ad nào load sẵn** → **không hiện gì**, ghi
  `noFill`/`notReady`. **Tuyệt đối không chờ load tại thời điểm trigger.**
  (Hiện tại app đang chờ load với timeout 5s và hiện dialog chặn — phải bỏ.)
- Ghi `shown` chỉ khi SDK báo ad đã thực sự hiện (`onAdShowedFullScreenContent`),
  ghi `dismissed` khi đóng — cooldown bắt đầu từ đó.

### Chèn native vào danh sách

```dart
List<int> nativeRows(int itemCount, NativeConfig c) {
  final first = math.max(1, c.firstRow) - 1;
  final every = math.max(1, c.everyRows);
  if (c.maxPerScreen <= 0 || first < 0) return const [];
  final rows = <int>[];
  var i = first;
  while (i < itemCount && rows.length < c.maxPerScreen) { rows.add(i); i += every; }
  return rows;
}
```

`i < itemCount` ⇒ luôn còn ít nhất một item sau quảng cáo; list ngắn thì không
có ad nào và ad không bao giờ đứng cuối. `nativeChunks` phải **dẫn xuất từ**
`nativeRows`, và có test khẳng định hai cái khớp nhau.

---

## 3. Remote Config: một key `ads_config`

Thay 21 key phẳng hiện tại bằng **một** parameter JSON. Domain nào parse lỗi thì
giữ default của chính nó, không ảnh hưởng domain khác. Default nhúng trong
bundle qua `setDefaults`.

> *"Defaults are always the safe side: ads off, wide spacing, low caps. A build
> that can't reach Remote Config must behave like the mildest build, not the
> most aggressive."*

```jsonc
{
  "enabled": false,
  "fullScreenCooldownSeconds": 30,
  "appOpen":      { "enabled": true, "minimumBackgroundSeconds": 45,
                    "minimumSecondsBetween": 300, "maxPerDay": 4, "skipFirstSessions": 3 },
  "interstitial": { "enabled": true, "minimumSecondsBetween": 180,
                    "minimumCompletionsBetween": 2, "minimumLifetimeCompletions": 3,
                    "minimumSessionSeconds": 30, "maxPerDay": 8,
                    "placements": ["summaryEnter", "summaryExit", "afterShare", "settingsExit"] },
  "rewarded":     { "enabled": true, "maxPerDay": 5 },
  "banner":       { "enabled": true, "placements": ["summaryTab"] },
  "native":       { "enabled": false, "firstRow": 6, "everyRows": 10,
                    "maxPerScreen": 3, "placements": ["minutesList"] }
}
```

Ad unit id giữ nguyên cơ chế hiện tại (`{"Android": "...", "iOS": "..."}`) nhưng
gom vào `ad_units` và **bổ sung tầng debug** dùng test unit id của Google, để
không bao giờ có chuyện dev tự click ad thật (lý do phổ biến nhất khiến tài
khoản AdMob bị limit).

`ad_toast_freq_limit_message` và nhóm `popup_intro_basic_*` giữ nguyên.

---

## 4. UMP consent (thay cho "chỉ ATT")

Thứ tự bắt buộc:

1. `enabled == false` → **không khởi động GMA SDK, không hỏi consent gì cả.**
2. `ConsentInformation.requestConsentInfoUpdate` với `TagForUnderAgeOfConsent(false)`.
3. Nếu form khả dụng → `loadAndShowConsentFormIfRequired`.
4. Chỉ khi `canRequestAds == true` mới `MobileAds.instance.initialize()`.
5. **iOS, sau UMP:** `AppTrackingTransparency.requestTrackingAuthorization()`.
   ATT không thay được UMP — UMP là cơ sở pháp lý (GDPR/ePrivacy), ATT là yêu
   cầu của Apple. Từ chối ATT ⇒ vẫn chạy ad, chỉ là non-personalized.
6. Settings phải có mục "Privacy options" gọi `showPrivacyOptionsForm` khi
   `privacyOptionsRequirementStatus == required`.

Hiện tại app gọi ATT **từ cả hai nút** của popup intro (kể cả "Cancel") — sai
thứ tự và sai ngữ cảnh. Phải bỏ.

**Android bổ sung** (skill không có): `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID">`
trong Manifest, test unit id riêng, khai báo Play Data Safety.

---

## 5. Rewarded SSV — client không bao giờ tự cộng credit

> *"The client never credits a reward. An app that accepts 'I just watched an
> ad, give me more' accepts it from anyone."*

Đây chính là lỗ hổng của v1: `POST /user/reward {rewardAmount}` nhận số bất kỳ
từ client, cộng bằng read-modify-write. Ai có ID token là tự nâng credit vô hạn.

### Luồng

1. User bấm "Watch ad & earn credit" → `AdGate.rewarded`.
2. Ngay trước `show()`, set trên ad đã load:
   `serverSideVerificationOptions = ServerSideVerificationOptions(userId: <auth uid>, customData: <ngữ cảnh>)`.
3. `onUserEarnedReward` → **chỉ** hiện "Reward on its way…". Không gọi API.
4. Google GET tới `adRewardSsv` với query có `signature` và `key_id`.
5. Server verify + cộng vào `users/{uid}/quota/{period}.rewardBonus`.
6. App sau khi ad đóng, **đọc lại quota với backoff 1s → 2s → 4s → 8s**, hoặc
   đơn giản hơn: đã có Firestore listener trên quota thì UI tự cập nhật.

### Server (`functions-v2/src/ads/adRewardSsv.ts`, `onRequest`)

| Điểm | Yêu cầu |
|---|---|
| Keys | `https://www.gstatic.com/admob/reward/verifier-keys.json`, cache 24h, **`key_id` lạ thì fetch lại một lần** (xoay khoá) |
| Tách chữ ký | cắt **chuỗi thô** `req.originalUrl` tại đúng `"&signature="`. **Không** parse rồi encode lại — `%2F` → `/` là đổi bytes Google đã ký |
| Verify | base64 URL-safe → chuẩn (`-`→`+`, `_`→`/`) + padding, rồi `crypto.verify("sha256", msg, {key, dsaEncoding: "der"}, sig)` |
| Query rỗng | trả **200 "ok"** — nút "Verify URL" của AdMob console gửi request rỗng |
| Thiếu `user_id` / query hỏng | **400**, không cộng gì |
| Không lấy được keys | **500** để Google retry. Trả 200 là nuốt mất phần thưởng |
| Chữ ký sai | **403** + `logger.warn` kèm transaction id |
| Thành công / đã xử lý rồi | **200** |
| Grant lỗi | **500** |
| Clamp | `max(0, min(MAX_GRANT=5, floor(rewardAmount)))` — chặn ở server bất kể console khai gì |
| Idempotency | **một** transaction: đọc `adRewards/{transaction_id}`; có rồi → return false (vẫn 200); chưa → `applyGrant` rồi `tx.create(txRef, {uid, amount, adUnit, at, expiresAt: now+30d})` |
| Grant | **nâng trần**, không giảm usage: 3/5 + thưởng 2 = **3/7** |
| Region | `asia-southeast1` (cùng Firestore vì có transaction), rồi đăng ký lại URL trong console |
| Log | **không bao giờ** log query string |

### Test bắt buộc (vitest)

1. Chữ ký hợp lệ, `custom_data` có `%2F` → verify pass.
2. Sửa `reward_amount` → verify fail, không cộng.
3. Cùng `transaction_id` hai lần → chỉ cộng một lần, cả hai trả 200.
4. Fetch keys lỗi → 500.
5. Thiếu `user_id` → 400, không cộng.

### Việc trên AdMob console (không làm bằng code)

Bật Server-side verification trên rewarded unit, dán URL function đã deploy,
đặt reward amount/item. **Không bật SSV thì không ai được cộng gì** — và đó là
kiểu hỏng đúng.

---

## 6. Vị trí đặt quảng cáo — giữ nguyên, đổi cơ chế

| Vị trí | Format | Trước | Sau |
|---|---|---|---|
| Cold start | App Open | bỏ qua lần mở đầu | bỏ qua 3 session đầu; **không chặn first paint** |
| Warm start | App Open | nền ≥30 phút | nền ≥45s + spacing 300s + cap 4/ngày |
| Tap note card | Interstitial | mỗi lần tap | sau `recordCompletion`, ≥2 completion giữa hai lần |
| Thoát summary | Interstitial | trừ nhánh có dialog | qua gate; sửa luôn nhánh bị bỏ sót |
| Sau khi share | Interstitial | luôn | qua gate — share là "completion" đúng nghĩa |
| Thoát settings | Interstitial | luôn | qua gate |
| Hết credit khi transcribe | Rewarded | client tự cộng | SSV |
| Đang chờ xử lý | Rewarded | client tự cộng | SSV |
| Đầu mỗi tab summary | Banner | 1 instance dùng chung 3 tab | giữ; thêm refresh dùng `ad_banner_refresh_rate_seconds` (key đang có mà không ai đọc) |
| Danh sách note | **Native** (mới) | — | `firstRow 6, everyRows 10, maxPerScreen 3`, mặc định tắt |

**Bỏ:** dialog `CircularProgressIndicator` chặn màn hình trong lúc chờ load ad.
Skill nói rõ: không có ad sẵn thì không hiện gì.

---

## 7. Luật chính sách phải giữ

- Không đặt ad ở nơi dễ chạm nhầm với nút thật; giữ khoảng cách an toàn.
- Không quảng cáo trên màn hình đang tải hoặc chuyển tiếp.
- Không bao giờ dùng ad unit thật trong debug build — dùng test unit id.
- Không gửi PII (uid, email, nội dung note) vào bất kỳ tham số ad nào.
  `userIdentifier` trong SSV là ngoại lệ duy nhất và là uid, không phải email.
- Native ad phải render qua `NativeAdView` với đầy đủ asset bắt buộc và nhãn
  "Ad"/"Sponsored"; không tự vẽ lại bố cục.
- App **không** khai báo child-directed.
