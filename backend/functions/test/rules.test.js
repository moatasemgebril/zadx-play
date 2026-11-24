// Firestore rules tests (R-32 / R-33) against the Firestore emulator.
// Run: npm run test:rules:deps && npm run test:rules
// (firebase emulators:exec starts the emulator; needs Java + `npm i -g firebase-tools`). The test SDKs
// are not in package.json so `npm audit` covers only what we deploy.
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("fs");
const { join } = require("path");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const {
  doc, collection, setDoc, updateDoc, getDoc, getDocs, deleteDoc, serverTimestamp, Timestamp, increment, arrayUnion,
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
  // freeChildId is chosen through the setFreeChild function only.
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
    "families/f1/devices/d1", "families/f1/private/billing", "families/f1/assistantUsage/" + DAY,
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
