/**
 * Zad X backend (Firebase Cloud Functions v2).
 *
 *  askAssistant     – AI help for parents (Claude API; key stays on the server)
 *  notifyParent     – push notification to parent devices (task done, adhan)
 *  verifyPurchase   – validates store receipts, stores the entitlement, records referrals
 *  referralStatus   – the caller's invite code + number of friends who paid
 *  playNotifications– Google Play RTDN webhook: credits referrers on a friend's first payment
 *  createPairingCode / redeemPairingCode – link child phones and Windows PCs to a family
 *  devicePolicy / reportUsage – HTTP API used by the Windows guard (device secret auth)
 */
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { google } from "googleapis";
import { createHash, randomBytes, randomInt, timingSafeEqual } from "crypto";

initializeApp();
const db = getFirestore();

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const ANDROID_PACKAGE = "com.zadx.app";
const ASSISTANT_MODEL = "claude-haiku-5-5";
const BASIC_DAILY_QUESTIONS = 10;
const REFERRAL_REWARD_MONTHS: Record<number, number> = { 1: 2, 2: 4, 3: 6 };
const MAX_REFERRALS_PER_YEAR = 3;

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  return auth.uid;
}

async function familyOf(uid: string): Promise<FirebaseFirestore.DocumentSnapshot> {
  const snap = await db.collection("families").where("members", "array-contains", uid).limit(1).get();
  if (snap.empty) throw new HttpsError("failed-precondition", "No family for this user.");
  return snap.docs[0];
}

// ---------------------------------------------------------------------------
// AI assistant
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `You are the help assistant inside "Zad X", an Islamic family app.
How the app works: children complete must-do tasks (prayer, homework) and bonus tasks
(Quran memorisation, adhkar, chores, light exercises); a parent approves each task and the
child earns play minutes. Device games (up to 5 on Basic, 15 on Plus) unlock only when
must-do tasks are approved, it is not prayer time, and minutes remain. At every adhan games
lock until the child taps "I prayed" and a parent approves. Prayer times follow the city and
calculation method chosen with the globe icon. PlayStation cannot be controlled directly;
Plus users get alerts and open the PlayStation Family app. Plans: Basic $4.99/month or
$39.99/year; Plus $7.99/month or $59.99/year; 14-day free trial. Referral: 1 paying friend =
2 free months, 2 = 4, 3 = 6.
Answer briefly and kindly in the user's language (Egyptian Arabic if they write Arabic).
Only answer questions about using Zad X, parenting screen time, or general Islamic etiquette
for children; for religious rulings advise asking a qualified scholar. Never give medical,
legal or financial advice.`;

export const askAssistant = onCall({ secrets: [ANTHROPIC_API_KEY], region: "europe-west1" }, async (req) => {
  const uid = requireUid(req.auth);
  const question = String(req.data?.question ?? "").slice(0, 1000).trim();
  const language = req.data?.language === "en" ? "en" : "ar";
  const history = Array.isArray(req.data?.history) ? req.data.history.slice(-8) : [];
  if (!question) throw new HttpsError("invalid-argument", "Empty question.");

  // Plan limits: Basic gets BASIC_DAILY_QUESTIONS per day.
  const family = await familyOf(uid);
  if (family.get("plan") !== "plus") {
    const day = new Date().toISOString().slice(0, 10);
    const usageRef = family.ref.collection("assistantUsage").doc(day);
    const used = (await usageRef.get()).get("count") ?? 0;
    if (used >= BASIC_DAILY_QUESTIONS) throw new HttpsError("resource-exhausted", "daily_limit");
    await usageRef.set({ count: FieldValue.increment(1) }, { merge: true });
  }

  const messages = [
    ...history
      .filter((m: { role?: string; content?: string }) => (m.role === "user" || m.role === "assistant") && m.content)
      .map((m: { role: string; content: string }) => ({ role: m.role, content: String(m.content).slice(0, 1000) })),
    { role: "user", content: question },
  ];

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY.value(),
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: ASSISTANT_MODEL,
      max_tokens: 500,
      system: `${SYSTEM_PROMPT}\nReply language: ${language === "ar" ? "Arabic" : "English"}.`,
      messages,
    }),
  });
  if (!res.ok) throw new HttpsError("unavailable", `AI error ${res.status}`);
  const body = (await res.json()) as { content: Array<{ type: string; text?: string }> };
  const answer = body.content.filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();
  return { answer };
});

// ---------------------------------------------------------------------------
// Parent notifications
// ---------------------------------------------------------------------------

export const notifyParent = onCall({ region: "europe-west1" }, async (req) => {
  const uid = requireUid(req.auth);
  const { familyId, childId, type, data } = req.data ?? {};
  const family = await db.doc(`families/${familyId}`).get();
  if (!family.exists || !(family.get("members") as string[]).includes(uid)) {
    throw new HttpsError("permission-denied", "Not a family member.");
  }
  const settings = family.get("settings") ?? {};
  if (type === "task_submitted" && settings.notifyOnTasks === false) return { sent: 0 };
  if (type === "adhan" && settings.notifyOnAdhan === false) return { sent: 0 };

  const tokens: string[] = family.get("parentTokens") ?? [];
  if (tokens.length === 0) return { sent: 0 };

  const ar = (family.get("language") ?? "ar") === "ar";
  const title = "Zad X";
  const body =
    type === "adhan"
      ? ar
        ? "وقت الصلاة — لو ابنك بيلعب على البلايستيشن أو الإكس بوكس، اقفله من التطبيق الرسمي"
        : "Prayer time — pause PlayStation or Xbox from the official app if your child is playing"
      : ar ? "فيه مهمة مستنية موافقتك" : "A task is waiting for your approval";

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type: String(type), childId: String(childId), ...(data ?? {}) },
  });
  return { sent: res.successCount };
});

// ---------------------------------------------------------------------------
// Purchases + referrals
// ---------------------------------------------------------------------------

const PRODUCTS: Record<string, { tier: "basic" | "plus" }> = {
  zadx_basic_monthly: { tier: "basic" },
  zadx_basic_yearly: { tier: "basic" },
  zadx_plus_monthly: { tier: "plus" },
  zadx_plus_yearly: { tier: "plus" },
};

async function androidPublisher() {
  const auth = new google.auth.GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] });
  return google.androidpublisher({ version: "v3", auth });
}

export const verifyPurchase = onCall({ region: "europe-west1" }, async (req) => {
  const uid = requireUid(req.auth);
  const { platform, productId, verificationData, referralCode } = req.data ?? {};
  const product = PRODUCTS[productId];
  if (!product) throw new HttpsError("invalid-argument", "Unknown product.");

  let expiresAt: string | null = null;
  let inTrial = false;

  if (platform === "android") {
    const publisher = await androidPublisher();
    const sub = await publisher.purchases.subscriptionsv2.get({ packageName: ANDROID_PACKAGE, token: verificationData });
    const line = sub.data.lineItems?.[0];
    expiresAt = line?.expiryTime ?? null;
    inTrial = Boolean(line?.offerDetails?.offerTags?.includes("trial") || sub.data.subscriptionState === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD");
    if (sub.data.subscriptionState !== "SUBSCRIPTION_STATE_ACTIVE" && sub.data.subscriptionState !== "SUBSCRIPTION_STATE_IN_GRACE_PERIOD") {
      throw new HttpsError("failed-precondition", "Subscription not active.");
    }
  } else {
    // TODO(ios): verify `verificationData` (JWS transaction) with Apple's App Store Server API
    // using @apple/app-store-server-library, then read expiresDate / offerType.
    throw new HttpsError("unimplemented", "iOS verification not configured yet.");
  }

  const family = await familyOf(uid);
  await family.ref.set(
    { plan: product.tier, planExpiresAt: expiresAt, inTrial, store: platform, purchaseToken: verificationData },
    { merge: true },
  );

  // Record the referral now; the referrer is credited only after the friend's first PAID period.
  if (referralCode && !(await family.ref.get()).get("referredBy")) {
    const owner = await db.collection("referralCodes").doc(String(referralCode).toUpperCase()).get();
    if (owner.exists && owner.get("familyId") !== family.id) {
      await family.ref.set({ referredBy: owner.get("familyId"), referralPaid: false }, { merge: true });
    }
  }
  return { tier: product.tier, inTrial, expiresAt };
});

export const referralStatus = onCall({ region: "europe-west1" }, async (req) => {
  const uid = requireUid(req.auth);
  const family = await familyOf(uid);
  let code: string | undefined = family.get("referralCode");
  if (!code) {
    code = await createUniqueCode(family.id);
    await family.ref.set({ referralCode: code }, { merge: true });
  }
  const year = new Date().getUTCFullYear();
  return { code, paidFriends: family.get(`referrals.${year}`) ?? 0 };
});

async function createUniqueCode(familyId: string): Promise<string> {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = "ZADX-" + Array.from({ length: 4 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
    const ref = db.collection("referralCodes").doc(code);
    const created = await db.runTransaction(async (tx) => {
      if ((await tx.get(ref)).exists) return false;
      tx.set(ref, { familyId, createdAt: FieldValue.serverTimestamp() });
      return true;
    });
    if (created) return code;
  }
  throw new HttpsError("internal", "Could not create code.");
}

/**
 * Google Play Real-time Developer Notifications (Pub/Sub push → this endpoint).
 * On SUBSCRIPTION_RENEWED (first paid period after the trial) the referrer earns
 * free months, applied by deferring their own Play subscription.
 */
export const playNotifications = onRequest({ region: "europe-west1" }, async (req, res) => {
  try {
    const msg = JSON.parse(Buffer.from(req.body?.message?.data ?? "", "base64").toString("utf8"));
    const n = msg.subscriptionNotification;
    const RENEWED = 2;
    if (!n || n.notificationType !== RENEWED) {
      res.status(204).send();
      return;
    }
    const friend = await db.collection("families").where("purchaseToken", "==", n.purchaseToken).limit(1).get();
    if (friend.empty || friend.docs[0].get("referralPaid") !== false) {
      res.status(204).send();
      return;
    }
    const friendRef = friend.docs[0].ref;
    const referrerId: string = friend.docs[0].get("referredBy");
    const year = new Date().getUTCFullYear();
    const referrerRef = db.doc(`families/${referrerId}`);

    const newCount = await db.runTransaction(async (tx) => {
      const referrer = await tx.get(referrerRef);
      const count = Math.min((referrer.get(`referrals.${year}`) ?? 0) + 1, MAX_REFERRALS_PER_YEAR);
      tx.set(referrerRef, { referrals: { [year]: count } }, { merge: true });
      tx.set(friendRef, { referralPaid: true }, { merge: true });
      return count;
    });

    // Each new paying friend adds the difference between reward tiers (2, +2, +2 months).
    const addMonths = (REFERRAL_REWARD_MONTHS[newCount] ?? 0) - (REFERRAL_REWARD_MONTHS[newCount - 1] ?? 0);
    const referrer = await referrerRef.get();
    if (addMonths > 0 && referrer.get("store") === "android") {
      const publisher = await androidPublisher();
      const productId = Object.keys(PRODUCTS).find((p) => PRODUCTS[p].tier === referrer.get("plan"));
      const current = new Date(referrer.get("planExpiresAt"));
      const desired = new Date(current);
      desired.setMonth(desired.getMonth() + addMonths);
      await publisher.purchases.subscriptions.defer({
        packageName: ANDROID_PACKAGE,
        subscriptionId: productId!,
        token: referrer.get("purchaseToken"),
        requestBody: {
          deferralInfo: {
            expectedExpiryTimeMillis: String(current.getTime()),
            desiredExpiryTimeMillis: String(desired.getTime()),
          },
        },
      });
      await referrerRef.set({ planExpiresAt: desired.toISOString() }, { merge: true });
    }
    // TODO(ios): for App Store subscribers, send a one-time offer code for `addMonths` free months.
    res.status(200).send();
  } catch (e) {
    console.error(e);
    res.status(500).send();
  }
});

// ---------------------------------------------------------------------------
// Device pairing
// ---------------------------------------------------------------------------

const PAIRING_TTL_MS = 10 * 60 * 1000;

export const createPairingCode = onCall({ region: "europe-west1" }, async (req) => {
  const uid = requireUid(req.auth);
  const familyId = String(req.data?.familyId ?? "");
  const target = req.data?.target === "windows" ? "windows" : "phone";
  const family = await db.doc(`families/${familyId}`).get();
  if (!family.exists || !(family.get("members") as string[]).includes(uid)) {
    throw new HttpsError("permission-denied", "Not a family member.");
  }
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
    const ref = db.collection("pairingCodes").doc(code);
    const ok = await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists && existing.get("expiresAt") > Date.now()) return false;
      tx.set(ref, { familyId, target, createdBy: uid, expiresAt: Date.now() + PAIRING_TTL_MS });
      return true;
    });
    if (ok) return { code };
  }
  throw new HttpsError("resource-exhausted", "Try again.");
});

function hashSecret(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

/**
 * Phone: adds the caller's uid to `members` and returns the familyId.
 * Windows Guard (unauthenticated HTTP client): returns a deviceId + deviceSecret
 * that the guard stores in the Windows Credential Manager.
 */
export const redeemPairingCode = onCall({ region: "europe-west1" }, async (req) => {
  const code = String(req.data?.code ?? "").trim();
  const ref = db.collection("pairingCodes").doc(code);
  const snap = await ref.get();
  if (!snap.exists || snap.get("expiresAt") < Date.now()) throw new HttpsError("not-found", "invalid_code");
  const familyId: string = snap.get("familyId");
  const target: string = snap.get("target");
  await ref.delete(); // single use

  if (target === "windows") {
    const deviceSecret = randomBytes(32).toString("hex");
    const device = await db.collection(`families/${familyId}/devices`).add({
      type: "windows",
      childId: "child-1",
      name: String(req.data?.deviceName ?? "Windows PC").slice(0, 60),
      secretHash: hashSecret(deviceSecret),
      createdAt: FieldValue.serverTimestamp(),
    });
    return { familyId, deviceId: device.id, deviceSecret };
  }

  const uid = requireUid(req.auth);
  await db.doc(`families/${familyId}`).update({ members: FieldValue.arrayUnion(uid) });
  return { familyId };
});

// ---------------------------------------------------------------------------
// Windows guard API (HTTP, device-secret auth)
// ---------------------------------------------------------------------------

async function authenticateDevice(req: { get(name: string): string | undefined }) {
  const familyId = req.get("x-zadx-family") ?? "";
  const deviceId = req.get("x-zadx-device") ?? "";
  const secret = req.get("x-zadx-secret") ?? "";
  if (!familyId || !deviceId || !secret) throw new HttpsError("unauthenticated", "missing credentials");
  const device = await db.doc(`families/${familyId}/devices/${deviceId}`).get();
  if (!device.exists) throw new HttpsError("unauthenticated", "unknown device");
  const expected = Buffer.from(device.get("secretHash"), "hex");
  const actual = Buffer.from(hashSecret(secret), "hex");
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    throw new HttpsError("unauthenticated", "bad secret");
  }
  await device.ref.set({ lastSeenAt: FieldValue.serverTimestamp() }, { merge: true });
  return { familyId, device };
}

function localDay(timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

/**
 * Same rule as WalletState.gamesUnlocked in the app:
 * unlocked = requiredDone && !prayerLock && earned - used > 0
 * The guard also locks on its own for 15 minutes after each adhan using `prayer`.
 */
export const devicePolicy = onRequest({ region: "europe-west1" }, async (req, res) => {
  try {
    const { familyId, device } = await authenticateDevice(req);
    const family = await db.doc(`families/${familyId}`).get();
    const settings = family.get("settings") ?? {};
    const timeZone: string = settings.timeZone ?? "UTC";
    const day = localDay(timeZone);
    const dayDoc = await db.doc(`families/${familyId}/children/${device.get("childId")}/days/${day}`).get();
    const earned = dayDoc.get("earnedMinutes") ?? 0;
    const used = dayDoc.get("usedMinutes") ?? 0;
    const requiredDone = dayDoc.get("requiredDone") ?? false;
    const prayerLock = dayDoc.get("prayerLock") ?? false;
    const remaining = Math.max(0, earned - used);
    const plan = family.get("plan");
    res.json({
      day,
      locked: !(requiredDone && !prayerLock && remaining > 0),
      reason: prayerLock ? "prayer" : !requiredDone ? "requiredTasks" : remaining <= 0 ? "noTime" : "none",
      remainingMinutes: remaining,
      games: settings.games ?? [],
      planActive: plan === "plus" || family.get("inTrial") === true,
      language: settings.language ?? "ar",
      prayer: {
        lat: settings.lat, lng: settings.lng, timeZone,
        fajrAngle: settings.fajrAngle, ishaAngle: settings.ishaAngle ?? null, ishaMinutes: settings.ishaMinutes ?? null,
        asrFactor: settings.asrFactor ?? 1, lockAtAdhan: settings.lockAtAdhan !== false,
      },
    });
  } catch (e) {
    const status = e instanceof HttpsError && e.code === "unauthenticated" ? 401 : 500;
    res.status(status).json({ error: String(e) });
  }
});

/** The guard reports minutes of foreground play; they reduce the child's balance on every device. */
export const reportUsage = onRequest({ region: "europe-west1" }, async (req, res) => {
  try {
    const { familyId, device } = await authenticateDevice(req);
    const minutes = Math.max(0, Math.min(60, Number(req.body?.minutes ?? 0)));
    const family = await db.doc(`families/${familyId}`).get();
    const day = localDay(family.get("settings")?.timeZone ?? "UTC");
    await db.doc(`families/${familyId}/children/${device.get("childId")}/days/${day}`).set(
      { day, usedMinutes: FieldValue.increment(minutes), updatedBy: `device:${device.id}` },
      { merge: true },
    );
    res.json({ ok: true });
  } catch (e) {
    const status = e instanceof HttpsError && e.code === "unauthenticated" ? 401 : 500;
    res.status(status).json({ error: String(e) });
  }
});
