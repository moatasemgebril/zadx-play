// Unit tests for server-side task approval (R-32): approveTask payload checks, idempotent
// crediting and the daily cap. Run with `npm test` (node:test, no extra deps).
const test = require("node:test");
const assert = require("node:assert/strict");
const s = require("../lib/security.js");

const NOW = Date.parse("2026-11-22T10:00:00Z");

test("isApprovalDay: real yyyy-MM-dd dates within two days only", () => {
  assert.equal(s.isApprovalDay("2026-11-22", NOW), true);
  assert.equal(s.isApprovalDay("2026-11-21", NOW), true);
  assert.equal(s.isApprovalDay("2026-11-24", NOW), true);
  for (const bad of ["2026-11-10", "2027-11-22", "2026-02-30", "2026-11-22/x", "22-11-2026", "", null, 20261122]) {
    assert.equal(s.isApprovalDay(bad, NOW), false, String(bad));
  }
});

test("parseApprovalRequest validates ids, minutes and the required list", () => {
  const ok = s.parseApprovalRequest({ taskId: "homework", minutes: 20, requiredTaskIds: ["prayer", "homework", "prayer"], isPrayer: false });
  assert.deepEqual(ok, { taskId: "homework", minutes: 20, requiredTaskIds: ["prayer", "homework"], isPrayer: false });
  assert.equal(s.parseApprovalRequest({ taskId: "prayer", minutes: 10 }).isPrayer, false);
  for (const bad of [
    null, [], "x",
    { taskId: "a/b", minutes: 10 },
    { taskId: "x".repeat(65), minutes: 10 },
    { taskId: "t", minutes: -1 },
    { taskId: "t", minutes: 1.5 },
    { taskId: "t", minutes: s.MAX_TASK_MINUTES + 1 },
    { taskId: "t", minutes: "10" },
    { taskId: "t", minutes: 10, requiredTaskIds: "prayer" },
    { taskId: "t", minutes: 10, requiredTaskIds: ["../x"] },
    { taskId: "t", minutes: 10, requiredTaskIds: Array.from({ length: s.MAX_TASKS + 1 }, (_, i) => `t${i}`) },
    { taskId: "t", minutes: 10, isPrayer: "yes" },
  ]) {
    assert.equal(s.parseApprovalRequest(bad), null, JSON.stringify(bad));
  }
});

test("applyApproval credits a task once and computes requiredDone", () => {
  const req = (taskId, minutes) => ({ taskId, minutes, requiredTaskIds: ["prayer", "homework"], isPrayer: false });
  let out = s.applyApproval(undefined, req("prayer", 10));
  assert.deepEqual(out, { credited: 10, approved: { prayer: 10 }, earnedMinutes: 10, requiredDone: false });
  out = s.applyApproval(out.approved, req("homework", 20));
  assert.equal(out.credited, 20);
  assert.equal(out.earnedMinutes, 30);
  assert.equal(out.requiredDone, true);
  // Approving the same task again (e.g. "I prayed" at the next adhan) never credits twice.
  const again = s.applyApproval(out.approved, req("prayer", 10));
  assert.equal(again.credited, 0);
  assert.equal(again.earnedMinutes, 30);
});

test("applyApproval never goes over the daily cap", () => {
  const big = {};
  for (let i = 0; i < 5; i++) big[`t${i}`] = 120; // 600 = cap
  const out = s.applyApproval(big, { taskId: "extra", minutes: 60, requiredTaskIds: [], isPrayer: false });
  assert.equal(out.credited, 0);
  assert.equal(out.earnedMinutes, s.DAILY_EARN_CAP_MINUTES);
  const near = s.applyApproval({ a: 120, b: 120, c: 120, d: 120, e: 100 }, { taskId: "x", minutes: 60, requiredTaskIds: [], isPrayer: false });
  assert.equal(near.credited, 20);
  assert.equal(near.earnedMinutes, 600);
});

test("readCredits drops malformed server data", () => {
  assert.deepEqual(s.readCredits({ ok: 10, neg: -1, big: 9999, str: "10", "a/b": 5, frac: 1.5 }), { ok: 10 });
  assert.deepEqual(s.readCredits(null), {});
  assert.deepEqual(s.readCredits([1, 2]), {});
});
