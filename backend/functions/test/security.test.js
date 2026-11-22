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

test("purchaseOwnerDecision: new token or own token attaches to the caller's family", () => {
  const base = { callerFamilyId: "famNew" };
  assert.deepEqual(s.purchaseOwnerDecision({ ...base, holderFamilyIds: [] }), { action: "attach" });
  assert.deepEqual(s.purchaseOwnerDecision({ ...base, holderFamilyIds: ["famNew"] }), { action: "attach" });
  assert.deepEqual(s.purchaseOwnerDecision({ ...base, holderFamilyIds: ["famNew", "famNew"] }), { action: "attach" });
});

test("purchaseOwnerDecision: a token of another family never joins or unlocks it (bearer secret)", () => {
  // Restore on a new phone / a child's tablet signed in to the parent's store account.
  assert.deepEqual(
    s.purchaseOwnerDecision({ callerFamilyId: "famNew", holderFamilyIds: ["famOld"] }),
    { action: "reject", reason: "purchase_in_other_family" },
  );
  // Ambiguous ownership (several families, legacy data).
  assert.deepEqual(
    s.purchaseOwnerDecision({ callerFamilyId: "famNew", holderFamilyIds: ["famA", "famB"] }),
    { action: "reject", reason: "purchase_in_use" },
  );
  assert.deepEqual(
    s.purchaseOwnerDecision({ callerFamilyId: "famNew", holderFamilyIds: ["famNew", "famA"] }),
    { action: "reject", reason: "purchase_in_use" },
  );
});

test("oldFamilyAction (parent code): only an untouched fresh install is left (and deleted)", () => {
  const fresh = { uid: "u1", members: ["u1"], childDevices: undefined, keys: ["members", "createdAt", "settings"], hasChildren: false, hasDevices: false };
  assert.equal(s.oldFamilyAction(fresh), "delete");
  // Anything with data or another device is refused: no abandoned children/* data, no orphans.
  assert.equal(s.oldFamilyAction({ ...fresh, hasChildren: true }), "reject");
  assert.equal(s.oldFamilyAction({ ...fresh, hasDevices: true }), "reject");
  assert.equal(s.oldFamilyAction({ ...fresh, keys: [...fresh.keys, "referralCode"] }), "reject");
  assert.equal(s.oldFamilyAction({ ...fresh, keys: [...fresh.keys, "plan"] }), "reject");
  assert.equal(s.oldFamilyAction({ ...fresh, members: ["u1", "childPhone"] }), "reject");
  assert.equal(s.oldFamilyAction({ ...fresh, childDevices: { u1: "child-1" } }), "reject");
  assert.equal(s.oldFamilyAction({ ...fresh, members: "junk" }), "reject");
});

test("tokenMigrationAction moves legacy tokens, never steals another family's", () => {
  assert.equal(s.tokenMigrationAction("famA", "tok-123456", undefined), "move");
  assert.equal(s.tokenMigrationAction("famA", "tok-123456", "famA"), "move");
  assert.equal(s.tokenMigrationAction("famA", "tok-123456", "famB"), "conflict");
  assert.equal(s.tokenMigrationAction("famA", undefined, undefined), "skip");
  assert.equal(s.tokenMigrationAction("famA", "", undefined), "skip");
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

// ---------------------------------------------------------------------------
// Zad X Kids (docs/decisions/ZADX-KIDS-VARIANT.md)
// ---------------------------------------------------------------------------

test("PRODUCTS: both apps sell the same tiers under their own ids", () => {
  const ids = Object.keys(s.PRODUCTS);
  assert.equal(ids.length, 8);
  for (const tier of ["basic", "plus"]) {
    for (const period of ["monthly", "yearly"]) {
      assert.deepEqual(s.productInfo(`zadx_${tier}_${period}`), { tier, app: "play" });
      assert.deepEqual(s.productInfo(`zadx_kids_${tier}_${period}`), { tier, app: "kids" });
    }
  }
  for (const bad of ["", "zadx_kids_gold_monthly", "__proto__", "constructor", "toString", 42, null, undefined]) {
    assert.equal(s.productInfo(bad), null, String(bad));
  }
  assert.equal(s.productIdFor("plus", "kids"), "zadx_kids_plus_monthly");
  assert.equal(s.productIdFor("basic", "play"), "zadx_basic_monthly");
  assert.equal(s.productIdFor("gold", "play"), null);
});

test("verifiedLine: only a product of the SAME app counts", () => {
  const kidsLine = { productId: "zadx_kids_plus_yearly" };
  const playLine = { productId: "zadx_plus_yearly" };
  assert.equal(s.verifiedLine("kids", [playLine, kidsLine]), kidsLine);
  assert.equal(s.verifiedLine("play", [kidsLine, playLine]), playLine);
  assert.equal(s.verifiedLine("kids", [playLine]), null);
  assert.equal(s.verifiedLine("play", [kidsLine, { productId: "other_app_sub" }, { productId: null }]), null);
  assert.equal(s.verifiedLine("play", undefined), null);
});

test("packages: only our two apps", () => {
  assert.equal(s.ANDROID_PACKAGES.play, "com.zadx.app");
  assert.equal(s.ANDROID_PACKAGES.kids, "com.zadx.kids");
  assert.equal(s.appForAndroidPackage("com.zadx.kids"), "kids");
  assert.equal(s.appForAndroidPackage("com.zadx.app"), "play");
  assert.equal(s.appForAndroidPackage("com.evil.app"), null);
  assert.equal(s.appForAndroidPackage(undefined), null);
});

test("assistant: only the exact value 'kids' selects the Kids prompt", () => {
  assert.equal(s.assistantVariant("kids"), "kids");
  for (const v of ["KIDS", "islamic", "", null, undefined, {}]) assert.equal(s.assistantVariant(v), "islamic");
});

test("Kids assistant prompt contains no religious word (tools/kids_forbidden_words.json)", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const words = JSON.parse(fs.readFileSync(path.join(__dirname, "../../../tools/kids_forbidden_words.json"), "utf8"));
  const found = [
    ...words.en.filter((w) => new RegExp(`(?<![A-Za-z'])${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z'])`, "i").test(s.KIDS_ASSISTANT_PROMPT)),
    ...words.ar.filter((w) => s.KIDS_ASSISTANT_PROMPT.includes(w)),
  ];
  assert.deepEqual(found, []);
  // The safety rules are kept.
  assert.match(s.KIDS_ASSISTANT_PROMPT, /A child may be reading/);
  assert.match(s.KIDS_ASSISTANT_PROMPT, /Never ask for, store or repeat personal information/);
});
