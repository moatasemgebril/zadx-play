/**
 * Pure helpers for parent push notifications (no Firebase imports, unit-tested with `npm test`).
 *
 * Child-safety rules (docs/PUSH_NOTIFICATIONS.md):
 *  - push goes to PARENT devices only (never to a paired child device);
 *  - payloads carry generic text and opaque ids only: no child nickname, no task title,
 *    no free text from the client. The parent app loads details after it is opened.
 */
import { isSafeId } from "./security";

/** Types a family device may ask the server to send (callable `notifyParent`). */
export const CLIENT_PUSH_TYPES = ["task_submitted", "unlock_request", "adhan"] as const;
/** Types only the server itself sends (pairing / security events, weekly summary). */
export const SERVER_PUSH_TYPES = ["device_paired", "weekly_summary"] as const;

export type ClientPushType = (typeof CLIENT_PUSH_TYPES)[number];
export type PushType = ClientPushType | (typeof SERVER_PUSH_TYPES)[number];
export type PushLang = "ar" | "en";

export function isClientPushType(value: unknown): value is ClientPushType {
  return typeof value === "string" && (CLIENT_PUSH_TYPES as readonly string[]).includes(value);
}

export function pushLang(value: unknown): PushLang {
  return value === "en" ? "en" : "ar";
}

/** Generic, fixed copy. Never interpolate child names or other client-supplied text here. */
const TEXT: Record<PushType, Record<PushLang, string>> = {
  task_submitted: {
    ar: "فيه مهمة مستنية موافقتك",
    en: "A task is waiting for your approval",
  },
  unlock_request: {
    ar: "فيه طلب فتح الألعاب مستني موافقتك",
    en: "An unlock request is waiting for your approval",
  },
  adhan: {
    ar: "وقت الصلاة — لو ابنك بيلعب على البلايستيشن أو الإكس بوكس، اقفله من التطبيق الرسمي",
    en: "Prayer time — pause PlayStation or Xbox from the official app if your child is playing",
  },
  device_paired: {
    ar: "تم ربط جهاز جديد بعائلتك. لو مش إنت، افتح التطبيق وراجع الأجهزة",
    en: "A new device was linked to your family. If this wasn't you, open the app and review devices",
  },
  weekly_summary: {
    ar: "ملخص الأسبوع جاهز — افتح التطبيق وشوف التقدّم",
    en: "Your weekly summary is ready — open the app to see progress",
  },
};

export function pushText(type: PushType, lang: PushLang): { title: string; body: string } {
  return { title: "Zad X", body: TEXT[type][lang] };
}

const PRAYERS = ["fajr", "dhuhr", "asr", "maghrib", "isha"];
const PAIR_TARGETS = ["phone", "windows"];

/** Data keys each type may carry; every value must be an opaque id or a fixed enum value. */
const DATA_KEYS: Record<PushType, Record<string, (v: string) => boolean>> = {
  task_submitted: { taskId: (v) => isSafeId(v) && v.length <= 64 },
  unlock_request: { taskId: (v) => isSafeId(v) && v.length <= 64, prayer: (v) => PRAYERS.includes(v) },
  adhan: { prayer: (v) => PRAYERS.includes(v) },
  device_paired: { target: (v) => PAIR_TARGETS.includes(v) },
  weekly_summary: {},
};

/**
 * FCM `data` (string → string). Only allow-listed keys with id/enum values survive, so no
 * free text (names, titles, messages) can reach a notification payload.
 */
export function buildPushData(type: PushType, childId: string | null, raw: unknown): Record<string, string> {
  const out: Record<string, string> = { type };
  if (childId !== null && isSafeId(childId) && childId.length <= 40) out.childId = childId;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  const allowed = DATA_KEYS[type];
  for (const [key, check] of Object.entries(allowed)) {
    const v = (raw as Record<string, unknown>)[key];
    if (typeof v === "string" && check(v)) out[key] = v;
  }
  return out;
}

/** FCM registration tokens: ~150–300 chars of [A-Za-z0-9_:-]. Bounded to keep docs small. */
export function isFcmToken(value: unknown): value is string {
  return typeof value === "string" && value.length >= 20 && value.length <= 4096 && /^[A-Za-z0-9_:.-]+$/.test(value);
}

/** Admin SDK error codes meaning the token will never work again: delete it. */
export const STALE_TOKEN_ERRORS: readonly string[] = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
];

export function isStaleTokenError(code: unknown): boolean {
  return typeof code === "string" && STALE_TOKEN_ERRORS.includes(code);
}

/** Family settings switches (families/{id}.settings), synced from the parent settings screen. */
export function pushAllowedBySettings(type: PushType, settings: unknown): boolean {
  const s = settings && typeof settings === "object" ? (settings as Record<string, unknown>) : {};
  if (type === "task_submitted" || type === "unlock_request") return s.notifyOnTasks !== false;
  if (type === "adhan") return s.notifyOnAdhan !== false;
  return true; // pairing/security events and the weekly summary: device opt-in is enough
}

/** Per family + type limits (in addition to the per-caller limit on `notifyParent`). */
export const PUSH_RATE_LIMITS: Record<PushType, { limit: number; windowMs: number }> = {
  task_submitted: { limit: 30, windowMs: 60 * 60_000 },
  unlock_request: { limit: 10, windowMs: 60 * 60_000 },
  adhan: { limit: 6, windowMs: 24 * 60 * 60_000 },
  device_paired: { limit: 10, windowMs: 60 * 60_000 },
  weekly_summary: { limit: 1, windowMs: 6 * 24 * 60 * 60_000 },
};

export const MAX_PARENT_DEVICES = 10;

export interface ParentDeviceDoc {
  id: string; // = owner uid
  token?: unknown;
  lang?: unknown;
}

export interface Recipient {
  uid: string;
  token: string;
  lang: PushLang;
}

/**
 * Picks the tokens to send to: the device must still be a family member, must NOT be a
 * paired child device, must have a well-formed token, and is not the caller's own device.
 * Duplicate tokens are dropped and the list is capped.
 */
export function selectRecipients(
  devices: ParentDeviceDoc[],
  members: unknown,
  childDevices: unknown,
  excludeUid: string | null = null,
  max = MAX_PARENT_DEVICES,
): Recipient[] {
  const memberSet = new Set(Array.isArray(members) ? members.filter((m): m is string => typeof m === "string") : []);
  const children = childDevices && typeof childDevices === "object" ? (childDevices as Record<string, unknown>) : {};
  const seen = new Set<string>();
  const out: Recipient[] = [];
  for (const d of devices) {
    if (out.length >= max) break;
    if (!isSafeId(d.id) || d.id === excludeUid || !memberSet.has(d.id)) continue;
    if (Object.prototype.hasOwnProperty.call(children, d.id)) continue; // child device: never
    if (!isFcmToken(d.token) || seen.has(d.token)) continue;
    seen.add(d.token);
    out.push({ uid: d.id, token: d.token, lang: pushLang(d.lang) });
  }
  return out;
}
