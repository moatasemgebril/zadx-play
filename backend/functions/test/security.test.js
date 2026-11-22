// Unit tests for the pure security helpers (run with `npm test`, uses node:test, no extra deps).
const test = require("node:test");
const assert = require("node:assert/strict");
const s = require("../lib/security.js");

test("isSafeId accepts Firestore ids and rejects path tricks", () => {
  assert.equal(s.isSafeId("aB3_x-9"), true);
  assert.equal(s.isSafeId("child-1"), true);
  for (const bad of ["", "a/b", "../x", "a b", "x".repeat(129), 42, null, undefined, {}]) {
    assert.equal(s.isSafeId(bad), false, String(bad));
  }
});

test("isPairingCode requires exactly six digits", () => {
  assert.equal(s.isPairingCode("012345"), true);
  for (const bad of ["12345", "1234567", "12a456", " 123456", 123456, null]) {
    assert.equal(s.isPairingCode(bad), false, String(bad));
  }
});

test("normaliseReferralCode", () => {
  assert.equal(s.normaliseReferralCode(" zadx-ab23 "), "ZADX-AB23");
  assert.equal(s.normaliseReferralCode("ZADX-AB1O"), null); // 1 and O are not in the alphabet
  assert.equal(s.normaliseReferralCode("families/x"), null);
  assert.equal(s.normaliseReferralCode(undefined), null);
});

test("hexDigestEquals is exact and safe on bad input", () => {
  const h = s.sha256Hex("secret");
  assert.equal(s.hexDigestEquals(h, s.sha256Hex("secret")), true);
  assert.equal(s.hexDigestEquals(h, s.sha256Hex("Secret")), false);
  assert.equal(s.hexDigestEquals(undefined, h), false);
  assert.equal(s.hexDigestEquals("zz", h), false);
  assert.equal(s.hexDigestEquals(h.slice(0, 10), h), false);
  assert.equal(s.hexDigestEquals("", ""), false);
});

test("rateLimitDecision fixed window", () => {
  let st;
  const now = 1_000_000;
  for (let i = 0; i < 3; i++) {
    const d = s.rateLimitDecision(st, now + i, 3, 60_000);
    assert.equal(d.allowed, true);
    st = d.next;
  }
  const blocked = s.rateLimitDecision(st, now + 10, 3, 60_000);
  assert.equal(blocked.allowed, false);
  assert.ok(blocked.retryAfterMs > 0);
  const later = s.rateLimitDecision(st, now + 60_000, 3, 60_000);
  assert.equal(later.allowed, true);
  assert.deepEqual(later.next, { windowStart: now + 60_000, count: 1 });
  // A window start in the future (clock skew / tampering) resets the window.
  assert.equal(s.rateLimitDecision({ windowStart: now * 2, count: 99 }, now, 3, 60_000).allowed, true);
});

test("rateLimitKey hides the subject", () => {
  const k = s.rateLimitKey("pairRedeemIp", "203.0.113.7");
  assert.match(k, /^pairRedeemIp_[0-9a-f]{40}$/);
  assert.ok(!k.includes("203.0.113.7"));
});

test("hasActivePlan", () => {
  const now = Date.parse("2026-01-01T00:00:00Z");
  assert.equal(s.hasActivePlan("plus", "2026-02-01T00:00:00Z", now), true);
  assert.equal(s.hasActivePlan("basic", "2026-02-01T00:00:00Z", now), true);
  assert.equal(s.hasActivePlan("plus", "2025-12-01T00:00:00Z", now), false);
  assert.equal(s.hasActivePlan(undefined, "2026-02-01T00:00:00Z", now), false);
  assert.equal(s.hasActivePlan("gold", "2026-02-01T00:00:00Z", now), false);
  assert.equal(s.hasActivePlan("plus", null, now), false);
  assert.equal(s.hasActivePlan("plus", "not a date", now), false);
});

test("sanitiseHistory keeps alternating, bounded turns", () => {
  const h = s.sanitiseHistory([
    { role: "assistant", content: "hi" }, // dropped: must start with user
    { role: "user", content: "q1" },
    { role: "user", content: "dup" }, // dropped: no alternation
    { role: "system", content: "evil" }, // dropped: role
    { role: "assistant", content: { x: 1 } }, // dropped: not a string
    { role: "assistant", content: "a1" },
    { role: "user", content: "q2" }, // dropped: history must end with assistant
  ]);
  assert.deepEqual(h, [
    { role: "user", content: "q1" },
    { role: "assistant", content: "a1" },
  ]);
  assert.deepEqual(s.sanitiseHistory("nope"), []);
  const long = s.sanitiseHistory([{ role: "user", content: "x".repeat(5000) }, { role: "assistant", content: "y" }]);
  assert.equal(long[0].content.length, 1000);
  const many = [];
  for (let i = 0; i < 8; i++) many.push({ role: i % 2 ? "assistant" : "user", content: "z".repeat(1000) });
  const bounded = s.sanitiseHistory(many);
  assert.ok(bounded.reduce((n, t) => n + t.content.length, 0) <= 6000);
  assert.equal(bounded[0].role, "user");
});

test("sanitiseNotifyData drops reserved and non-scalar values", () => {
  const d = s.sanitiseNotifyData({ taskId: "fajr", type: "x", childId: "y", nested: { a: 1 }, n: 5 });
  assert.deepEqual(d, { taskId: "fajr", n: "5" });
  assert.deepEqual(s.sanitiseNotifyData({ from: "z", google_x: "1", gcmY: "2", "bad key": "v", ok: true }), { ok: "true" });
  assert.deepEqual(s.sanitiseNotifyData(null), {});
  assert.deepEqual(s.sanitiseNotifyData(["a"]), {});
  assert.equal(s.sanitiseNotifyData({ prayer: "x".repeat(500) }).prayer.length, 100);
});

test("PLAN_FEATURES: free is only lock, prayer times, adhan, Quran and adhkar; basic ⊂ plus", () => {
  assert.deepEqual([...s.PLAN_FEATURES.free].sort(), ["adhan", "adhkar", "appLock", "prayerTimes", "quran"]);
  for (const f of s.PLAN_FEATURES.free) assert.ok(s.PLAN_FEATURES.basic.includes(f), f);
  for (const f of s.PLAN_FEATURES.basic) assert.ok(s.PLAN_FEATURES.plus.includes(f), f);
  assert.ok(s.PLAN_FEATURES.plus.length > s.PLAN_FEATURES.basic.length);
});

test("planAllows: free features always, paid only with an active plan", () => {
  const now = Date.parse("2026-01-15T00:00:00Z");
  const future = "2026-02-01T00:00:00Z";
  const past = "2025-12-01T00:00:00Z";
  for (const f of ["appLock", "prayerTimes", "adhan", "quran", "adhkar"]) {
    assert.equal(s.planAllows(null, null, now, f), true, f);
    assert.equal(s.planAllows("plus", past, now, f), true, f);
  }
  assert.equal(s.planAllows(null, null, now, "assistant"), false);
  assert.equal(s.planAllows("basic", past, now, "assistant"), false);
  assert.equal(s.planAllows("basic", future, now, "assistant"), true);
  assert.equal(s.planAllows("basic", future, now, "unlimitedAssistant"), false);
  assert.equal(s.planAllows("plus", future, now, "unlimitedAssistant"), true);
  assert.equal(s.planAllows("gold", future, now, "games"), false);
});

// Device protection (docs/decisions/DEVICE-PROTECTION.md)
test("parseProtectionReport keeps only known platforms and reasons", () => {
  assert.deepEqual(s.parseProtectionReport({ platform: "android", reasons: ["accessibility_off", "x", "accessibility_off", 3] }), {
    platform: "android", reasons: ["accessibility_off"],
  });
  assert.deepEqual(s.parseProtectionReport({ platform: "ios" }), { platform: "ios", reasons: [] });
  for (const bad of [null, [], "android", { platform: "windows" }, { platform: "web", reasons: [] }]) {
    assert.equal(s.parseProtectionReport(bad), null);
  }
});

test("newTamperReasons alerts each reason once", () => {
  assert.deepEqual(s.newTamperReasons(undefined, ["accessibility_off"]), ["accessibility_off"]);
  assert.deepEqual(s.newTamperReasons(["accessibility_off"], ["accessibility_off"]), []);
  assert.deepEqual(s.newTamperReasons(["accessibility_off"], ["accessibility_off", "device_admin_off"]), ["device_admin_off"]);
  assert.deepEqual(s.newTamperReasons("junk", []), []);
});

test("needsStaleAlert after a day without a heartbeat, once", () => {
  const now = Date.UTC(2026, 10, 21);
  const day = 24 * 60 * 60_000;
  assert.equal(s.needsStaleAlert(now - day - 1, false, now), true);
  assert.equal(s.needsStaleAlert(now - day - 1, true, now), false);
  assert.equal(s.needsStaleAlert(now - 1000, false, now), false);
  assert.equal(s.needsStaleAlert(undefined, false, now), false);
});

test("protectionAlertText never names the child", () => {
  for (const kind of ["tamper", "stale"]) {
    for (const ar of [true, false]) {
      const t = s.protectionAlertText(kind, ar);
      assert.ok(t.length > 20 && t.length < 300);
    }
  }
});

test("heartbeatAction deletes orphans and old docs, alerts once", () => {
  const now = Date.UTC(2026, 10, 21);
  const day = 24 * 60 * 60_000;
  const ok = { familyExists: true, childExists: true };
  assert.equal(s.heartbeatAction({ ...ok, lastSeenMs: now - 2 * day, staleAlerted: false }, now), "alert");
  assert.equal(s.heartbeatAction({ ...ok, lastSeenMs: now - 2 * day, staleAlerted: true }, now), "skip");
  assert.equal(s.heartbeatAction({ ...ok, lastSeenMs: now - 1000, staleAlerted: false }, now), "skip");
  assert.equal(s.heartbeatAction({ ...ok, lastSeenMs: now - 31 * day, staleAlerted: true }, now), "delete");
  assert.equal(s.heartbeatAction({ familyExists: true, childExists: false, lastSeenMs: now - 2 * day, staleAlerted: false }, now), "delete");
  assert.equal(s.heartbeatAction({ familyExists: false, childExists: true, lastSeenMs: now, staleAlerted: false }, now), "delete");
  assert.equal(s.heartbeatAction({ ...ok, lastSeenMs: "x", staleAlerted: false }, now), "delete");
});

test("tamperReasonsToAlert applies a per-device cooldown per reason", () => {
  const now = Date.UTC(2026, 10, 21);
  const first = s.tamperReasonsToAlert([], ["accessibility_off"], undefined, now);
  assert.deepEqual(first.reasons, ["accessibility_off"]);
  // Turned back on, then off again 10 minutes later: no second push.
  const again = s.tamperReasonsToAlert([], ["accessibility_off"], first.alertedAt, now + 10 * 60_000);
  assert.deepEqual(again.reasons, []);
  // After the hour: pushed again.
  assert.deepEqual(s.tamperReasonsToAlert([], ["accessibility_off"], first.alertedAt, now + 61 * 60_000).reasons, ["accessibility_off"]);
  // Still off (already reported): never re-pushed.
  assert.deepEqual(s.tamperReasonsToAlert(["accessibility_off"], ["accessibility_off"], {}, now).reasons, []);
  // Junk in the stored map is dropped.
  assert.deepEqual(s.tamperReasonsToAlert([], [], { bad: 1, accessibility_off: "x" }, now).alertedAt, {});
});

// Free plan = one child (owner decision 2026-11-21, docs/decisions/FREE-ONE-CHILD.md).
test("childPaused: Free keeps only the first child (child-1) active", () => {
  const now = Date.parse("2026-12-10T12:00:00Z");
  const old = now - 30 * 24 * 60 * 60_000; // family created a month ago: trial over
  const base = { plan: undefined, planExpiresAt: undefined, createdAtMs: old, freeChildId: undefined, now };
  assert.equal(s.childPaused({ ...base, childId: "child-1" }), false);
  assert.equal(s.childPaused({ ...base, childId: "cabc123" }), true);
});

test("childPaused: the parent's chosen child stays active instead", () => {
  const now = Date.parse("2026-12-10T12:00:00Z");
  const base = { plan: null, planExpiresAt: null, createdAtMs: 0, freeChildId: "cabc123", now };
  assert.equal(s.childPaused({ ...base, childId: "cabc123" }), false);
  assert.equal(s.childPaused({ ...base, childId: "child-1" }), true);
  // A malformed choice falls back to child-1, never to "everyone active".
  assert.equal(s.childPaused({ ...base, freeChildId: "../x", childId: "child-1" }), false);
  assert.equal(s.childPaused({ ...base, freeChildId: "../x", childId: "cabc123" }), true);
});

test("childPaused: nobody is paused on a paid plan or during the first 7 days", () => {
  const now = Date.parse("2026-12-10T12:00:00Z");
  const future = new Date(now + 86_400_000).toISOString();
  const past = new Date(now - 1).toISOString();
  assert.equal(s.childPaused({ plan: "basic", planExpiresAt: future, createdAtMs: 0, freeChildId: undefined, childId: "c2", now }), false);
  assert.equal(s.childPaused({ plan: "plus", planExpiresAt: future, createdAtMs: 0, freeChildId: undefined, childId: "c2", now }), false);
  // Expired plan: paused again (data is kept; resumes when the family subscribes).
  assert.equal(s.childPaused({ plan: "plus", planExpiresAt: past, createdAtMs: 0, freeChildId: undefined, childId: "c2", now }), true);
  // Server-side 7-day trial from the family's creation time.
  assert.equal(s.childPaused({ plan: null, planExpiresAt: null, createdAtMs: now - 6 * 86_400_000, freeChildId: undefined, childId: "c2", now }), false);
  assert.equal(s.childPaused({ plan: null, planExpiresAt: null, createdAtMs: now - 7 * 86_400_000, freeChildId: undefined, childId: "c2", now }), true);
  // Missing or bad creation time: no trial.
  assert.equal(s.childPaused({ plan: null, planExpiresAt: null, createdAtMs: "x", freeChildId: undefined, childId: "c2", now }), true);
});

test("freeChildIdOf defaults to child-1", () => {
  assert.equal(s.freeChildIdOf(undefined), "child-1");
  assert.equal(s.freeChildIdOf("cAbc_1"), "cAbc_1");
  assert.equal(s.freeChildIdOf("a/b"), "child-1");
  assert.equal(s.freeChildIdOf(42), "child-1");
});

test("redeemPairingCode refuses a code for a child paused on Free (child_paused)", () => {
  const now = Date.parse("2026-12-10T12:00:00Z");
  const free = { plan: null, planExpiresAt: null, createdAtMs: now - 30 * 86_400_000, freeChildId: undefined, now };
  const paused = s.childPaused({ ...free, childId: "cyusuf" });
  assert.equal(s.pairingRedeemRefusal(true, paused), "child_paused");
  // The free child, a paid family or a trial family can still redeem.
  assert.equal(s.pairingRedeemRefusal(true, s.childPaused({ ...free, childId: "child-1" })), null);
  const paid = { ...free, plan: "basic", planExpiresAt: new Date(now + 86_400_000).toISOString() };
  assert.equal(s.pairingRedeemRefusal(true, s.childPaused({ ...paid, childId: "cyusuf" })), null);
  assert.equal(s.pairingRedeemRefusal(true, s.childPaused({ ...free, createdAtMs: now - 86_400_000, childId: "cyusuf" })), null);
  assert.equal(s.pairingRedeemRefusal(false, true), null);
});
