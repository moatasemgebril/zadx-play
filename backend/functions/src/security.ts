/**
 * Pure security helpers (no Firebase imports) so they can be unit-tested with `npm test`.
 */
import { createHash, timingSafeEqual } from "crypto";

/** Firestore auto-ids and our own ids: letters, digits, '-' and '_', no '/'. */
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

export function isSafeId(value: unknown): value is string {
  return typeof value === "string" && ID_RE.test(value);
}

/** Pairing codes are exactly 6 digits. */
export function isPairingCode(value: unknown): value is string {
  return typeof value === "string" && /^[0-9]{6}$/.test(value);
}

/** Referral codes look like ZADX-AB23 (see createUniqueCode). */
export function normaliseReferralCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim().toUpperCase();
  return /^ZADX-[A-HJ-NP-Z2-9]{4}$/.test(code) ? code : null;
}

export function sha256Hex(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

/** Constant-time comparison of two hex digests (false on any length/format mismatch). */
export function hexDigestEquals(expectedHex: unknown, actualHex: string): boolean {
  if (typeof expectedHex !== "string" || !/^[0-9a-f]+$/i.test(expectedHex)) return false;
  const expected = Buffer.from(expectedHex, "hex");
  const actual = Buffer.from(actualHex, "hex");
  return expected.length === actual.length && expected.length > 0 && timingSafeEqual(expected, actual);
}

// ---------------------------------------------------------------------------
// Fixed-window rate limiting (state is stored in Firestore by the caller)
// ---------------------------------------------------------------------------

export interface WindowState {
  windowStart: number;
  count: number;
}

export interface RateDecision {
  allowed: boolean;
  next: WindowState;
  retryAfterMs: number;
}

export function rateLimitDecision(
  prev: Partial<WindowState> | undefined,
  now: number,
  limit: number,
  windowMs: number,
): RateDecision {
  const start = typeof prev?.windowStart === "number" ? prev.windowStart : 0;
  const count = typeof prev?.count === "number" ? prev.count : 0;
  if (now - start >= windowMs || start > now) {
    return { allowed: limit > 0, next: { windowStart: now, count: 1 }, retryAfterMs: 0 };
  }
  if (count >= limit) {
    return { allowed: false, next: { windowStart: start, count }, retryAfterMs: start + windowMs - now };
  }
  return { allowed: true, next: { windowStart: start, count: count + 1 }, retryAfterMs: 0 };
}

/** Rate-limit doc id: hashed so no uid / IP address is stored in clear text. */
export function rateLimitKey(bucket: string, subject: string): string {
  return `${bucket}_${sha256Hex(`${bucket}:${subject}`).slice(0, 40)}`;
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

/**
 * Feature matrix, mirrored from lib/data/models/plan.dart (`AppFeature`,
 * `freeFeatures`, `basicFeatures`, `plusFeatures`). Keep the names identical:
 * test/plan_matrix_test.dart in the app compares both lists.
 * Free = no plan (or an expired one).
 */
export const PLAN_FEATURES = {
  free: ["appLock", "prayerTimes", "adhan", "quran", "adhkar"],
  basic: [
    "appLock", "prayerTimes", "adhan", "quran", "adhkar",
    "tasksRewards", "games", "eduGames", "exercises", "customUnlockTasks", "multipleChildren", "assistant",
  ],
  plus: [
    "appLock", "prayerTimes", "adhan", "quran", "adhkar",
    "tasksRewards", "games", "eduGames", "exercises", "customUnlockTasks", "multipleChildren", "assistant",
    "consoleLinks", "unlimitedAssistant", "weeklyReport",
  ],
} as const;

export type PlanFeature = (typeof PLAN_FEATURES)["plus"][number];

/** True when the family's plan in force at [now] includes [feature]. Free features are always allowed. */
export function planAllows(plan: unknown, planExpiresAt: unknown, now: number, feature: PlanFeature): boolean {
  if ((PLAN_FEATURES.free as readonly string[]).includes(feature)) return true;
  if (!hasActivePlan(plan, planExpiresAt, now)) return false;
  return (PLAN_FEATURES[plan as "basic" | "plus"] as readonly string[]).includes(feature);
}

/** True when the family has a paid or trial plan that has not expired. */
export function hasActivePlan(plan: unknown, planExpiresAt: unknown, now: number): boolean {
  if (plan !== "basic" && plan !== "plus") return false;
  if (typeof planExpiresAt !== "string") return false;
  const t = Date.parse(planExpiresAt);
  return Number.isFinite(t) && t > now;
}

// ---------------------------------------------------------------------------
// Free plan = one child (owner decision 2026-11-21, docs/decisions/FREE-ONE-CHILD.md)
// ---------------------------------------------------------------------------

export const DEFAULT_CHILD_ID = "child-1";
export const FAMILY_TRIAL_MS = 7 * 24 * 60 * 60_000;
const CHILD_ID_PATTERN = /^[A-Za-z0-9_-]{1,40}$/;

/** The child that stays active on Free: the parent's choice (`setFreeChild`) or `child-1`. */
export function freeChildIdOf(freeChildId: unknown): string {
  return typeof freeChildId === "string" && CHILD_ID_PATTERN.test(freeChildId) ? freeChildId : DEFAULT_CHILD_ID;
}

/** True during the first 7 days after the family was created (server time, like the app's trial). */
export function familyTrialActive(createdAtMs: unknown, now: number): boolean {
  return typeof createdAtMs === "number" && Number.isFinite(createdAtMs) && now < createdAtMs + FAMILY_TRIAL_MS;
}

/**
 * True when [childId] is paused: the family has no active paid plan, is past its first 7 days,
 * and the child is not the one kept active on Free. Paused children keep all their data; they
 * are only not locked, monitored or paired as separate children. Same rule as
 * `FamilyPlanStatus.childPaused` in lib/services/family/child_pause.dart.
 */
export function childPaused(input: {
  plan: unknown; planExpiresAt: unknown; createdAtMs: unknown; freeChildId: unknown; childId: string; now: number;
}): boolean {
  if (hasActivePlan(input.plan, input.planExpiresAt, input.now)) return false;
  if (familyTrialActive(input.createdAtMs, input.now)) return false;
  return input.childId !== freeChildIdOf(input.freeChildId);
}

/**
 * `redeemPairingCode`: why a valid code must be refused before it is burned, or null.
 * A child paused on the Free plan gets no new device (same as `createPairingCode`).
 * A missing family keeps the old behaviour (null): the redeem then fails on its own.
 */
export function pairingRedeemRefusal(familyExists: boolean, paused: boolean): "child_paused" | null {
  return familyExists && paused ? "child_paused" : null;
}

// ---------------------------------------------------------------------------
// AI assistant input
// ---------------------------------------------------------------------------

export interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

/**
 * Keeps only well-formed turns, truncates each, bounds the total size and makes the
 * list start with a user turn and alternate roles (what the Messages API expects).
 */
export function sanitiseHistory(raw: unknown, maxTurns = 8, maxChars = 1000, maxTotal = 6000): ChatTurn[] {
  if (!Array.isArray(raw)) return [];
  const turns: ChatTurn[] = [];
  for (const m of raw.slice(-maxTurns)) {
    if (!m || typeof m !== "object") continue;
    const role = (m as { role?: unknown }).role;
    const content = (m as { content?: unknown }).content;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") continue;
    const text = content.slice(0, maxChars).trim();
    if (!text) continue;
    const last = turns[turns.length - 1];
    if (last && last.role === role) continue; // keep alternation
    turns.push({ role, content: text });
  }
  while (turns.length && turns[0].role !== "user") turns.shift();
  // The new question is appended as a user turn, so history must end with an assistant turn.
  while (turns.length && turns[turns.length - 1].role !== "assistant") turns.pop();
  let total = turns.reduce((n, t) => n + t.content.length, 0);
  while (total > maxTotal && turns.length >= 2) {
    total -= turns[0].content.length + turns[1].content.length;
    turns.splice(0, 2);
  }
  return turns;
}

// ---------------------------------------------------------------------------
// Push notification payload
// ---------------------------------------------------------------------------

export const NOTIFY_TYPES: readonly string[] = ["task_submitted", "adhan"];

/** FCM data must be string → string; we allow a few short, non-reserved keys only. */
export function sanitiseNotifyData(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  for (const [k, v] of Object.entries(raw as Record<string, unknown>).slice(0, 5)) {
    if (!/^[a-zA-Z][a-zA-Z0-9_]{0,30}$/.test(k)) continue;
    if (k === "type" || k === "childId" || k === "from" || /^(google|gcm)/i.test(k)) continue;
    if (typeof v !== "string" && typeof v !== "number" && typeof v !== "boolean") continue;
    out[k] = String(v).slice(0, 100);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Device protection: tamper alerts + heartbeats (docs/decisions/DEVICE-PROTECTION.md)
// ---------------------------------------------------------------------------

/** Why a child device's protection is off. Anything else from a client is dropped. */
export const TAMPER_REASONS: readonly string[] = ["accessibility_off", "device_admin_off", "screen_time_off"];

/** A device that has not reported for this long gets one "not checking in" alert. */
export const HEARTBEAT_STALE_MS = 24 * 60 * 60_000;

export interface ProtectionReport {
  platform: "android" | "ios";
  reasons: string[];
}

/** Validates a child device's protection report: only known platforms and reasons, deduplicated. */
export function parseProtectionReport(raw: unknown): ProtectionReport | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  if (r.platform !== "android" && r.platform !== "ios") return null;
  const list = Array.isArray(r.reasons) ? r.reasons.slice(0, 10) : [];
  const reasons = [...new Set(list.filter((x): x is string => typeof x === "string" && TAMPER_REASONS.includes(x)))].sort();
  return { platform: r.platform, reasons };
}

/** Reasons present now that were not reported last time (each tamper is alerted once). */
export function newTamperReasons(previous: unknown, current: readonly string[]): string[] {
  const prev = new Set(Array.isArray(previous) ? previous.filter((x) => typeof x === "string") : []);
  return current.filter((r) => !prev.has(r));
}

/** True when a heartbeat is older than [staleMs] and no stale alert was sent for it yet. */
export function needsStaleAlert(lastSeenMs: unknown, staleAlerted: unknown, nowMs: number, staleMs = HEARTBEAT_STALE_MS): boolean {
  if (typeof lastSeenMs !== "number" || !Number.isFinite(lastSeenMs)) return false;
  return staleAlerted !== true && nowMs - lastSeenMs > staleMs;
}

/** Parent push text. `kind` is "tamper" or "stale". Never includes the child's name. */
export function protectionAlertText(kind: "tamper" | "stale", ar: boolean): string {
  if (kind === "tamper") {
    return ar
      ? "تنبيه: حماية Zad X اتقفلت على جهاز طفلك (إمكانية الوصول أو منع المسح أو Screen Time). افتح Zad X على الجهاز ده وشغّلها تاني."
      : "Alert: Zad X protection was turned off on your child's device (accessibility, delete protection or Screen Time). Open Zad X on that device to turn it back on.";
  }
  return ar
    ? "جهاز طفلك ما اتواصلش مع Zad X من أكتر من يوم. لو الجهاز كان مقفول تجاهل الرسالة، غير كده اتأكد إن الحماية لسه شغّالة."
    : "Your child's device has not checked in with Zad X for over a day. If it was switched off, ignore this; otherwise check that protection is still on.";
}

/** Heartbeats older than this are deleted (device gone for a month: nothing more to tell the parent). */
export const HEARTBEAT_RETENTION_MS = 30 * 24 * 60 * 60_000;

/** The same tamper reason from the same device is pushed at most once per this period. */
export const TAMPER_ALERT_COOLDOWN_MS = 60 * 60_000;

export type HeartbeatAction = "delete" | "alert" | "skip";

/**
 * What `checkHeartbeats` does with one heartbeat doc:
 * delete when the family or child is gone, or it is older than the retention period;
 * alert once when it has been silent for [staleMs]; otherwise skip.
 */
export function heartbeatAction(
  hb: { lastSeenMs: unknown; staleAlerted: unknown; familyExists: boolean; childExists: boolean },
  nowMs: number,
  staleMs = HEARTBEAT_STALE_MS,
  retentionMs = HEARTBEAT_RETENTION_MS,
): HeartbeatAction {
  if (!hb.familyExists || !hb.childExists) return "delete";
  if (typeof hb.lastSeenMs !== "number" || !Number.isFinite(hb.lastSeenMs)) return "delete";
  if (nowMs - hb.lastSeenMs > retentionMs) return "delete";
  return needsStaleAlert(hb.lastSeenMs, hb.staleAlerted, nowMs, staleMs) ? "alert" : "skip";
}

/**
 * Tamper reasons to push now: newly appeared since the last report AND not pushed for this device
 * within [cooldownMs] (a child toggling the service off/on/off gets one alert per hour, not many).
 * Returns the reasons plus the updated per-reason "last alerted" map to store.
 */
export function tamperReasonsToAlert(
  previous: unknown,
  current: readonly string[],
  alertedAt: unknown,
  nowMs: number,
  cooldownMs = TAMPER_ALERT_COOLDOWN_MS,
): { reasons: string[]; alertedAt: Record<string, number> } {
  const map: Record<string, number> = {};
  if (alertedAt && typeof alertedAt === "object" && !Array.isArray(alertedAt)) {
    for (const [k, v] of Object.entries(alertedAt as Record<string, unknown>)) {
      if (TAMPER_REASONS.includes(k) && typeof v === "number" && Number.isFinite(v)) map[k] = v;
    }
  }
  const reasons = newTamperReasons(previous, current).filter((r) => !(r in map) || nowMs - map[r] >= cooldownMs);
  for (const r of reasons) map[r] = nowMs;
  return { reasons, alertedAt: map };
}
