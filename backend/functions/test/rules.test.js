// Firestore rules tests (R-32 / R-33) against the Firestore emulator.
// Run: npm run test:rules   (firebase emulators:exec starts the emulator; needs Java + firebase-tools)
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("fs");
const { join } = require("path");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const { doc, setDoc, updateDoc, getDoc, deleteDoc, serverTimestamp, Timestamp, increment } = require("firebase/firestore");

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
  await assertSucceeds(setDoc(day(as(KID1)), { prayerLock: true, prayerLockAt: serverTimestamp(), prayerLockSinceMs: Date.now() }, { merge: true }));
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
