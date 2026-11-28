// Firestore rules tests (R-32 / R-33) against the Firestore emulator.
// Run: npm run test:rules:deps && npm run test:rules
// (firebase emulators:exec starts the emulator; needs Java + `npm i -g firebase-tools`). The test SDKs
// are not in package.json so `npm audit` covers only what we deploy.
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("fs");
const { join } = require("path");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const { createHash } = require("crypto");
const {
  doc, collection, setDoc, updateDoc, getDoc, getDocs, deleteDoc, serverTimestamp, Timestamp, increment, arrayUnion,
  arrayRemove, deleteField, FieldPath, writeBatch, addDoc,
} = require("firebase/firestore");

const DAY = "2026-11-22";
const PARENT = "parentUid";
const PARENT2 = "parentPhone2";
const KID1 = "kid1DeviceUid"; // bound to child c1
const KID2 = "kid2DeviceUid"; // bound to child c2
const STRANGER = "strangerUid";

let env;

test.before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");
  env = await initializeTestEnvironment({
    projectId: "demo-zadx",
    firestore: { rules: readFileSync(join(__dirname, "..", "..", "firestore.rules"), "utf8"), host, port: Number(port) },
  });
});

test.after(async () => {
  await env?.cleanup();
});

/** Fresh family: parent + second parent phone + two child devices bound to c1 / c2. */
async function seed({ lockMinutesAgo = 5, prayerLock = true } = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "families/f1"), {
      members: [PARENT, PARENT2, KID1, KID2],
      childDevices: { [KID1]: "c1", [KID2]: "c2" },
      parentDevices: { [PARENT2]: Timestamp.now() },
      settings: { lockAtAdhan: true, games: ["minecraft"] },
    });
    await setDoc(doc(db, "families/f1/children/c1"), { nickname: "Sara", avatar: "moon" });
    await setDoc(doc(db, "families/f1/children/c2"), { nickname: "Yusuf", avatar: "rocket" });
    for (const c of ["c1", "c2"]) {
      await setDoc(doc(db, `families/f1/children/${c}/days/${DAY}`), {
        day: DAY,
        progress: { homework: { status: "pending", count: 0 } },
        usedMinutes: 10,
        prayerLock,
        prayerLockAt: Timestamp.fromMillis(Date.now() - lockMinutesAgo * 60_000),
        approved: { prayer: 10 },
        earnedMinutes: 10,
        requiredDone: false,
      });
    }
  });
}

const as = (uid) => env.authenticatedContext(uid).firestore();
const day = (db, child = "c1", d = DAY) => doc(db, `families/f1/children/${child}/days/${d}`);

// ---- R-32: a child device cannot approve or credit itself ----------------------------------

test("child cannot approve: no approved / earnedMinutes / requiredDone writes", async () => {
  await seed();
  const db = as(KID1);
  await assertFails(setDoc(day(db), { approved: { homework: 20 } }, { merge: true }));
  await assertFails(setDoc(day(db), { earnedMinutes: 500 }, { merge: true }));
  await assertFails(setDoc(day(db), { requiredDone: true }, { merge: true }));
  await assertFails(updateDoc(day(db), { "approved.homework": 20, earnedMinutes: 30 }));
});

test("child cannot change minutes: used minutes only go up", async () => {
  await seed();
  const db = as(KID1);
  await assertFails(setDoc(day(db), { usedMinutes: 0 }, { merge: true }));
  await assertFails(setDoc(day(db), { usedMinutes: 9 }, { merge: true }));
  await assertSucceeds(setDoc(day(db), { usedMinutes: increment(5) }, { merge: true }));
  await assertSucceeds(setDoc(day(db), { usedMinutes: 20 }, { merge: true }));
});

test("child can submit a task (pending) on its own day", async () => {
  await seed();
  const db = as(KID1);
  await assertSucceeds(setDoc(day(db), {
    day: DAY, progress: { room: { status: "pending", count: 0 } }, updatedAt: serverTimestamp(), updatedBy: KID1,
  }, { merge: true }));
  // ...but not in another device's name.
  await assertFails(setDoc(day(db), { updatedBy: PARENT }, { merge: true }));
});

test("child cannot delete its day (would reset minutes and the lock)", async () => {
  await seed();
  await assertFails(deleteDoc(day(as(KID1))));
  await assertSucceeds(deleteDoc(day(as(PARENT))));
});

test("child cannot end the prayer lock inside the window, can after it", async () => {
  await seed({ lockMinutesAgo: 5 });
  await assertFails(setDoc(day(as(KID1)), { prayerLock: false }, { merge: true }));
  await seed({ lockMinutesAgo: 30 });
  await assertSucceeds(setDoc(day(as(KID1)), { prayerLock: false }, { merge: true }));
});

test("child can start a prayer lock only with the server time", async () => {
  await seed({ prayerLock: false });
  await assertFails(setDoc(day(as(KID1)), { prayerLock: true, prayerLockAt: Timestamp.fromMillis(Date.now() - 3600_000) }, { merge: true }));
  await assertFails(setDoc(day(as(KID1)), { prayerLock: true }, { merge: true }));
  // The device-clock start is not synced any more: a back-dated value could shorten the lock.
  await assertFails(setDoc(day(as(KID1)), { prayerLock: true, prayerLockAt: serverTimestamp(), prayerLockSinceMs: 0 }, { merge: true }));
  await assertSucceeds(setDoc(day(as(KID1)), { prayerLock: true, prayerLockAt: serverTimestamp() }, { merge: true }));
  // Re-stamping an existing lock with an old time is refused too.
  await assertFails(setDoc(day(as(KID1)), { prayerLockAt: Timestamp.fromMillis(0) }, { merge: true }));
});

test("child creates a new day without server-only fields only", async () => {
  await seed();
  const db = as(KID1);
  await assertFails(setDoc(day(db, "c1", "2026-11-23"), { day: "2026-11-23", earnedMinutes: 60 }));
  await assertFails(setDoc(day(db, "c1", "2026-11-23"), { day: "2026-11-23", approved: {} }));
  await assertFails(setDoc(day(db, "c1", "2026-11-23"), { day: "2026-11-24", usedMinutes: 0 })); // wrong day id
  await assertSucceeds(setDoc(day(db, "c1", "2026-11-23"), { day: "2026-11-23", progress: {}, usedMinutes: 0 }));
});

test("child cannot read or write another child's docs", async () => {
  await seed();
  const db = as(KID1);
  await assertFails(getDoc(day(db, "c2")));
  await assertFails(setDoc(day(db, "c2"), { progress: { x: { status: "pending", count: 0 } } }, { merge: true }));
  await assertFails(setDoc(day(db, "c2", "2026-11-23"), { day: "2026-11-23" }));
  await assertFails(setDoc(doc(db, "families/f1/children/c2"), { nickname: "x", avatar: "moon" }));
  await assertSucceeds(getDoc(day(db, "c1")));
});

// ---- R-33: family settings are parent-only ---------------------------------------------------

test("child cannot write family settings; parent can", async () => {
  await seed();
  await assertFails(setDoc(doc(as(KID1), "families/f1"), { settings: { lockAtAdhan: false } }, { merge: true }));
  await assertFails(updateDoc(doc(as(KID1), "families/f1"), { "settings.games": [] }));
  await assertSucceeds(getDoc(doc(as(KID1), "families/f1"))); // child devices still read the plan
  await assertSucceeds(setDoc(doc(as(PARENT), "families/f1"), { settings: { lockAtAdhan: false } }, { merge: true }));
  await assertSucceeds(updateDoc(doc(as(PARENT2), "families/f1"), { "settings.games": [] }));
});

test("nobody writes server-only family fields from a client", async () => {
  await seed();
  for (const uid of [PARENT, KID1]) {
    await assertFails(setDoc(doc(as(uid), "families/f1"), { plan: "plus" }, { merge: true }));
    await assertFails(setDoc(doc(as(uid), "families/f1"), { childDevices: {} }, { merge: true }));
  }
});

test("per-app plans (plans.<app>, planApp) are server-only (Zad X Kids / Zad X Play entitlements)", async () => {
  await seed();
  for (const uid of [PARENT, PARENT2, KID1]) {
    const fam = doc(as(uid), "families/f1");
    await assertFails(setDoc(fam, { plans: { play: { plan: "plus", planExpiresAt: "2099-01-01T00:00:00Z", inTrial: false } } }, { merge: true }));
    await assertFails(setDoc(fam, { plans: { kids: { plan: "plus" } } }, { merge: true }));
    await assertFails(updateDoc(fam, { "plans.kids.plan": "plus" }));
    await assertFails(setDoc(fam, { planApp: "kids" }, { merge: true }));
    await assertFails(updateDoc(fam, { planApp: "play" }));
  }
  // A new family cannot be created with an entitlement either.
  await assertFails(setDoc(doc(as(STRANGER), "families/f2"), { members: [STRANGER], plans: { play: { plan: "plus" } } }));
  await assertFails(setDoc(doc(as(STRANGER), "families/f3"), { members: [STRANGER], planApp: "play" }));
  await assertSucceeds(setDoc(doc(as(STRANGER), "families/f4"), { members: [STRANGER] }));
});

test("family create is idempotent (FirestoreFamilyRepository.createFamily, retried by FamilyBootstrap)", async () => {
  await env.clearFirestore();
  const NEW = "newPhoneUid";
  const fam = doc(as(NEW), "families/local-id-1");
  const create = () => setDoc(fam, { members: arrayUnion(NEW) }, { merge: true });
  await assertSucceeds(create()); // first write: a create with members == [uid]
  await assertSucceeds(create()); // retry after a timeout that did land: no change
  let members;
  await env.withSecurityRulesDisabled(async (ctx) => {
    members = (await getDoc(doc(ctx.firestore(), "families/local-id-1"))).get("members");
  });
  assert.deepEqual(members, [NEW]);
  // The same call cannot add a device to someone else's family.
  await seed();
  await assertFails(setDoc(doc(as(STRANGER), "families/f1"), { members: arrayUnion(STRANGER) }, { merge: true }));
});

test("family create stamps createdAt with server time only; a retry falls back to members (Free = one child)", async () => {
  await env.clearFirestore();
  const NEW = "newPhoneUid";
  const fam = doc(as(NEW), "families/local-id-2");
  // A client cannot backdate createdAt to stretch the server's 7-day family trial.
  await assertFails(setDoc(fam, { members: arrayUnion(NEW), createdAt: Timestamp.fromMillis(Date.now() + 30 * 86_400_000) }, { merge: true }));
  await assertSucceeds(setDoc(fam, { members: arrayUnion(NEW), createdAt: serverTimestamp() }, { merge: true }));
  // createFamily retry after a write that did land: createdAt is server-only now ...
  await assertFails(setDoc(fam, { members: arrayUnion(NEW), createdAt: serverTimestamp() }, { merge: true }));
  // ... so it falls back to the plain members write, which still succeeds.
  await assertSucceeds(setDoc(fam, { members: arrayUnion(NEW) }, { merge: true }));
  // freeChildId: a parent device may pick only child-1 or an existing child (freeChildOk).
  await assertFails(setDoc(fam, { freeChildId: "c2" }, { merge: true }));
});

// ---- parents ---------------------------------------------------------------------------------

test("parent manages the day but cannot credit minutes outside approveTask", async () => {
  await seed();
  const db = as(PARENT);
  await assertSucceeds(setDoc(day(db), { prayerLock: false }, { merge: true }));
  await assertSucceeds(setDoc(day(db), { progress: { homework: { status: "todo", count: 0 } }, usedMinutes: 0 }, { merge: true }));
  await assertSucceeds(getDoc(day(db, "c2")));
  await assertFails(setDoc(day(db), { approved: { homework: 20 } }, { merge: true }));
  await assertFails(setDoc(day(db), { earnedMinutes: 600 }, { merge: true }));
  await assertFails(setDoc(day(db, "c2", "2026-11-23"), { day: "2026-11-23", requiredDone: true }));
});

test("strangers get nothing", async () => {
  await seed();
  const db = as(STRANGER);
  await assertFails(getDoc(day(db)));
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(setDoc(day(db), { progress: {} }, { merge: true }));
  assert.ok(true);
});

test("prayerLockSinceMs is not writable by any client (lock window counts from server prayerLockAt)", async () => {
  await seed({ lockMinutesAgo: 5 });
  // A child cannot back-date the lock start, on its own or together with ending the lock.
  await assertFails(setDoc(day(as(KID1)), { prayerLockSinceMs: 0 }, { merge: true }));
  await assertFails(setDoc(day(as(KID1)), { prayerLock: false, prayerLockSinceMs: 0 }, { merge: true }));
  await assertFails(setDoc(day(as(KID1), "c1", "2026-11-23"), { day: "2026-11-23", prayerLockSinceMs: 0 }));
  // Parents do not write it either (the app never sends it).
  await assertFails(setDoc(day(as(PARENT)), { prayerLockSinceMs: 0 }, { merge: true }));
});

// ---- Removed feature: the "excused" prayer pause (owner decision 2026-11-22) -----------------

test("prayerPaused (removed excused pause) is not writable by any client", async () => {
  await seed({ lockMinutesAgo: 1 });
  // Child devices cannot set it, alone or with other fields, on an existing or a new day.
  await assertFails(setDoc(day(as(KID1)), { prayerPaused: true }, { merge: true }));
  await assertFails(setDoc(day(as(KID1)), { prayerPaused: true, prayerLock: false }, { merge: true }));
  await assertFails(setDoc(day(as(KID1), "c1", "2026-11-23"), { day: "2026-11-23", prayerPaused: true }));
  // Parent devices cannot set, change or create it either.
  await assertFails(setDoc(day(as(PARENT)), { prayerPaused: true }, { merge: true }));
  await assertFails(setDoc(day(as(PARENT2)), { prayerPaused: false }, { merge: true }));
  await assertFails(setDoc(day(as(PARENT)), { day: DAY, prayerPaused: true, prayerLock: false }, { merge: true }));
  await assertFails(setDoc(day(as(PARENT), "c1", "2026-11-23"), { day: "2026-11-23", prayerPaused: false }));
  // Normal day writes keep working for parents and the child device.
  await assertSucceeds(setDoc(day(as(PARENT)), { prayerLock: false }, { merge: true }));
  await assertSucceeds(setDoc(day(as(KID1)), { progress: { homework: { status: "pending", count: 0 } } }, { merge: true }));
});

test("a legacy prayerPaused value does not block normal writes, and cannot be changed", async () => {
  await seed({ lockMinutesAgo: 1 });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `families/f1/children/c1/days/${DAY}`), { prayerPaused: true }, { merge: true });
  });
  await assertSucceeds(setDoc(day(as(PARENT)), { prayerLock: false }, { merge: true }));
  await assertSucceeds(setDoc(day(as(KID1)), { usedMinutes: increment(1) }, { merge: true }));
  await assertFails(setDoc(day(as(PARENT)), { prayerPaused: false }, { merge: true }));
  await assertFails(setDoc(day(as(KID1)), { prayerPaused: false }, { merge: true }));
});

// ---- Who may do what: child device vs parent vs stranger vs signed out ------------------------
// (Replaces the manual Rules Playground cases that PR #36 listed in backend/README.md.)

/** Server-side snapshot of c1's day (rules off), to prove a refused write changed nothing. */
async function serverDay(child = "c1", d = DAY) {
  let data;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), `families/f1/children/${child}/days/${d}`))).data();
  });
  return data;
}

test("child device: allowed day writes (pending request, more play time, start a prayer lock)", async () => {
  await seed({ prayerLock: false });
  const db = as(KID1);
  await assertSucceeds(setDoc(day(db), {
    day: DAY, progress: { prayer: { status: "pending", count: 0 } }, updatedAt: serverTimestamp(), updatedBy: KID1,
  }, { merge: true }));
  await assertSucceeds(setDoc(day(db), { progress: { room: { status: "todo", count: 0 } } }, { merge: true }));
  await assertSucceeds(setDoc(day(db), { usedMinutes: increment(5) }, { merge: true }));
  await assertSucceeds(setDoc(day(db), { prayerLock: true, prayerLockAt: serverTimestamp() }, { merge: true }));
  const after = await serverDay();
  assert.equal(after.usedMinutes, 15);
  assert.equal(after.prayerLock, true);
  assert.equal(after.progress.prayer.status, "pending");
});

test("child device: a self-written \"done\" status credits nothing (credits are server-only)", async () => {
  await seed();
  const db = as(KID1);
  // Status is only a request marker in the server-approvals model; credits live in `approved`.
  await assertSucceeds(setDoc(day(db), { progress: { homework: { status: "done", count: 1 } } }, { merge: true }));
  // ...but no way to turn it into minutes, a finished required list, or an approval.
  await assertFails(setDoc(day(db), { progress: { homework: { status: "done", count: 1 } }, approved: { homework: 20 } }, { merge: true }));
  await assertFails(setDoc(day(db), { progress: { homework: { status: "done", count: 1 } }, earnedMinutes: 30 }, { merge: true }));
  await assertFails(setDoc(day(db), { progress: { homework: { status: "done", count: 1 } }, requiredDone: true }, { merge: true }));
  await assertFails(updateDoc(day(db), { approved: {} }));
  const after = await serverDay();
  assert.deepEqual(after.approved, { prayer: 10 });
  assert.equal(after.earnedMinutes, 10);
  assert.equal(after.requiredDone, false);
});

test("child device: cannot write the family doc at all (any field, delete)", async () => {
  await seed();
  const fam = doc(as(KID1), "families/f1");
  await assertFails(setDoc(fam, { settings: { lockAtAdhan: false } }, { merge: true }));
  await assertFails(updateDoc(fam, { "settings.lockAtAdhan": false }));
  await assertFails(updateDoc(fam, { "settings.timeZone": "Pacific/Kiritimati" }));
  await assertFails(setDoc(fam, { someField: 1 }, { merge: true }));
  await assertFails(updateDoc(fam, { settings: {} }));
  await assertFails(deleteDoc(fam));
});

test("child device: cannot create, change or delete child profiles (own or sibling)", async () => {
  await seed();
  const db = as(KID1);
  await assertFails(setDoc(doc(db, "families/f1/children/c1"), { nickname: "Boss", avatar: "moon" }));
  await assertFails(updateDoc(doc(db, "families/f1/children/c1"), { nickname: "Boss" }));
  await assertFails(deleteDoc(doc(db, "families/f1/children/c1")));
  await assertFails(setDoc(doc(db, "families/f1/children/c9"), { nickname: "New", avatar: "moon" }));
  await assertFails(getDoc(doc(db, "families/f1/children/c2")));
  await assertSucceeds(getDoc(doc(db, "families/f1/children/c1")));
});

test("child device: cannot delete any day, its own or a sibling's", async () => {
  await seed();
  await assertFails(deleteDoc(day(as(KID1))));
  await assertFails(deleteDoc(day(as(KID1), "c2")));
  assert.ok(await serverDay());
});

test("parent device: approvals stay with approveTask, everything else is allowed", async () => {
  await seed({ lockMinutesAgo: 1 });
  const db = as(PARENT2); // a second parent phone is a parent too
  // Ends a prayer lock inside the window (a child cannot).
  await assertSucceeds(setDoc(day(db), { prayerLock: false }, { merge: true }));
  // Sets a task back to todo / marks it done on its own device.
  await assertSucceeds(setDoc(day(db), { progress: { homework: { status: "done", count: 1 } } }, { merge: true }));
  // Creates a day and manages child profiles (nickname + avatar only, COPPA).
  await assertSucceeds(setDoc(day(db, "c2", "2026-11-23"), { day: "2026-11-23", progress: {}, usedMinutes: 0 }));
  await assertSucceeds(setDoc(doc(db, "families/f1/children/c3"), { nickname: "Maryam", avatar: "star" }));
  await assertFails(setDoc(doc(db, "families/f1/children/c4"), { nickname: "Ali", avatar: "star", birthday: "2019-01-01" }));
  await assertFails(setDoc(doc(db, "families/f1/children/c4"), { nickname: "Ali", avatar: "star", school: "X" }));
  await assertSucceeds(deleteDoc(doc(db, "families/f1/children/c3")));
  // Changes family settings and deletes a day.
  await assertSucceeds(updateDoc(doc(db, "families/f1"), { "settings.lockAtAdhan": false }));
  await assertSucceeds(deleteDoc(day(db, "c2")));
  // Credits only through the approveTask Cloud Function (admin SDK), never a client write.
  await assertFails(setDoc(day(db), { earnedMinutes: 20 }, { merge: true }));
  await assertFails(setDoc(day(db), { requiredDone: true }, { merge: true }));
  await assertFails(setDoc(day(db), { approved: { homework: 20 } }, { merge: true }));
});

test("unrelated signed-in user: reads and writes nothing in the family", async () => {
  await seed();
  const db = as(STRANGER);
  // Reads.
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(getDoc(doc(db, "families/f1/children/c1")));
  await assertFails(getDocs(collection(db, "families/f1/children")));
  await assertFails(getDoc(day(db)));
  await assertFails(getDocs(collection(db, "families/f1/children/c1/days")));
  await assertFails(getDoc(doc(db, "families/f1/assistantUsage/" + DAY)));
  // Writes.
  await assertFails(setDoc(doc(db, "families/f1"), { settings: { lockAtAdhan: false } }, { merge: true }));
  await assertFails(updateDoc(doc(db, "families/f1"), { members: arrayUnion(STRANGER) }));
  await assertFails(deleteDoc(doc(db, "families/f1")));
  await assertFails(setDoc(doc(db, "families/f1/children/c9"), { nickname: "x", avatar: "moon" }));
  await assertFails(updateDoc(doc(db, "families/f1/children/c1"), { nickname: "x" }));
  await assertFails(deleteDoc(doc(db, "families/f1/children/c1")));
  await assertFails(setDoc(day(db), { usedMinutes: increment(1) }, { merge: true }));
  await assertFails(setDoc(day(db, "c1", "2026-11-23"), { day: "2026-11-23" }));
  await assertFails(deleteDoc(day(db)));
  // Cannot plant a family that lists someone else, or binds a device.
  await assertFails(setDoc(doc(db, "families/f9"), { members: [STRANGER, PARENT] }));
  await assertFails(setDoc(doc(db, "families/f9"), { members: [PARENT] }));
  await assertFails(setDoc(doc(db, "families/f9"), { members: [STRANGER], childDevices: { [STRANGER]: "c1" } }));
  await assertFails(setDoc(doc(db, "families/f9"), { members: [STRANGER], parentDevices: { [STRANGER]: 1 } }));
});

test("a device bound in childDevices but no longer a member gets nothing", async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "families/f1"), { members: [PARENT, PARENT2, KID2] });
  });
  const db = as(KID1);
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(getDoc(day(db)));
  await assertFails(setDoc(day(db), { progress: { homework: { status: "pending", count: 0 } } }, { merge: true }));
});

/** The family doc exactly as removeLinkedDevice (admin SDK) leaves it after removing [uid]. */
async function removeAsFunctionWould(uid) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(
      doc(ctx.firestore(), "families/f1"),
      new FieldPath("members"), arrayRemove(uid),
      new FieldPath("childDevices", uid), deleteField(),
      new FieldPath("parentDevices", uid), deleteField(),
    );
  });
}

test("P1-3: a removed child device is denied every family read and write", async () => {
  await seed();
  await assertSucceeds(getDoc(day(as(KID1)))); // before removal
  await removeAsFunctionWould(KID1);
  const db = as(KID1);
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(getDoc(doc(db, "families/f1/children/c1")));
  await assertFails(getDoc(day(db)));
  await assertFails(getDocs(collection(db, "families/f1/children/c1/days")));
  await assertFails(getDoc(doc(db, "families/f1/assistantUsage/" + DAY)));
  await assertFails(setDoc(day(db), { progress: { homework: { status: "pending", count: 0 } } }, { merge: true }));
  await assertFails(setDoc(day(db), { usedMinutes: increment(1) }, { merge: true }));
  // It cannot put itself back.
  await assertFails(setDoc(doc(db, "families/f1"), { members: arrayUnion(KID1) }, { merge: true }));
  await assertFails(updateDoc(doc(db, "families/f1"), { [`childDevices.${KID1}`]: "c1" }));
  // The other devices keep working.
  await assertSucceeds(getDoc(day(as(KID2), "c2")));
  await assertSucceeds(getDoc(doc(as(PARENT), "families/f1")));
});

test("P1-3: a removed parent phone loses parent access too", async () => {
  await seed();
  await removeAsFunctionWould(PARENT2);
  const db = as(PARENT2);
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(getDocs(collection(db, "families/f1/children")));
  await assertFails(setDoc(doc(db, "families/f1"), { settings: { lockAtAdhan: false } }, { merge: true }));
  await assertFails(setDoc(doc(db, "families/f1/children/c9"), { nickname: "x", avatar: "moon" }));
  await assertFails(deleteDoc(day(db)));
  await assertFails(updateDoc(doc(db, "families/f1"), { members: arrayUnion(PARENT2), [`parentDevices.${PARENT2}`]: 1 }));
});

test("P1-3: no client removes a member directly (only removeLinkedDevice does)", async () => {
  await seed();
  for (const uid of [PARENT, PARENT2, KID1]) {
    const db = as(uid);
    const fam = doc(db, "families/f1");
    await assertFails(updateDoc(fam, { members: arrayRemove(KID2) }), `${uid} arrayRemove`);
    await assertFails(updateDoc(fam, { members: [PARENT, PARENT2, KID1] }), `${uid} overwrite`);
    await assertFails(updateDoc(fam, { [`childDevices.${KID2}`]: deleteField() }), `${uid} unbind`);
    await assertFails(updateDoc(fam, { [`parentDevices.${PARENT2}`]: deleteField() }), `${uid} parentDevices`);
    // The audit trail is server-only.
    await assertFails(getDoc(doc(db, "families/f1/audit/a1")), `${uid} read audit`);
    await assertFails(setDoc(doc(db, "families/f1/audit/a1"), { action: "device_removed" }), `${uid} write audit`);
  }
});

test("signed out: denied everywhere", async () => {
  await seed();
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(getDoc(doc(db, "families/f1/children/c1")));
  await assertFails(getDoc(day(db)));
  await assertFails(setDoc(day(db), { usedMinutes: increment(1) }, { merge: true }));
  await assertFails(setDoc(doc(db, "families/f9"), { members: [] }));
  await assertFails(setDoc(doc(db, "families/f9"), { members: [null] }));
  await assertFails(updateDoc(doc(db, "families/f1"), { "settings.lockAtAdhan": false }));
  await assertFails(getDoc(doc(db, "pairingCodes/123456")));
});

test("server-only collections are closed to every client (parent included)", async () => {
  await seed();
  const paths = [
    "families/f1/devices/d1", "families/f1/private/billing", "families/f1/assistantUsage/" + DAY, "families/f1/audit/a1",
    "purchases/h1", "pairingCodes/123456", "referralCodes/ABC", "deviceHeartbeats/h1", "rateLimits/k1",
    "families/f1/children/c1/secret/x", "somethingElse/x",
  ];
  for (const uid of [PARENT, KID1, STRANGER]) {
    const db = as(uid);
    for (const p of paths) {
      await assertFails(setDoc(doc(db, p), { x: 1 }), `${uid} write ${p}`);
      if (!p.includes("assistantUsage")) await assertFails(getDoc(doc(db, p)), `${uid} read ${p}`);
    }
  }
  // assistantUsage is readable by family members only.
  await assertSucceeds(getDoc(doc(as(PARENT), "families/f1/assistantUsage/" + DAY)));
  await assertFails(getDoc(doc(as(STRANGER), "families/f1/assistantUsage/" + DAY)));
});

// =============================================================================================
// Zero-cost family core (Spark plan, no Cloud Functions; docs/ZERO-COST-BACKEND.md). The client
// writes that replaced createPairingCode / redeemPairingCode / removeLinkedDevice /
// checkDeviceMembership / approveTask / rejectTask / setFreeChild, and what the rules refuse.
// =============================================================================================

const NEWKID = "newKidDeviceUid";
const NEWPARENT = "newParentPhoneUid";
const GUARD = "windowsGuardUid";
/** Same doc id as lib/services/family/pairing_code.dart PairingCode.docId. */
const codeId = (code) => createHash("sha256").update(`zadx-pair-v1:${code}`).digest("hex");

/** A code doc as a parent phone of f1 writes it (rules off, so tests can back-date it). */
async function seedCode(code, data, { minutesAgo = 1 } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `pairingCodes/${codeId(code)}`), {
      familyId: "f1", createdBy: PARENT, createdAt: Timestamp.fromMillis(Date.now() - minutesAgo * 60_000), ...data,
    });
  });
}

/** PairingService.redeem: join f1 + delete the code in one commit. */
function joinBatch(db, code, uid, { role = "child", childId = "c1", deleteCode = true, opUid = uid, family = "f1" } = {}) {
  const b = writeBatch(db);
  b.update(
    doc(db, `families/${family}`),
    new FieldPath("members"), arrayUnion(uid),
    ...(role === "parent"
      ? [new FieldPath("parentDevices", uid), serverTimestamp()]
      : [new FieldPath("childDevices", uid), childId]),
    new FieldPath("memberOp"), { op: "join", uid: opUid, code: codeId(code), at: serverTimestamp() },
  );
  if (deleteCode) b.delete(doc(db, `pairingCodes/${codeId(code)}`));
  return b.commit();
}

async function familyData() {
  let data;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), "families/f1"))).data();
  });
  return data;
}

async function exists(path) {
  let found;
  await env.withSecurityRulesDisabled(async (ctx) => {
    found = (await getDoc(doc(ctx.firestore(), path))).exists();
  });
  return found;
}

// ---- Pairing codes ---------------------------------------------------------------------------

test("pairing: only a parent device creates a code, with fixed fields and server time", async () => {
  await seed();
  const ref = (db, code) => doc(db, `pairingCodes/${codeId(code)}`);
  const phone = (uid, extra = {}) => ({
    familyId: "f1", target: "phone", childId: "c1", createdBy: uid, createdAt: serverTimestamp(), ...extra,
  });
  await assertSucceeds(setDoc(ref(as(PARENT), "PHONE22222"), phone(PARENT)));
  await assertSucceeds(setDoc(ref(as(PARENT2), "PARNT22222"), { familyId: "f1", target: "parent", createdBy: PARENT2, createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(ref(as(PARENT), "WINDS22222"), phone(PARENT, { target: "windows", childId: "c2" })));
  // A child device or a stranger never creates one.
  await assertFails(setDoc(ref(as(KID1), "KIDXX22222"), phone(KID1)));
  await assertFails(setDoc(ref(as(STRANGER), "STRNG22222"), phone(STRANGER)));
  // Fixed shape.
  await assertFails(setDoc(ref(as(PARENT), "OLDXX22222"), phone(PARENT, { createdAt: Timestamp.fromMillis(Date.now() + 3600_000) })));
  await assertFails(setDoc(ref(as(PARENT), "NOKID22222"), phone(PARENT, { childId: "c9" }))); // no such child
  await assertFails(setDoc(ref(as(PARENT), "PRKID22222"), phone(PARENT, { target: "parent" }))); // parent code + child
  await assertFails(setDoc(ref(as(PARENT), "ADMIN22222"), phone(PARENT, { target: "admin" })));
  await assertFails(setDoc(ref(as(PARENT), "EXTRA22222"), phone(PARENT, { plan: "plus" })));
  await assertFails(setDoc(ref(as(PARENT), "OTHER22222"), phone(PARENT2)));
  await assertFails(setDoc(doc(as(PARENT), "pairingCodes/123456"), phone(PARENT))); // id must be a sha256
  // Never overwritten once written.
  await assertFails(setDoc(ref(as(PARENT), "PHONE22222"), phone(PARENT)));
  // The creator may withdraw its own code; nobody else may.
  await assertFails(deleteDoc(ref(as(PARENT2), "PHONE22222")));
  await assertFails(deleteDoc(ref(as(STRANGER), "PHONE22222")));
  await assertSucceeds(deleteDoc(ref(as(PARENT), "PHONE22222")));
});

test("pairing: a code is read by its id only while live; no listing; missing = expired = denied", async () => {
  await seed();
  await seedCode("LIVEX22222", { target: "phone", childId: "c1" });
  await seedCode("STALE22222", { target: "phone", childId: "c1" }, { minutesAgo: 11 });
  await assertSucceeds(getDoc(doc(as(NEWKID), `pairingCodes/${codeId("LIVEX22222")}`)));
  await assertFails(getDoc(doc(as(NEWKID), `pairingCodes/${codeId("STALE22222")}`)));
  await assertFails(getDoc(doc(as(NEWKID), `pairingCodes/${codeId("NOPEX22222")}`)));
  await assertFails(getDocs(collection(as(NEWKID), "pairingCodes")));
  await assertFails(getDocs(collection(as(PARENT), "pairingCodes")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `pairingCodes/${codeId("LIVEX22222")}`)));
});

test("pairing: a child phone joins only itself, only as the code's child, and uses the code up", async () => {
  await seed();
  await seedCode("CHILD22222", { target: "phone", childId: "c2" });
  const db = as(NEWKID);
  await assertFails(joinBatch(db, "CHILD22222", NEWKID, { childId: "c1" })); // not the code's child
  await assertFails(joinBatch(db, "CHILD22222", NEWKID, { role: "parent" })); // not the code's role
  await assertFails(joinBatch(db, "CHILD22222", NEWKID, { childId: "c2", deleteCode: false })); // must use it up
  await assertFails(joinBatch(db, "CHILD22222", STRANGER, { childId: "c2", opUid: NEWKID })); // adds someone else
  await assertFails(updateDoc(doc(db, "families/f1"), { members: arrayUnion(NEWKID), [`childDevices.${NEWKID}`]: "c2" })); // no code
  await assertFails(joinBatch(db, "WRONG22222", NEWKID, { childId: "c2" })); // unknown code
  await assertSucceeds(joinBatch(db, "CHILD22222", NEWKID, { childId: "c2" }));

  const fam = await familyData();
  assert.deepEqual(fam.members, [PARENT, PARENT2, KID1, KID2, NEWKID]);
  assert.equal(fam.childDevices[NEWKID], "c2");
  assert.equal(fam.parentDevices[NEWKID], undefined);
  assert.equal(await exists(`pairingCodes/${codeId("CHILD22222")}`), false);
  // A child device: its own child only, no family writes.
  await assertSucceeds(getDoc(day(db, "c2")));
  await assertFails(getDoc(day(db, "c1")));
  await assertFails(updateDoc(doc(db, "families/f1"), { "settings.lockAtAdhan": false }));
  // Single use: the same code never works again.
  await assertFails(joinBatch(as(STRANGER), "CHILD22222", STRANGER, { childId: "c2" }));
});

test("pairing: expired codes, codes of a removed parent and codes of another family are refused", async () => {
  await seed();
  await seedCode("EXPRD22222", { target: "phone", childId: "c1" }, { minutesAgo: 11 });
  await assertFails(joinBatch(as(NEWKID), "EXPRD22222", NEWKID));
  await seedCode("GONEX22222", { target: "phone", childId: "c1", createdBy: "removedParentUid" });
  await assertFails(joinBatch(as(NEWKID), "GONEX22222", NEWKID));
  await seedCode("BYKID22222", { target: "phone", childId: "c1", createdBy: KID1 });
  await assertFails(joinBatch(as(NEWKID), "BYKID22222", NEWKID));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "families/f2"), { members: ["otherParent"] });
  });
  await seedCode("FAMF222222", { target: "phone", childId: "c1", familyId: "f2", createdBy: "otherParent" });
  await assertFails(joinBatch(as(NEWKID), "FAMF222222", NEWKID)); // f2's code used on f1
  await seedCode("WINDS33333", { target: "windows", childId: "c1" });
  await assertFails(joinBatch(as(NEWKID), "WINDS33333", NEWKID)); // a phone never redeems a windows code
  assert.deepEqual((await familyData()).members, [PARENT, PARENT2, KID1, KID2]);
});

test("pairing: a parent code adds a PARENT phone; an existing member cannot redeem codes", async () => {
  await seed();
  await seedCode("PRNTX22222", { target: "parent" });
  await assertFails(joinBatch(as(NEWPARENT), "PRNTX22222", NEWPARENT, { role: "child", childId: "c1" }));
  // A child device of the family cannot turn itself into a parent with a parent code.
  await assertFails(joinBatch(as(KID1), "PRNTX22222", KID1, { role: "parent" }));
  await assertSucceeds(joinBatch(as(NEWPARENT), "PRNTX22222", NEWPARENT, { role: "parent" }));
  const fam = await familyData();
  assert.ok(fam.members.includes(NEWPARENT));
  assert.equal(typeof fam.parentDevices[NEWPARENT]?.toMillis, "function"); // server time
  assert.equal(fam.childDevices[NEWPARENT], undefined);
  await assertSucceeds(updateDoc(doc(as(NEWPARENT), "families/f1"), { "settings.lockAtAdhan": false }));
  // A member (parent or child device) cannot redeem a phone code to re-bind itself.
  await seedCode("REBND22222", { target: "phone", childId: "c2" });
  await assertFails(joinBatch(as(KID1), "REBND22222", KID1, { childId: "c2" }));
  await assertFails(joinBatch(as(PARENT2), "REBND22222", PARENT2, { childId: "c2" }));
});

test("pairing: Zad X Guard registers itself with a windows code (devices/{its uid}), single use", async () => {
  await seed();
  await seedCode("GUARD22222", { target: "windows", childId: "c1" });
  const guard = (db, uid, code, extra = {}) => {
    const b = writeBatch(db);
    b.set(doc(db, `families/f1/devices/${uid}`), {
      type: "windows", childId: "c1", name: "Family PC", code: codeId(code), createdAt: serverTimestamp(), ...extra,
    });
    b.delete(doc(db, `pairingCodes/${codeId(code)}`));
    return b.commit();
  };
  const db = as(GUARD);
  await assertFails(guard(db, "someOtherUid", "GUARD22222")); // only devices/{own uid}
  await assertFails(guard(db, GUARD, "GUARD22222", { childId: "c2" })); // not the code's child
  await assertFails(guard(db, GUARD, "GUARD22222", { secretHash: "x" }));
  await assertSucceeds(guard(db, GUARD, "GUARD22222"));
  await assertSucceeds(getDoc(doc(db, `families/f1/devices/${GUARD}`)));
  await assertFails(getDoc(doc(as(KID1), `families/f1/devices/${GUARD}`)));
  await assertFails(updateDoc(doc(db, `families/f1/devices/${GUARD}`), { childId: "c2" }));
  // A guard is not a family member: no family reads.
  await assertFails(getDoc(doc(db, "families/f1")));
  await assertFails(guard(as("secondGuardUid"), "secondGuardUid", "GUARD22222")); // used up
});

// ---- Device removal (removeLinkedDevice / checkDeviceMembership replacement) -----------------

/** FirestoreFamilyRepository.removeLinkedDevice: one commit with the marker and the audit entry. */
function removeBatch(db, by, x, { audit = true, marker = true, role = "child", auditId = `a-${x}`, also = [] } = {}) {
  const b = writeBatch(db);
  b.update(
    doc(db, "families/f1"),
    new FieldPath("members"), arrayRemove(x, ...also),
    new FieldPath("childDevices", x), deleteField(),
    new FieldPath("parentDevices", x), deleteField(),
    new FieldPath("memberOp"), { op: "remove", uid: x, by, at: serverTimestamp(), audit: auditId },
  );
  if (marker) b.set(doc(db, `families/f1/removedDevices/${x}`), { removedAt: serverTimestamp() });
  if (audit) {
    b.set(doc(db, `families/f1/audit/${auditId}`), {
      action: "device_removed", byUid: by, targetUid: x, targetRole: role, at: serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 365 * 86_400_000),
    });
  }
  return b.commit();
}

test("removal: a parent removes a child device with marker + audit in one commit", async () => {
  await seed();
  const db = as(PARENT);
  await assertFails(removeBatch(db, PARENT, KID1, { audit: false }));
  await assertFails(removeBatch(db, PARENT, KID1, { marker: false }));
  await assertFails(removeBatch(db, PARENT, KID1, { role: "parent" })); // audit must state the real role
  await assertFails(removeBatch(db, PARENT, KID1, { also: [KID2] })); // one device per commit
  await assertFails(removeBatch(db, KID2, KID1)); // "by" must be the caller
  await assertSucceeds(removeBatch(db, PARENT, KID1));

  const fam = await familyData();
  assert.deepEqual(fam.members, [PARENT, PARENT2, KID2]);
  assert.equal(fam.childDevices[KID1], undefined);
  assert.equal(fam.childDevices[KID2], "c2");
  // The removed device: no family access, but an explicit answer about ITSELF.
  const kid = as(KID1);
  await assertFails(getDoc(doc(kid, "families/f1")));
  await assertFails(getDoc(day(kid)));
  await assertSucceeds(getDoc(doc(kid, `families/f1/removedDevices/${KID1}`)));
  assert.equal((await getDoc(doc(kid, `families/f1/removedDevices/${KID1}`))).exists(), true);
  // Markers are private to their uid and never listed.
  await assertFails(getDoc(doc(as(KID2), `families/f1/removedDevices/${KID1}`)));
  await assertFails(getDocs(collection(kid, "families/f1/removedDevices")));
  // A member that was never removed reads "no marker" (stays unknown in the app, never a reset).
  assert.equal((await getDoc(doc(as(KID2), `families/f1/removedDevices/${KID2}`))).exists(), false);
  // The removed device cannot put itself back.
  await assertFails(updateDoc(doc(kid, "families/f1"), { members: arrayUnion(KID1), [`childDevices.${KID1}`]: "c1" }));
});

test("removal: only parent devices remove, never the last parent, strangers never", async () => {
  await seed();
  await assertFails(removeBatch(as(KID1), KID1, KID2)); // a child device removes nobody
  await assertFails(removeBatch(as(KID1), KID1, KID1)); // not even itself
  await assertFails(removeBatch(as(STRANGER), STRANGER, KID1));
  await assertFails(removeBatch(as(PARENT), PARENT, STRANGER)); // not a member
  // A parent removes another parent phone; then the last parent cannot remove itself.
  await assertSucceeds(removeBatch(as(PARENT), PARENT, PARENT2, { role: "parent" }));
  await assertFails(removeBatch(as(PARENT), PARENT, PARENT, { role: "parent" }));
  assert.deepEqual((await familyData()).members, [PARENT, KID1, KID2]);
  // The removed parent phone lost parent access, and its unused codes stopped working.
  await assertFails(updateDoc(doc(as(PARENT2), "families/f1"), { "settings.lockAtAdhan": false }));
  await seedCode("P2CODE2222", { target: "phone", childId: "c1", createdBy: PARENT2 });
  await assertFails(joinBatch(as(NEWKID), "P2CODE2222", NEWKID));
});

test("removal: a parent may remove itself while another parent remains", async () => {
  await seed();
  await assertSucceeds(removeBatch(as(PARENT2), PARENT2, PARENT2, { role: "parent" }));
  assert.deepEqual((await familyData()).members, [PARENT, KID1, KID2]);
});

test("removal: markers and audit entries cannot be forged, read, changed or deleted", async () => {
  await seed();
  const db = as(PARENT);
  // A marker without a real removal in the same commit.
  await assertFails(setDoc(doc(db, `families/f1/removedDevices/${KID2}`), { removedAt: serverTimestamp() }));
  // An audit entry without a removal.
  await assertFails(setDoc(doc(db, "families/f1/audit/x1"), {
    action: "device_removed", byUid: PARENT, targetUid: KID2, targetRole: "child", at: serverTimestamp(),
  }));
  await assertSucceeds(removeBatch(db, PARENT, KID1));
  // Append-only: nobody reads, rewrites or deletes it from a client.
  for (const uid of [PARENT, PARENT2, KID2]) {
    await assertFails(getDoc(doc(as(uid), `families/f1/audit/a-${KID1}`)), `${uid} read`);
    await assertFails(setDoc(doc(as(uid), `families/f1/audit/a-${KID1}`), { action: "x" }), `${uid} overwrite`);
    await assertFails(deleteDoc(doc(as(uid), `families/f1/audit/a-${KID1}`)), `${uid} delete`);
  }
  // A child device cannot delete its marker to look like a member again.
  await assertFails(deleteDoc(doc(as(KID1), `families/f1/removedDevices/${KID1}`)));
  assert.equal(await exists(`families/f1/audit/a-${KID1}`), true);
});

// ---- Free child (setFreeChild replacement) -----------------------------------------------------

test("free child: parent devices pick child-1 or an existing child; child devices never", async () => {
  await seed();
  await assertSucceeds(updateDoc(doc(as(PARENT), "families/f1"), { freeChildId: "c2" }));
  await assertSucceeds(updateDoc(doc(as(PARENT2), "families/f1"), { freeChildId: "child-1" }));
  await assertFails(updateDoc(doc(as(PARENT), "families/f1"), { freeChildId: "c9" })); // no such child
  await assertFails(updateDoc(doc(as(PARENT), "families/f1"), { freeChildId: "bad/id" }));
  await assertFails(updateDoc(doc(as(PARENT), "families/f1"), { freeChildId: 5 }));
  await assertFails(updateDoc(doc(as(PARENT), "families/f1"), { freeChildId: "c1", plan: "plus" }));
  await assertFails(updateDoc(doc(as(KID1), "families/f1"), { freeChildId: "c1" })); // a child picks itself
  await assertFails(updateDoc(doc(as(STRANGER), "families/f1"), { freeChildId: "c1" }));
});

// ---- Task approval (approveTask / rejectTask replacement) --------------------------------------

/** FirestoreFamilyRepository.approveTask's write (seed: approved {prayer: 10}, earned 10). */
function approve(db, uid, taskId, credit, earned, extra = {}) {
  return setDoc(day(db), {
    day: DAY,
    approval: { taskId, by: uid, at: serverTimestamp() },
    approved: { [taskId]: credit },
    earnedMinutes: earned,
    requiredDone: false,
    progress: { [taskId]: { status: "done", count: 0 } },
    updatedAt: serverTimestamp(),
    updatedBy: uid,
    ...extra,
  }, { merge: true });
}

test("approval: a parent device credits one task once, 0..120 minutes, earned grows by exactly that", async () => {
  await seed();
  const db = as(PARENT);
  await assertFails(approve(db, PARENT, "homework", 121, 131)); // over 120
  await assertFails(approve(db, PARENT, "homework", -5, 5));
  await assertFails(approve(db, PARENT, "homework", 20, 40)); // earned must be 10 + 20
  await assertFails(approve(db, PARENT, "homework", 20, 30, { approved: { homework: 20, room: 20 } })); // two tasks
  await assertFails(approve(db, PARENT, "homework", 20, 30, { approval: { taskId: "homework", by: PARENT2, at: serverTimestamp() } }));
  await assertFails(approve(db, PARENT, "homework", 20, 30, { approval: { taskId: "homework", by: PARENT, at: Timestamp.now() } }));
  await assertFails(approve(db, PARENT, "homework", 20, 30, { approval: { taskId: "room", by: PARENT, at: serverTimestamp() } }));
  await assertFails(approve(db, PARENT, "homework", 20, 30, { prayerPaused: true }));
  await assertSucceeds(approve(db, PARENT, "homework", 20, 30, { requiredDone: true }));
  let after = await serverDay();
  assert.deepEqual(after.approved, { prayer: 10, homework: 20 });
  assert.equal(after.earnedMinutes, 30);
  assert.equal(after.requiredDone, true);
  // Approving again keeps the credit and adds nothing (any other value is refused).
  await assertFails(approve(db, PARENT, "homework", 60, 30));
  await assertFails(approve(db, PARENT, "homework", 20, 50));
  await assertSucceeds(approve(as(PARENT2), PARENT2, "homework", 20, 30));
  after = await serverDay();
  assert.equal(after.earnedMinutes, 30);
});

test("approval: the daily cap (600) holds", async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `families/f1/children/c1/days/${DAY}`), { earnedMinutes: 590 });
  });
  const db = as(PARENT);
  await assertFails(approve(db, PARENT, "room", 20, 610));
  await assertSucceeds(approve(db, PARENT, "room", 10, 600));
  await assertFails(approve(db, PARENT, "extra", 5, 605));
  await assertSucceeds(approve(db, PARENT, "extra", 0, 600));
});

test("approval: a child device can never credit itself, even with an approval op", async () => {
  await seed();
  const db = as(KID1);
  await assertFails(approve(db, KID1, "homework", 20, 30));
  await assertFails(approve(db, KID1, "homework", 0, 10));
  await assertFails(setDoc(day(db), { approval: { taskId: "homework", by: KID1, at: serverTimestamp() } }, { merge: true }));
  await assertFails(setDoc(day(db, "c1", "2026-11-23"), {
    day: "2026-11-23", approval: { taskId: "x", by: KID1, at: serverTimestamp() }, approved: { x: 5 }, earnedMinutes: 5,
  }));
  // A stranger or a removed device cannot either.
  await assertFails(approve(as(STRANGER), STRANGER, "homework", 20, 30));
  const after = await serverDay();
  assert.deepEqual(after.approved, { prayer: 10 });
  assert.equal(after.earnedMinutes, 10);
});

test("approval: approving a prayer ends the lock; a new day can start with an approval", async () => {
  await seed({ lockMinutesAgo: 1 });
  const db = as(PARENT);
  await assertSucceeds(approve(db, PARENT, "prayerAsr", 5, 15, { prayerLock: false, prayerLockAt: deleteField() }));
  const after = await serverDay();
  assert.equal(after.prayerLock, false);
  assert.equal(after.prayerLockAt, undefined);
  // A lock cannot be (re)started by an approval write.
  await assertFails(approve(db, PARENT, "prayerMaghrib", 5, 20, { prayerLock: true }));
  // New day doc (the child has not synced it yet).
  await assertSucceeds(setDoc(day(db, "c2", "2026-11-23"), {
    day: "2026-11-23", approval: { taskId: "room", by: PARENT, at: serverTimestamp() }, approved: { room: 15 },
    earnedMinutes: 15, requiredDone: false, progress: { room: { status: "done", count: 1 } },
  }));
  await assertFails(setDoc(day(db, "c2", "2026-11-24"), {
    day: "2026-11-24", approval: { taskId: "room", by: PARENT, at: serverTimestamp() }, approved: { room: 15 }, earnedMinutes: 30,
  }));
});

test("reject: a parent sends a task back to todo with a plain write; credits stay", async () => {
  await seed();
  await assertSucceeds(setDoc(day(as(PARENT)), {
    day: DAY, progress: { homework: { status: "todo", count: 0 } }, updatedAt: serverTimestamp(), updatedBy: PARENT,
  }, { merge: true }));
  const after = await serverDay();
  assert.equal(after.progress.homework.status, "todo");
  assert.deepEqual(after.approved, { prayer: 10 });
});

// ---- Fresh family cleanup after "Add a parent phone" -------------------------------------------

test("a phone deletes only its own untouched fresh family", async () => {
  await env.clearFirestore();
  const NEW = "freshPhoneUid";
  const fam = doc(as(NEW), "families/fresh-1");
  await assertSucceeds(setDoc(fam, { members: [NEW], createdAt: serverTimestamp(), settings: { lang: "ar" } }));
  await assertFails(deleteDoc(doc(as(STRANGER), "families/fresh-1")));
  await assertSucceeds(deleteDoc(fam));
  await seed();
  await assertFails(deleteDoc(doc(as(PARENT), "families/f1"))); // several members
  await assertFails(deleteDoc(doc(as(KID1), "families/f1")));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "families/paid-1"), { members: [NEW], plan: "plus" });
  });
  await assertFails(deleteDoc(doc(as(NEW), "families/paid-1"))); // not untouched
});

// ---- App side without Functions (docs/decisions/SPARK-APP-NO-FUNCTIONS.md) -------------------

/** plans.<app> as familyPlanSharerProvider writes it (client-asserted, accepted risk). */
const devicePlan = (uid, extra = {}) => ({
  plan: "plus", planExpiresAt: "2026-12-05T10:00:00.000Z", inTrial: false, source: "device",
  updatedBy: uid, updatedAt: serverTimestamp(), ...extra,
});

test("plans: a parent device shares its store plan as plans.play / plans.kids, fixed shape", async () => {
  await seed();
  const fam = doc(as(PARENT), "families/f1");
  await assertSucceeds(setDoc(fam, { plans: { play: devicePlan(PARENT) } }, { merge: true }));
  await assertSucceeds(setDoc(doc(as(PARENT2), "families/f1"), { plans: { kids: devicePlan(PARENT2, { plan: "basic" }) } }, { merge: true }));
  const after = await familyData();
  assert.equal(after.plans.play.plan, "plus");
  assert.equal(after.plans.kids.plan, "basic");
  // Denied shapes.
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { plan: "family" }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { inTrial: true }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { source: "store" }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { planExpiresAt: "x".repeat(41) }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { planExpiresAt: Timestamp.now() }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { updatedBy: PARENT2 }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { updatedAt: Timestamp.now() }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT, { purchaseToken: "t" }) } }, { merge: true }));
  await assertFails(setDoc(fam, { plans: { web: devicePlan(PARENT) } }, { merge: true })); // unknown app
  await assertFails(setDoc(fam, { plans: { play: devicePlan(PARENT) }, "settings": { lockAtAdhan: false } }, { merge: true })); // one thing per write
  // Legacy top-level plan, store, purchase and referral keys stay server-only.
  for (const field of [{ plan: "plus" }, { planApp: "play" }, { planExpiresAt: "2099-01-01" }, { inTrial: true },
    { store: "play" }, { purchaseToken: "t" }, { referralCode: "ZADX-AAAA" }, { referrals: { 2026: 3 } }]) {
    await assertFails(setDoc(fam, field, { merge: true }), JSON.stringify(field));
  }
});

test("plans: a child device or a stranger never writes plans", async () => {
  await seed();
  await assertFails(setDoc(doc(as(KID1), "families/f1"), { plans: { play: devicePlan(KID1) } }, { merge: true }));
  await assertFails(updateDoc(doc(as(KID1), "families/f1"), { "plans.kids": devicePlan(KID1) }));
  await assertFails(setDoc(doc(as(STRANGER), "families/f1"), { plans: { play: devicePlan(STRANGER) } }, { merge: true }));
  assert.equal((await familyData()).plans, undefined);
});

const event = (uid, extra = {}) => ({ type: "task_submitted", childId: "c1", at: serverTimestamp(), by: uid, detail: "homework", ...extra });
const events = (db) => collection(db, "families/f1/events");

test("events: a child device reports for its own child; a parent device for any child", async () => {
  await seed();
  await assertSucceeds(addDoc(events(as(KID1)), event(KID1)));
  await assertSucceeds(addDoc(events(as(KID1)), {
    type: "protection", childId: "c1", at: serverTimestamp(), by: KID1, reasons: ["accessibility_off", "clock_changed"],
  }));
  await assertSucceeds(addDoc(events(as(KID2)), event(KID2, { type: "adhan", childId: "c2", detail: "asr" })));
  await assertSucceeds(addDoc(events(as(PARENT)), event(PARENT, { childId: "c2" })));
  // Parents read and delete; child devices do not read, nobody updates.
  const list = await assertSucceeds(getDocs(events(as(PARENT))));
  assert.equal(list.size, 4);
  await assertFails(getDocs(events(as(KID1))));
  const first = list.docs[0].id;
  await assertFails(updateDoc(doc(as(PARENT), `families/f1/events/${first}`), { detail: "x" }));
  await assertFails(deleteDoc(doc(as(KID1), `families/f1/events/${first}`)));
  await assertSucceeds(deleteDoc(doc(as(PARENT), `families/f1/events/${first}`)));
});

test("events: denied writes (stranger, sibling, shape, time, writer, reasons)", async () => {
  await seed();
  await assertFails(addDoc(events(as(STRANGER)), event(STRANGER))); // stranger writing events
  await assertFails(addDoc(events(env.unauthenticatedContext().firestore()), event("x")));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { childId: "c2" }))); // a sibling's child
  await assertFails(addDoc(events(as(KID1)), event(KID1, { type: "plan_changed" })));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { childId: "bad/id" })));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { at: Timestamp.now() })));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { by: PARENT })));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { detail: "x".repeat(65) })));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { nickname: "Sara" }))); // no personal data
  await assertFails(addDoc(events(as(KID1)), event(KID1, { type: "protection", reasons: ["vpn_on"] })));
  await assertFails(addDoc(events(as(KID1)), event(KID1, { type: "protection", reasons: ["accessibility_off", "device_admin_off", "screen_time_off", "clock_changed", "clock_changed"] })));
  await removeAsFunctionWould(KID2);
  await assertFails(addDoc(events(as(KID2)), event(KID2, { childId: "c2" }))); // removed device
});

const presence = (db, child = "c1") => doc(db, `families/f1/presence/${child}`);
const seen = (uid, extra = {}) => ({ childId: "c1", lastSeen: serverTimestamp(), platform: "android", by: uid, ...extra });

test("presence: only the device bound to that child writes its last-seen; parents read and delete", async () => {
  await seed();
  await assertSucceeds(setDoc(presence(as(KID1)), seen(KID1)));
  await assertSucceeds(setDoc(presence(as(KID1)), seen(KID1, { protection: ["accessibility_off"] })));
  await assertSucceeds(getDoc(presence(as(PARENT))));
  await assertSucceeds(getDoc(presence(as(KID1))));
  await assertFails(getDoc(presence(as(KID2)))); // a sibling's device
  await assertFails(getDoc(presence(as(STRANGER))));
  // Denied writes.
  await assertFails(setDoc(presence(as(KID2)), seen(KID2))); // not its child
  await assertFails(setDoc(presence(as(PARENT)), seen(PARENT))); // parents never fake "last seen"
  await assertFails(setDoc(presence(as(STRANGER)), seen(STRANGER)));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { childId: "c2" })));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { lastSeen: Timestamp.fromMillis(Date.now() + 86_400_000) })));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { by: PARENT })));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { platform: "x".repeat(17) })));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { platform: 3 })));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { protection: ["unknown_reason"] })));
  await assertFails(setDoc(presence(as(KID1)), seen(KID1, { battery: 80 })));
  // Delete: parents only.
  await assertFails(deleteDoc(presence(as(KID1))));
  await assertSucceeds(deleteDoc(presence(as(PARENT))));
});
