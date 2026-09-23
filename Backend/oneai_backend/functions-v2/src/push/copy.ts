/**
 * Notification text per device locale. The server picks the language from the
 * locale the app registered with, so a Vietnamese phone gets Vietnamese even
 * when the note itself is in English.
 */
export type PushKind = "minuteReady" | "minuteFailed";

interface Copy { title: string; body: (title: string) => string }

const COPY: Record<string, Record<PushKind, Copy>> = {
  en: {
    minuteReady: { title: "Your note is ready", body: (t) => `"${t}" has been transcribed and summarised.` },
    minuteFailed: { title: "Transcription failed", body: (t) => `"${t}" could not be processed. Your minutes have been returned.` },
  },
  vi: {
    minuteReady: { title: "Ghi chú đã sẵn sàng", body: (t) => `"${t}" đã được chuyển thành văn bản và tóm tắt.` },
    minuteFailed: { title: "Xử lý không thành công", body: (t) => `"${t}" không xử lý được. Số phút của bạn đã được hoàn lại.` },
  },
  es: {
    minuteReady: { title: "Tu nota está lista", body: (t) => `"${t}" se ha transcrito y resumido.` },
    minuteFailed: { title: "La transcripción falló", body: (t) => `"${t}" no se pudo procesar. Te devolvimos los minutos.` },
  },
};

export const DEFAULT_LOCALE = "en";

/** "vi-VN" → vi, "es_419" → es, "pt" → en (unsupported → default). */
export function pickLocale(raw: string | null | undefined): string {
  const primary = (raw ?? "").toLowerCase().split(/[-_]/)[0] ?? "";
  return primary in COPY ? primary : DEFAULT_LOCALE;
}

export function notificationCopy(kind: PushKind, locale: string | null | undefined, minuteTitle: string): { title: string; body: string } {
  const c = COPY[pickLocale(locale)]![kind];
  const t = minuteTitle.trim().length > 0 ? truncate(minuteTitle.trim(), 60) : "Untitled";
  return { title: c.title, body: c.body(t) };
}

function truncate(s: string, max: number): string {
  return s.length <= max ? s : `${s.slice(0, max - 1)}…`;
}
