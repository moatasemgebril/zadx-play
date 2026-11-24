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
  const refuse = (target, familyExists, paused) => s.pairingRedeemRefusal({ target, familyExists, paused });
  const paused = s.childPaused({ ...free, childId: "cyusuf" });
  assert.equal(refuse("phone", true, paused), "child_paused");
  assert.equal(refuse("windows", true, paused), "child_paused");
  // The free child, a paid family or a trial family can still redeem.
  assert.equal(refuse("phone", true, s.childPaused({ ...free, childId: "child-1" })), null);
  const paid = { ...free, plan: "basic", planExpiresAt: new Date(now + 86_400_000).toISOString() };
  assert.equal(refuse("phone", true, s.childPaused({ ...paid, childId: "cyusuf" })), null);
  assert.equal(refuse("phone", true, s.childPaused({ ...free, createdAtMs: now - 86_400_000, childId: "cyusuf" })), null);
  assert.equal(refuse("phone", false, true), null);
});

// BACKLOG P1 merge note (PR #28): a parent code has no child; its childId falls back to child-1.
test("redeemPairingCode: a parent code works while child-1 is paused on Free", () => {
  const now = Date.parse("2026-12-10T12:00:00Z");
  // Free family past its trial; the parent chose "cyusuf" as the free child, so child-1 is paused.
  const free = { plan: null, planExpiresAt: null, createdAtMs: now - 30 * 86_400_000, freeChildId: "cyusuf", now };
  const child1Paused = s.childPaused({ ...free, childId: "child-1" });
  assert.equal(child1Paused, true);
  assert.equal(s.pairingRedeemRefusal({ target: "parent", familyExists: true, paused: child1Paused }), null);
  // A child code for that same paused child is still refused.
  assert.equal(s.pairingRedeemRefusal({ target: "phone", familyExists: true, paused: child1Paused }), "child_paused");
  assert.equal(s.pairingRedeemRefusal({ target: "windows", familyExists: true, paused: child1Paused }), "child_paused");
});

test("pausePlanOf: an active plan of either app keeps every child active", () => {
  const now = Date.parse("2026-12-10T12:00:00Z");
  const future = new Date(now + 86_400_000).toISOString();
  const past = new Date(now - 1).toISOString();
  const old = { createdAtMs: now - 30 * 86_400_000, freeChildId: undefined, childId: "c2", now };
  const pausedFor = (family) => {
    const p = s.pausePlanOf(family, now);
    return s.childPaused({ ...old, plan: p.plan, planExpiresAt: p.planExpiresAt });
  };
  assert.equal(pausedFor({}), true);
  assert.equal(pausedFor(undefined), true);
  // Legacy top-level plan (no planApp = Zad X Play).
  assert.equal(pausedFor({ plan: "basic", planExpiresAt: future }), false);
  assert.equal(pausedFor({ plans: { play: { plan: "plus", planExpiresAt: future } } }), false);
  assert.equal(pausedFor({ plans: { kids: { plan: "basic", planExpiresAt: future } } }), false);
  assert.equal(pausedFor({ plans: { play: { plan: "plus", planExpiresAt: past } } }), true);
  assert.equal(pausedFor({ plans: { play: { plan: "gold", planExpiresAt: future } } }), true);
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

test("tierForApp: only the SAME app's products have a tier (App Store verification)", () => {
  const play = s.tierForApp("play");
  const kids = s.tierForApp("kids");
  assert.equal(play("zadx_plus_yearly"), "plus");
  assert.equal(play("zadx_basic_monthly"), "basic");
  assert.equal(play("zadx_kids_plus_yearly"), null);
  assert.equal(kids("zadx_kids_basic_monthly"), "basic");
  assert.equal(kids("zadx_plus_yearly"), null);
  for (const bad of ["", "toString", "__proto__", "zadx_gold_monthly"]) {
    assert.equal(play(bad), null, bad);
    assert.equal(kids(bad), null, bad);
  }
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

// ---------------------------------------------------------------------------
// Separate entitlements per app (owner-safe default 2026-11-22)
// ---------------------------------------------------------------------------

test("planAppOf / requestingAppOf: unknown = Zad X Play, requests only narrow", () => {
  assert.equal(s.planAppOf("kids"), "kids");
  for (const v of ["play", undefined, null, "KIDS", 1]) assert.equal(s.planAppOf(v), "play");
  assert.equal(s.requestingAppOf("kids"), "kids");
  assert.equal(s.requestingAppOf("play"), "play");
  assert.equal(s.requestingAppOf("islamic"), "play"); // the app's variant name
  for (const v of [undefined, null, "", "both", {}]) assert.equal(s.requestingAppOf(v), null);
});

test("a Kids plan never unlocks Zad X Play and a Play plan never unlocks Kids", () => {
  const future = new Date(Date.now() + 30 * 86_400_000).toISOString();
  const now = Date.now();
  const kidsOnly = { plans: { kids: { plan: "plus", planExpiresAt: future, inTrial: false } } };
  const playLegacy = { plan: "plus", planExpiresAt: future, inTrial: false }; // before Zad X Kids: no planApp
  const both = {
    plan: "basic", planExpiresAt: future, planApp: "play",
    plans: { play: { plan: "basic", planExpiresAt: future }, kids: { plan: "plus", planExpiresAt: future } },
  };
  const allows = (fam, app) => {
    const p = s.planForRequest(fam, app);
    return s.planAllows(p.plan, p.planExpiresAt, now, "assistant");
  };
  assert.equal(allows(kidsOnly, "kids"), true);
  assert.equal(allows(kidsOnly, "islamic"), false);
  assert.equal(allows(kidsOnly, undefined), false); // a caller that does not say it is Kids gets nothing
  assert.equal(allows(playLegacy, "islamic"), true);
  assert.equal(allows(playLegacy, undefined), true);
  assert.equal(allows(playLegacy, "kids"), false);
  assert.equal(s.planForRequest(both, "kids").plan, "plus");
  assert.equal(s.planForRequest(both, "play").plan, "basic");
  // A legacy top-level plan marked as Kids is not a Play plan.
  assert.equal(s.familyPlanFor({ plan: "plus", planExpiresAt: future, planApp: "kids" }, "play").plan, null);
  assert.equal(s.familyPlanFor(undefined, "play").plan, null);
  assert.equal(s.familyPlanFor({ plans: [] }, "kids").plan, null);
});

test("productIdFor: the verified product id wins (yearly referral deferral)", () => {
  assert.equal(s.productIdFor("plus", "play", "zadx_plus_yearly"), "zadx_plus_yearly");
  assert.equal(s.productIdFor("basic", "kids", "zadx_kids_basic_yearly"), "zadx_kids_basic_yearly");
  // Another app's or an unknown product id is ignored: fall back to the tier's monthly product.
  assert.equal(s.productIdFor("plus", "play", "zadx_kids_plus_yearly"), "zadx_plus_monthly");
  assert.equal(s.productIdFor("plus", "kids", "evil_product"), "zadx_kids_plus_monthly");
  assert.equal(s.productIdFor("plus", "kids", undefined), "zadx_kids_plus_monthly");
});

test("Kids-visible parent notifications are neutral; Kids families never get the adhan push", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const words = JSON.parse(fs.readFileSync(path.join(__dirname, "../../../tools/kids_forbidden_words.json"), "utf8"));
  const religious = (t) => [
    ...words.en.filter((w) => new RegExp(`(?<![A-Za-z'])${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z'])`, "i").test(t)),
    ...words.ar.filter((w) => t.includes(w)),
  ];
  for (const ar of [true, false]) {
    assert.equal(s.parentNotificationBody("adhan", ar, "kids"), null);
    assert.ok(s.parentNotificationBody("adhan", ar, "islamic"));
    const task = s.parentNotificationBody("task_submitted", ar, "kids");
    assert.deepEqual(religious(task), [], task);
    for (const kind of ["tamper", "stale"]) assert.deepEqual(religious(s.protectionAlertText(kind, ar)), []);
  }
  assert.equal(s.parentNotificationBody("other", false, undefined), null);
});

test("clock_changed is a tamper reason", () => {
  assert.deepEqual(s.parseProtectionReport({ platform: "android", reasons: ["clock_changed", "bogus"] }).reasons, ["clock_changed"]);
});
