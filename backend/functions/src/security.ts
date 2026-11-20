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

/** True when the family has a paid or trial plan that has not expired. */
export function hasActivePlan(plan: unknown, planExpiresAt: unknown, now: number): boolean {
  if (plan !== "basic" && plan !== "plus") return false;
  if (typeof planExpiresAt !== "string") return false;
  const t = Date.parse(planExpiresAt);
  return Number.isFinite(t) && t > now;
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
