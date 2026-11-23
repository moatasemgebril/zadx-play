// Unit tests for App Store verification (apple-logic.ts) with a MOCKED verifier: no Apple network
// calls and no real keys. The real SignedDataVerifier is built in apple.ts.
const test = require("node:test");
const assert = require("node:assert/strict");
const a = require("../lib/apple-logic.js");

const NOW = Date.parse("2026-11-22T10:00:00Z");
const DAY = 24 * 60 * 60_000;
const TIERS = { zadx_basic_monthly: "basic", zadx_basic_yearly: "basic", zadx_plus_monthly: "plus", zadx_plus_yearly: "plus" };
const tierOf = (id) => TIERS[id] ?? null;

// A fake compact JWS: the mocked verifier maps it to a payload; anything unknown "fails verification".
const jws = (name) => `eyJhbGciOiJFUzI1NiJ9.${Buffer.from(name).toString("base64url").padEnd(12, "A")}.c2lnbmF0dXJlLXNpZw`;

function tx(over = {}) {
  return {
    bundleId: "com.zadx.app", productId: "zadx_plus_monthly", originalTransactionId: "2000000123456789",
    transactionId: "2000000999999999", expiresDate: NOW + 20 * DAY, environment: "Sandbox", ...over,
  };
}

function deps({ signed = {}, latest = [], receipt = null, info } = {}) {
  const calls = [];
  return {
    calls,
    async verifyTransaction(j) {
      calls.push(["verifyTransaction", j]);
      if (!(j in signed)) throw new Error("VerificationException");
      return signed[j];
    },
    async verifyNotification() { throw new Error("unused"); },
    transactionIdFromReceipt(r) { calls.push(["receipt", r]); return receipt; },
    async signedTransactionInfo(id) { calls.push(["info", id]); return info; },
    async latestSignedTransactions(id) { calls.push(["latest", id]); return latest; },
  };
}

test("JWS input: verified, then the LATEST state from Apple decides; tier from the verified productId", async () => {
  const client = jws("client");
  const current = jws("current");
  const d = deps({
    signed: { [client]: tx({ productId: "zadx_basic_monthly", expiresDate: NOW - DAY }), [current]: tx() },
    latest: [current],
  });
  const r = await a.verifyAppleSubscription(d, client, NOW, tierOf);
  assert.equal(r.ok, true);
  assert.equal(r.tier, "plus");
  assert.equal(r.inTrial, false);
  assert.equal(r.originalTransactionId, "2000000123456789");
  assert.equal(r.expiresAt, new Date(NOW + 20 * DAY).toISOString());
  assert.deepEqual(d.calls.find((c) => c[0] === "latest"), ["latest", "2000000123456789"]);
});

test("a forged / unverifiable JWS is rejected before any field is used", async () => {
  const d = deps({});
  await assert.rejects(a.verifyAppleSubscription(d, jws("forged"), NOW, tierOf), /VerificationException/);
  assert.equal(d.calls.some((c) => c[0] === "latest"), false);
});

test("wrong bundle id, unknown product, revoked and expired transactions grant nothing", async () => {
  const cases = [
    [tx({ bundleId: "com.other.app" }), "wrong_bundle"],
    [tx({ productId: "zadx_lifetime_free" }), "unknown_product"],
    [tx({ revocationDate: NOW - 1000 }), "revoked"],
    [tx({ expiresDate: NOW - 1 }), "expired"],
    [tx({ expiresDate: undefined }), "expired"],
    [tx({ originalTransactionId: "../x" }), "no_transaction"],
  ];
  for (const [payload, reason] of cases) {
    assert.deepEqual(a.appleEntitlement(payload, NOW, tierOf), { ok: false, reason }, reason);
  }
});

test("a client-sent JWS for another app never reaches the status lookup", async () => {
  const client = jws("other");
  const d = deps({ signed: { [client]: tx({ bundleId: "com.other.app" }) } });
  assert.deepEqual(await a.verifyAppleSubscription(d, client, NOW, tierOf), { ok: false, reason: "wrong_bundle" });
  assert.equal(d.calls.some((c) => c[0] === "latest"), false);
});

test("StoreKit 1 app receipt: transaction id from the receipt, then Apple's signed data", async () => {
  const info = jws("info");
  const d = deps({ receipt: "2000000123456789", info, signed: { [info]: tx({ offerType: 1, offerDiscountType: "FREE_TRIAL" }) } });
  const r = await a.verifyAppleSubscription(d, "MIIT" + "A".repeat(200), NOW, tierOf);
  assert.equal(r.ok, true);
  assert.equal(r.inTrial, true);
  assert.deepEqual(d.calls.map((c) => c[0]), ["receipt", "latest", "info", "verifyTransaction"]);
});

test("a receipt without a transaction is refused", async () => {
  const d = deps({ receipt: null });
  assert.deepEqual(await a.verifyAppleSubscription(d, "MIIT" + "A".repeat(200), NOW, tierOf), { ok: false, reason: "no_transaction" });
});

test("bestAppleEntitlement prefers an active plan with the latest expiry", () => {
  const e1 = a.appleEntitlement(tx({ productId: "zadx_basic_monthly", expiresDate: NOW + 5 * DAY }), NOW, tierOf);
  const e2 = a.appleEntitlement(tx({ expiresDate: NOW + 30 * DAY }), NOW, tierOf);
  const bad = a.appleEntitlement(tx({ expiresDate: NOW - DAY }), NOW, tierOf);
  assert.equal(a.bestAppleEntitlement([e1, bad, e2]).tier, "plus");
  assert.deepEqual(a.bestAppleEntitlement([bad]), { ok: false, reason: "expired" });
  assert.deepEqual(a.bestAppleEntitlement([]), { ok: false, reason: "no_transaction" });
});

test("config check fails closed and names only the missing settings", () => {
  const full = {
    environment: "Production", issuerId: "57246542-96fe-1a63-e053-0824d011072a", keyId: "2X9R4HXF34",
    privateKey: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----", appAppleId: "1234567890", rootCertificates: 1,
  };
  assert.deepEqual(a.appleConfigProblems(full), []);
  assert.deepEqual(a.appleConfigProblems({ ...full, environment: "", rootCertificates: 0 }), ["APPLE_ENVIRONMENT", "certs/AppleRootCA-*.cer"]);
  assert.deepEqual(a.appleConfigProblems({ ...full, appAppleId: "" }), ["APPLE_APP_APPLE_ID"]);
  assert.deepEqual(a.appleConfigProblems({ ...full, environment: "Sandbox", appAppleId: "" }), []);
  assert.deepEqual(a.appleConfigProblems({ ...full, privateKey: "unset", keyId: "x", issuerId: "" }),
    ["APPLE_ISSUER_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY"]);
});

test("notification actions: refunds revoke, subscription changes refresh, the rest is ignored", () => {
  assert.equal(a.appleNotificationAction({ notificationType: "REFUND" }), "revoke");
  assert.equal(a.appleNotificationAction({ notificationType: "REVOKE" }), "revoke");
  for (const t of ["SUBSCRIBED", "DID_RENEW", "EXPIRED", "DID_FAIL_TO_RENEW", "GRACE_PERIOD_EXPIRED", "REFUND_REVERSED"]) {
    assert.equal(a.appleNotificationAction({ notificationType: t }), "refresh", t);
  }
  for (const t of ["TEST", "CONSUMPTION_REQUEST", "PRICE_INCREASE", undefined]) {
    assert.equal(a.appleNotificationAction({ notificationType: t }), "ignore", String(t));
  }
});

test("first paid renewal + ownership key + JWS shape", () => {
  assert.equal(a.isFirstPaidRenewal({ notificationType: "DID_RENEW" }, tx()), true);
  assert.equal(a.isFirstPaidRenewal({ notificationType: "DID_RENEW" }, tx({ offerType: 1 })), false);
  assert.equal(a.isFirstPaidRenewal({ notificationType: "SUBSCRIBED" }, tx()), false);
  assert.equal(a.appleOwnershipKey("2000000123456789"), "apple:2000000123456789");
  assert.equal(a.looksLikeJws(jws("x")), true);
  assert.equal(a.looksLikeJws("MIIT" + "A".repeat(200)), false);
  assert.deepEqual(a.parseAppleEnvironment("Production"), "Production");
  assert.equal(a.parseAppleEnvironment("production"), null);
});

// ---- Zad X Kids (com.zadx.kids): each app verifies its own bundle and its own products ----------
const { tierForApp } = require("../lib/security.js");

test("bundle ids per app; Play is the default", () => {
  assert.deepEqual(a.APPLE_BUNDLE_IDS, { play: "com.zadx.app", kids: "com.zadx.kids" });
  assert.equal(a.APPLE_BUNDLE_ID, "com.zadx.app");
});

test("Kids verifier: only com.zadx.kids transactions of Kids products grant a plan", async () => {
  const kidsTx = (over = {}) => tx({ bundleId: "com.zadx.kids", productId: "zadx_kids_plus_yearly", ...over });
  const kidsTier = tierForApp("kids");
  assert.equal(a.appleEntitlement(kidsTx(), NOW, kidsTier, "com.zadx.kids").ok, true);
  assert.equal(a.appleEntitlement(kidsTx(), NOW, kidsTier, "com.zadx.kids").productId, "zadx_kids_plus_yearly");
  // A Zad X Play transaction never verifies for Kids, and a Kids one never for Play.
  assert.deepEqual(a.appleEntitlement(tx(), NOW, kidsTier, "com.zadx.kids"), { ok: false, reason: "wrong_bundle" });
  assert.deepEqual(a.appleEntitlement(kidsTx(), NOW, tierForApp("play")), { ok: false, reason: "wrong_bundle" });
  // A Play product id inside a Kids-bundle transaction is not a Kids product.
  assert.deepEqual(a.appleEntitlement(kidsTx({ productId: "zadx_plus_monthly" }), NOW, kidsTier, "com.zadx.kids"),
    { ok: false, reason: "unknown_product" });

  // End to end with Kids deps: the latest state decides, and a Play JWS is refused before any lookup.
  const current = jws("kids-current");
  const d = { ...deps({ signed: { [current]: kidsTx() }, latest: [current] }), bundleId: "com.zadx.kids" };
  const r = await a.verifyAppleSubscription(d, current, NOW, kidsTier);
  assert.equal(r.ok, true);
  assert.equal(r.tier, "plus");
  const playJws = jws("play-client");
  const d2 = { ...deps({ signed: { [playJws]: tx() }, latest: [] }), bundleId: "com.zadx.kids" };
  assert.deepEqual(await a.verifyAppleSubscription(d2, playJws, NOW, kidsTier), { ok: false, reason: "wrong_bundle" });
  assert.equal(d2.calls.some((c) => c[0] === "latest"), false);
});
