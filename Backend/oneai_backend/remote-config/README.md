# Remote Config

`ads_config.defaults.json` — chính sách quảng cáo v2, một key JSON (`docs/08-ADS-FLOW.md` §3).
`enabled: false` là mặc định an toàn: build không fetch được config thì **không hiện ad nào**.

`ad_units.defaults.json` — id TEST công khai của Google. App dùng chúng ở debug build và
khi thiếu key, nên dev không bao giờ click phải ad thật.

## Đưa lên Firebase — KHÔNG deploy thẳng

`firebase deploy --only remoteconfig` thay **toàn bộ** template. App v1 đang chạy đọc 21
key phẳng (`ad_unit_*`, `ad_*_enabled`, `popup_intro_basic_*`…); mất chúng là ad của bản
đang phát hành tắt ngay. Vì thế:

```bash
cd Backend/oneai_backend
firebase remoteconfig:get -o remote-config/current.json -P prod
node remote-config/merge.mjs remote-config/current.json > remote-config/merged.json
diff <(jq -S . remote-config/current.json) <(jq -S . remote-config/merged.json)   # chỉ thấy 3 key mới
cp remote-config/merged.json remoteconfig.template.json
firebase deploy --only remoteconfig -P prod
```

`merge.mjs` giữ nguyên mọi key hiện có, gộp id thật từ `ad_unit_*` của v1 vào `ad_units`
(nếu có), và chỉ thêm `ads_config`, `ad_units`, `min_client_version`.

`current.json`, `merged.json`, `remoteconfig.template.json` đều gitignore — chúng chứa
id thật và chỉ có nghĩa với một project.
