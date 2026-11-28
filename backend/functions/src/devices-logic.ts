/**
 * Pure logic for removing a linked device from a family (BACKLOG P1-3): no Firebase imports, so
 * it is unit-tested with `npm test` (test/devices.test.js). index.ts `removeLinkedDevice` runs it
 * inside a Firestore transaction on the live family doc.
 *
 * Data model (firestore.rules): families/{id}.members = [uid...] (every device, each with its own
 * anonymous Firebase Auth uid); childDevices = {uid: childId} (paired child devices);
 * parentDevices = {uid: linkedAt} (parent phones linked with a parent code). A member that is not
 * in childDevices is a PARENT device (the family creator is in neither map).
 */
import { isSafeId } from "./security";

export type MemberRole = "parent" | "child";

export interface FamilyMembership {
  members: unknown;
  childDevices: unknown;
}

export interface RemoveDeviceRequest {
  familyId: string;
  deviceUid: string;
}

export type RemoveDeviceDecision =
  | { ok: true; targetRole: MemberRole; self: boolean }
  | {
      ok: false;
      /** HttpsError code the callable throws. */
      code: "permission-denied" | "not-found" | "failed-precondition";
      reason: "not_member" | "parent_required" | "device_not_found" | "last_parent";
    };

/** Payload of the `removeLinkedDevice` callable: {familyId, deviceUid}, both Firestore-safe ids. */
export function parseRemoveDeviceRequest(raw: unknown): RemoveDeviceRequest | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const { familyId, deviceUid } = raw as Record<string, unknown>;
  if (!isSafeId(familyId) || !isSafeId(deviceUid)) return null;
  return { familyId, deviceUid };
}

function memberList(raw: unknown): string[] {
  return Array.isArray(raw) ? raw.filter((m): m is string => typeof m === "string") : [];
}

function childMap(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {};
}

/** Role from server data only (same rule as `isParent` in firestore.rules), or null for a non-member. */
export function memberRole(family: FamilyMembership, uid: string): MemberRole | null {
  if (!memberList(family.members).includes(uid)) return null;
  const bound = childMap(family.childDevices);
  return Object.prototype.hasOwnProperty.call(bound, uid) && typeof bound[uid] === "string" ? "child" : "parent";
}

/** Parent devices of the family (members not bound to a child). */
export function parentMembers(family: FamilyMembership): string[] {
  return [...new Set(memberList(family.members))].filter((uid) => memberRole(family, uid) === "parent");
}

/**
 * May [callerUid] remove [targetUid] from this family?
 * - the caller must be a member and a PARENT device (a paired child device never can);
 * - the target must be a member of the same family;
 * - the last parent device is never removed (the family would have nobody to manage it),
 *   whether a parent removes itself or another parent.
 */
export function removeDeviceDecision(family: FamilyMembership, callerUid: string, targetUid: string): RemoveDeviceDecision {
  const callerRole = memberRole(family, callerUid);
  if (callerRole === null) return { ok: false, code: "permission-denied", reason: "not_member" };
  if (callerRole !== "parent") return { ok: false, code: "permission-denied", reason: "parent_required" };
  const targetRole = memberRole(family, targetUid);
  if (targetRole === null) return { ok: false, code: "not-found", reason: "device_not_found" };
  if (targetRole === "parent" && parentMembers(family).length <= 1) {
    return { ok: false, code: "failed-precondition", reason: "last_parent" };
  }
  return { ok: true, targetRole, self: callerUid === targetUid };
}

/** How long a device-removal audit entry is kept (Firestore TTL on `expiresAt`). */
export const DEVICE_AUDIT_RETENTION_MS = 365 * 24 * 60 * 60_000;

/**
 * Audit entry for families/{id}/audit/{autoId} (server-only). Uids and the role only: no child
 * nickname, avatar, child id or any other personal data.
 */
export function deviceRemovalAudit(byUid: string, targetUid: string, targetRole: MemberRole, nowMs: number) {
  return {
    action: "device_removed" as const,
    byUid,
    targetUid,
    targetRole,
    atMs: nowMs,
    expiresAt: new Date(nowMs + DEVICE_AUDIT_RETENTION_MS),
  };
}

/**
 * Payload of the `checkDeviceMembership` callable (BACKLOG P1-3a): {familyId}, a Firestore-safe id.
 * The caller always asks about its OWN uid (from the auth token), never about another device.
 */
export function parseMembershipRequest(raw: unknown): { familyId: string } | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const { familyId } = raw as Record<string, unknown>;
  if (!isSafeId(familyId)) return null;
  return { familyId };
}

/**
 * The explicit "is this device still in the family?" answer for `checkDeviceMembership`, read
 * with the admin SDK (so a rules bug can never make a device look removed). A missing family doc
 * is "not a member". The answer is a single boolean about the caller itself: it reveals no
 * members, roles or child data, and nothing about families the caller never belonged to beyond
 * "you are not a member".
 */
export function deviceMembershipAnswer(family: FamilyMembership | null, uid: string): { member: boolean } {
  return { member: family !== null && memberRole(family, uid) !== null };
}
