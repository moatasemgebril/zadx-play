// Unit tests for the pure push helpers (run with `npm test`, uses node:test, no extra deps).
const test = require("node:test");
const assert = require("node:assert/strict");
const p = require("../lib/push.js");

const TOKEN = "fAKE_t0ken:APA91b" + "x".repeat(140);
const TOKEN2 = "other-token:APA91b" + "y".repeat(140);

test("only the three client types are accepted by notifyParent", () => {
  for (const t of ["task_submitted", "unlock_request", "adhan"]) assert.equal(p.isClientPushType(t), true, t);
  for (const bad of ["device_paired", "weekly_summary", "marketing", "", null, 1, { t: 1 }]) {
    assert.equal(p.isClientPushType(bad), false, String(bad));
  }
});

test("pushText is generic, bilingual and never empty", () => {
  for (const type of [...p.CLIENT_PUSH_TYPES, ...p.SERVER_PUSH_TYPES]) {
    for (const lang of ["ar", "en"]) {
      const { title, body } = p.pushText(type, lang);
      assert.equal(title, "Zad X");
      assert.ok(body.length > 5 && body.length < 200, `${type}/${lang}`);
    }
  }
  assert.equal(p.pushLang("en"), "en");
  assert.equal(p.pushLang("fr"), "ar");
  assert.equal(p.pushLang(undefined), "ar");
});

test("buildPushData keeps only allow-listed ids / enums (no free text, no names)", () => {
  assert.deepEqual(p.buildPushData("task_submitted", "child-1", { taskId: "fajr_prayer", nickname: "Omar", note: "hi" }), {
    type: "task_submitted",
    childId: "child-1",
    taskId: "fajr_prayer",
  });
  // Free text in an id field is dropped.
  assert.deepEqual(p.buildPushData("task_submitted", "c1", { taskId: "Omar's homework" }), { type: "task_submitted", childId: "c1" });
  // Enum values only.
  assert.deepEqual(p.buildPushData("adhan", "c1", { prayer: "asr" }), { type: "adhan", childId: "c1", prayer: "asr" });
  assert.deepEqual(p.buildPushData("adhan", "c1", { prayer: "party" }), { type: "adhan", childId: "c1" });
  assert.deepEqual(p.buildPushData("device_paired", null, { target: "windows" }), { type: "device_paired", target: "windows" });
  // Keys of other types, reserved keys and non-strings are ignored; the type cannot be overridden.
  assert.deepEqual(p.buildPushData("weekly_summary", null, { type: "x", taskId: "a", from: "y" }), { type: "weekly_summary" });
  assert.deepEqual(p.buildPushData("task_submitted", "c1", { taskId: 42 }), { type: "task_submitted", childId: "c1" });
  // Bad childId / raw shapes.
  assert.deepEqual(p.buildPushData("task_submitted", "a/b", null), { type: "task_submitted" });
  assert.deepEqual(p.buildPushData("task_submitted", "x".repeat(41), ["a"]), { type: "task_submitted" });
});

test("isFcmToken", () => {
  assert.equal(p.isFcmToken(TOKEN), true);
  for (const bad of ["", "short", "has space " + "x".repeat(30), "x".repeat(4097), "a/b" + "x".repeat(30), null, 5]) {
    assert.equal(p.isFcmToken(bad), false, String(bad).slice(0, 20));
  }
});

test("isStaleTokenError only for permanent token errors", () => {
  assert.equal(p.isStaleTokenError("messaging/registration-token-not-registered"), true);
  assert.equal(p.isStaleTokenError("messaging/invalid-registration-token"), true);
  assert.equal(p.isStaleTokenError("messaging/internal-error"), false);
  assert.equal(p.isStaleTokenError("messaging/invalid-argument"), false);
  assert.equal(p.isStaleTokenError(undefined), false);
});

test("pushAllowedBySettings follows the family switches", () => {
  assert.equal(p.pushAllowedBySettings("task_submitted", undefined), true);
  assert.equal(p.pushAllowedBySettings("task_submitted", { notifyOnTasks: false }), false);
  assert.equal(p.pushAllowedBySettings("unlock_request", { notifyOnTasks: false }), false);
  assert.equal(p.pushAllowedBySettings("adhan", { notifyOnAdhan: false }), false);
  assert.equal(p.pushAllowedBySettings("adhan", { notifyOnTasks: false }), true);
  assert.equal(p.pushAllowedBySettings("device_paired", { notifyOnTasks: false, notifyOnAdhan: false }), true);
  assert.equal(p.pushAllowedBySettings("weekly_summary", "garbage"), true);
});

test("every push type has a positive rate limit", () => {
  for (const type of [...p.CLIENT_PUSH_TYPES, ...p.SERVER_PUSH_TYPES]) {
    const rl = p.PUSH_RATE_LIMITS[type];
    assert.ok(rl.limit > 0 && rl.windowMs > 0, type);
  }
});

test("selectRecipients: parents only, never child devices, never non-members", () => {
  const devices = [
    { id: "parentA", token: TOKEN, lang: "en" },
    { id: "childPhone", token: TOKEN2, lang: "ar" }, // bound child device
    { id: "stranger", token: TOKEN2 + "z", lang: "ar" }, // not a member any more
    { id: "parentB", token: "bad token", lang: "ar" }, // malformed
    { id: "parentC", token: TOKEN, lang: "ar" }, // duplicate token
    { id: "a/b", token: TOKEN2 + "q" },
  ];
  const members = ["parentA", "childPhone", "parentB", "parentC", "a/b"];
  const r = p.selectRecipients(devices, members, { childPhone: "child-1" });
  assert.deepEqual(r, [{ uid: "parentA", token: TOKEN, lang: "en" }]);
});

test("selectRecipients excludes the caller, defaults lang, caps the list and survives bad input", () => {
  const devices = [
    { id: "p1", token: TOKEN },
    { id: "p2", token: TOKEN2, lang: "xx" },
  ];
  assert.deepEqual(p.selectRecipients(devices, ["p1", "p2"], undefined, "p1"), [{ uid: "p2", token: TOKEN2, lang: "ar" }]);
  const many = Array.from({ length: 30 }, (_, i) => ({ id: `p${i}`, token: TOKEN + i }));
  assert.equal(p.selectRecipients(many, many.map((d) => d.id), {}).length, p.MAX_PARENT_DEVICES);
  assert.deepEqual(p.selectRecipients(devices, "not-an-array", null), []);
  assert.deepEqual(p.selectRecipients([], ["p1"], {}), []);
});
