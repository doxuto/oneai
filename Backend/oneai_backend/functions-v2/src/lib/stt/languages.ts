/**
 * ISO-639-3 codes ElevenLabs Scribe accepts for `language_code`. The app's
 * Language enum already sends these codes; "auto" (or v1's "auto-detect")
 * means omit the field and let the model detect.
 *
 * One copy. v1 duplicated a 90-entry map in two files.
 */
export const STT_LANGUAGES: ReadonlySet<string> = new Set([
  "afr","amh","ara","asm","aze","bak","bel","bul","ben","bod","bos","cat","ceb","ces","chv","cym",
  "dan","deu","div","ell","eng","epo","spa","est","eus","fas","fin","fil","fra","fry","gle","glg",
  "guj","hau","heb","hin","hrv","hun","hye","ind","isl","ita","jpn","jav","kat","kaz","khm","kan",
  "kor","kur","kir","lao","lit","lav","mkd","mal","mon","mar","msa","mya","nep","nld","nor","pan",
  "pol","pus","por","ron","rus","san","snd","sin","slk","slv","som","sqi","srp","sun","swe","swa",
  "tam","tel","tha","tur","ukr","urd","uzb","vie","zho","zul",
]);

export const AUTO_DETECT = "auto";

/** Normalise whatever the client sent to a Scribe code, or undefined for auto. */
export function sttLanguageCode(input: string | undefined): string | undefined {
  if (!input) return undefined;
  const v = input.trim().toLowerCase();
  if (v === AUTO_DETECT || v === "auto-detect" || v === "") return undefined;
  // Accept "en-US" / "vi" style too, mapping the common BCP-47 prefixes.
  const bcp: Record<string, string> = {
    en: "eng", vi: "vie", es: "spa", fr: "fra", de: "deu", ja: "jpn", ko: "kor", zh: "zho",
    pt: "por", it: "ita", ru: "rus", th: "tha", id: "ind", ms: "msa", hi: "hin", ar: "ara",
    nl: "nld", tr: "tur", pl: "pol", uk: "ukr", sv: "swe", da: "dan", fi: "fin", nb: "nor", no: "nor",
  };
  const prefix = v.split(/[-_]/)[0] ?? v;
  const mapped = STT_LANGUAGES.has(v) ? v : bcp[prefix];
  return mapped && STT_LANGUAGES.has(mapped) ? mapped : undefined;
}
