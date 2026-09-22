#!/usr/bin/env node
/**
 * Merge the v2 parameters INTO the live Remote Config template without
 * touching anything the v1 app still reads.
 *
 *   firebase remoteconfig:get -o remote-config/current.json -P prod
 *   node remote-config/merge.mjs remote-config/current.json > remote-config/merged.json
 *   # review the diff, then:
 *   firebase deploy --only remoteconfig -P prod   # after copying merged.json → remoteconfig.template.json
 *
 * v2 keys added/overwritten: ads_config, ad_units, min_client_version.
 * Every other parameter is passed through unchanged. Existing v1 ad_unit_*
 * values are folded into ad_units so the real ids are not lost.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const currentPath = process.argv[2];
if (!currentPath) { console.error("usage: merge.mjs <current.json>"); process.exit(2); }

const current = JSON.parse(readFileSync(currentPath, "utf8"));
const adsDefaults = JSON.parse(readFileSync(join(here, "ads_config.defaults.json"), "utf8"));
const unitDefaults = JSON.parse(readFileSync(join(here, "ad_units.defaults.json"), "utf8"));
delete unitDefaults._comment;

const params = current.parameters ?? {};
const str = (o) => JSON.stringify(o);
const v1Value = (key) => {
  const raw = params[key]?.defaultValue?.value;
  if (!raw) return null;
  try { const j = JSON.parse(raw); return { android: j.Android ?? "", ios: j.iOS ?? "" }; } catch { return null; }
};

// Fold the live v1 ids in where they exist; keep test ids where they don't.
const adUnits = { ...unitDefaults };
const v1Map = {
  banner: "ad_unit_banner",
  interstitial: "ad_unit_interstitial_pre_summary",
  rewarded: "ad_unit_rewarded",
  appOpen: "ad_unit_open_app",
};
for (const [k, v1Key] of Object.entries(v1Map)) {
  const v = v1Value(v1Key);
  if (v && (v.android || v.ios)) adUnits[k] = { android: v.android || adUnits[k].android, ios: v.ios || adUnits[k].ios };
}
// v1 used four interstitial units; v2 uses one unit + placements. Keep the others reachable for a while.
for (const k of ["ad_unit_interstitial_after_share", "ad_unit_interstitial_settings_exit", "ad_unit_interstitial_summary_exit"]) {
  const v = v1Value(k);
  if (v) adUnits[`legacy_${k}`] = v;
}

const merged = {
  ...current,
  parameters: {
    ...params,
    ads_config: { defaultValue: { value: str(adsDefaults) }, valueType: "JSON", description: "v2 ads policy. One JSON; a domain that fails to parse keeps its own defaults. enabled=false is the safe side." },
    ad_units: { defaultValue: { value: str(adUnits) }, valueType: "JSON", description: "v2 ad unit ids per format and platform." },
    min_client_version: { defaultValue: { value: params.min_client_version?.defaultValue?.value ?? "2.0.0" }, valueType: "STRING", description: "Informational only — the enforced gate is the server's MIN_CLIENT_VERSION param." },
  },
};
process.stdout.write(JSON.stringify(merged, null, 2) + "\n");
console.error(`merged: ${Object.keys(params).length} existing params kept, ads_config + ad_units + min_client_version set`);
