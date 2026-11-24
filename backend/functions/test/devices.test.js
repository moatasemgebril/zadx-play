// Unit tests for removing a linked device (BACKLOG P1-3): who may remove whom, the last-parent
// guard and the audit entry. Run with `npm test` (node:test, no extra deps).
const test = require("node:test");
const assert = require("node:assert/strict");
const d = require("../lib/devices-logic.js");

const PARENT = "parentUid";
const PARENT2 = "parentPhone2";
const KID1 = "kid1DeviceUid";
const KID2 = "kid2DeviceUid";
const STRANGER = "strangerUid";

/** Same shape as the rules tests: creator parent + linked parent phone + two child devices. */
const family = (over = {}) => ({
  members: [PARENT, PARENT2, KID1, KID2],
  childDevices: { [KID1]: "c1", [KID2]: "c2" },
  ...over,
});

test("parent removes a child device", () => {
  assert.deepEqual(d.removeDeviceDecision(family(), PARENT, KID1), { ok: true, targetRole: "child", self: false });
  // A linked parent phone may do it too.
  assert.deepEqual(d.removeDeviceDecision(family(), PARENT2, KID2), { ok: true, targetRole: "child", self: false });
});

test("parent removes another parent phone (e.g. a lost phone)", () => {
  assert.deepEqual(d.removeDeviceDecision(family(), PARENT, PARENT2), { ok: true, targetRole: "parent", self: false });
  // ... and the linked phone may remove the creator's phone: both are parents.
  assert.deepEqual(d.removeDeviceDecision(family(), PARENT2, PARENT), { ok: true, targetRole: "parent", self: false });
});

test("a parent may leave (remove itself) while another parent remains", () => {
  assert.deepEqual(d.removeDeviceDecision(family(), PARENT2, PARENT2), { ok: true, targetRole: "parent", self: true });
});

test("the last parent is refused (itself), whatever the number of child devices", () => {
  const solo = family({ members: [PARENT, KID1, KID2] });
  assert.deepEqual(d.removeDeviceDecision(solo, PARENT, PARENT), {
    ok: false, code: "failed-precondition", reason: "last_parent",
  });
  // Removing a child device in that family is still fine.
  assert.equal(d.removeDeviceDecision(solo, PARENT, KID1).ok, true);
  // Duplicated uids in members do not count as two parents.
  const dup = family({ members: [PARENT, PARENT, KID1] });
  assert.equal(d.removeDeviceDecision(dup, PARENT, PARENT).reason, "last_parent");
});

test("a child device can never remove anything (other child, a parent, itself)", () => {
  for (const target of [KID2, PARENT, PARENT2, KID1]) {
    assert.deepEqual(d.removeDeviceDecision(family(), KID1, target), {
      ok: false, code: "permission-denied", reason: "parent_required",
    }, target);
  }
});

test("a stranger or a parent of another family is refused", () => {
  for (const target of [KID1, PARENT, PARENT2, STRANGER]) {
    assert.deepEqual(d.removeDeviceDecision(family(), STRANGER, target), {
      ok: false, code: "permission-denied", reason: "not_member",
    }, target);
  }
  // A parent of THIS family cannot remove a device of another family (not a member here).
  const other = { members: ["otherParent", "otherKid"], childDevices: { otherKid: "c1" } };
  assert.deepEqual(d.removeDeviceDecision(family(), PARENT, "otherKid"), {
    ok: false, code: "not-found", reason: "device_not_found",
  });
  assert.equal(d.removeDeviceDecision(other, PARENT, KID1).reason, "not_member");
});

test("a device still in childDevices but no longer a member is not a member", () => {
  const stale = family({ members: [PARENT, PARENT2, KID2] });
  assert.equal(d.memberRole(stale, KID1), null);
  assert.equal(d.removeDeviceDecision(stale, KID1, KID2).reason, "not_member");
  assert.equal(d.removeDeviceDecision(stale, PARENT, KID1).reason, "device_not_found");
});

test("role comes from server data only and fails safe on malformed docs", () => {
  assert.equal(d.memberRole(family(), PARENT), "parent");
  assert.equal(d.memberRole(family(), KID1), "child");
  assert.deepEqual(d.parentMembers(family()), [PARENT, PARENT2]);
  // Malformed members: nobody is a member, so nothing can be removed.
  for (const members of [undefined, null, "parentUid", { 0: PARENT }]) {
    assert.equal(d.removeDeviceDecision({ members, childDevices: {} }, PARENT, KID1).reason, "not_member");
  }
  // A non-string childDevices value is not a binding (the rules read it the same way: null = parent).
  assert.equal(d.memberRole({ members: [PARENT], childDevices: { [PARENT]: null } }, PARENT), "parent");
  // Inherited keys (e.g. "constructor") are never a binding.
  assert.equal(d.memberRole({ members: ["constructor"], childDevices: {} }, "constructor"), "parent");
});

test("parseRemoveDeviceRequest accepts only safe ids", () => {
  assert.deepEqual(d.parseRemoveDeviceRequest({ familyId: "f1", deviceUid: KID1 }), { familyId: "f1", deviceUid: KID1 });
  for (const bad of [
    null, undefined, [], "x",
    { familyId: "f1" },
    { deviceUid: KID1 },
    { familyId: "f1", deviceUid: "a/b" },
    { familyId: "../x", deviceUid: KID1 },
    { familyId: "f1", deviceUid: "" },
    { familyId: "f1", deviceUid: "x".repeat(129) },
    { familyId: "f1", deviceUid: 42 },
  ]) {
    assert.equal(d.parseRemoveDeviceRequest(bad), null, JSON.stringify(bad));
  }
});

test("audit entry: who removed whom and when, nothing about the child", () => {
  const now = Date.parse("2026-11-24T08:00:00Z");
  const a = d.deviceRemovalAudit(PARENT, KID1, "child", now);
  assert.deepEqual(Object.keys(a).sort(), ["action", "atMs", "byUid", "expiresAt", "targetRole", "targetUid"]);
  assert.equal(a.action, "device_removed");
  assert.equal(a.byUid, PARENT);
  assert.equal(a.targetUid, KID1);
  assert.equal(a.atMs, now);
  assert.equal(a.expiresAt.getTime(), now + d.DEVICE_AUDIT_RETENTION_MS);
});
