/**
 * App Store subscription checks, without any Apple or Firebase import so they can be unit-tested
 * with a mocked verifier (test/apple.test.js). The real verifier (SignedDataVerifier from
 * @apple/app-store-server-library, Apple root certificates, App Store Server API client) is built
 * in apple.ts.
 *
 * Rules (verifyPurchase on iOS + appStoreNotifications):
 *  - Every signed payload (transaction JWS, notification) is verified against Apple's root CA
 *    chain, our bundle id and the configured environment before any field is read.
 *  - The tier comes from the VERIFIED productId, never from the client.
 *  - The latest state is read from the App Store Server API (getAllSubscriptionStatuses), so an
 *    old or refunded transaction the client replays does not grant anything.
 *  - Not configured → fail closed (no entitlement) with a clear log line.
 */

import type { StoreApp } from "./security";

export type Tier = "basic" | "plus";

/** The fields we read from a verified JWSTransactionDecodedPayload. */
export interface AppleTransaction {
  productId?: string;
  bundleId?: string;
  originalTransactionId?: string;
  transactionId?: string;
  expiresDate?: number;
  revocationDate?: number;
  /** 1 = introductory offer (free trial / intro price), 2 = promotional, 3 = offer code, 4 = win-back. */
  offerType?: number;
  /** "FREE_TRIAL" | "PAY_AS_YOU_GO" | "PAY_UP_FRONT" (newer payloads). */
  offerDiscountType?: string;
  environment?: string;
}

/** The fields we read from a verified ResponseBodyV2DecodedPayload. */
export interface AppleNotification {
  notificationType?: string;
  subtype?: string;
  data?: { signedTransactionInfo?: string; bundleId?: string; environment?: string };
}

/** Only these calls touch Apple; tests pass a fake. One set per app (bundle id). */
export interface AppleDeps {
  /** Bundle id the verifier and API client were built for (APPLE_BUNDLE_IDS); default Zad X Play. */
  bundleId?: string;
  /** SignedDataVerifier.verifyAndDecodeTransaction: throws when the signature/chain/bundle/env is wrong. */
  verifyTransaction(jws: string): Promise<AppleTransaction>;
  /** SignedDataVerifier.verifyAndDecodeNotification. */
  verifyNotification(signedPayload: string): Promise<AppleNotification>;
  /** ReceiptUtility.extractTransactionIdFromAppReceipt (StoreKit 1 app receipt → a transaction id). */
  transactionIdFromReceipt(appReceipt: string): string | null;
  /** AppStoreServerAPIClient.getTransactionInfo → signedTransactionInfo (JWS, still unverified). */
  signedTransactionInfo(transactionId: string): Promise<string | undefined>;
  /** AppStoreServerAPIClient.getAllSubscriptionStatuses → every lastTransactions[].signedTransactionInfo. */
  latestSignedTransactions(transactionId: string): Promise<string[]>;
}

/** iOS bundle id of each app. A transaction / notification is only accepted for its own app's bundle. */
export const APPLE_BUNDLE_IDS: Readonly<Record<StoreApp, string>> = {
  play: "com.zadx.app",
  kids: "com.zadx.kids",
};

/** Zad X Play's bundle id (the default when [AppleDeps.bundleId] is not set). */
export const APPLE_BUNDLE_ID = APPLE_BUNDLE_IDS.play;

/** A compact JWS (header.payload.signature) as StoreKit 2 / notifications send it. */
export function looksLikeJws(value: string): boolean {
  return /^[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$/.test(value);
}

export type AppleEnvironment = "Production" | "Sandbox";

/** Environment from config ("Production" | "Sandbox"); anything else is null (fail closed). */
export function parseAppleEnvironment(raw: unknown): AppleEnvironment | null {
  return raw === "Production" || raw === "Sandbox" ? raw : null;
}

export interface AppleConfigInput {
  environment: string;
  issuerId: string;
  keyId: string;
  privateKey: string;
  appAppleId: string;
  rootCertificates: number;
}

/** Names of the missing / invalid settings ([] = ready). Logged, never returned to clients. */
export function appleConfigProblems(c: AppleConfigInput): string[] {
  const problems: string[] = [];
  const env = parseAppleEnvironment(c.environment);
  if (!env) problems.push("APPLE_ENVIRONMENT");
  if (!/^[0-9a-f-]{36}$/i.test(c.issuerId)) problems.push("APPLE_ISSUER_ID");
  if (!/^[A-Z0-9]{10}$/.test(c.keyId)) problems.push("APPLE_KEY_ID");
  if (!c.privateKey.includes("PRIVATE KEY")) problems.push("APPLE_PRIVATE_KEY");
  // The App Apple ID is required by SignedDataVerifier in Production.
  if (env === "Production" && !/^[0-9]{1,20}$/.test(c.appAppleId)) problems.push("APPLE_APP_APPLE_ID");
  if (c.rootCertificates < 1) problems.push("certs/AppleRootCA-*.cer");
  return problems;
}

export type AppleEntitlement =
  | { ok: true; tier: Tier; expiresAt: string; inTrial: boolean; originalTransactionId: string; productId: string }
  | { ok: false; reason: "unknown_product" | "revoked" | "expired" | "wrong_bundle" | "no_transaction" };

/**
 * Entitlement from ONE verified transaction. [tierOf] maps the product ids of the app being verified
 * only (tierForApp), and [bundleId] is that app's bundle.
 */
export function appleEntitlement(
  tx: AppleTransaction,
  nowMs: number,
  tierOf: (productId: string) => Tier | null,
  bundleId: string = APPLE_BUNDLE_ID,
): AppleEntitlement {
  if (tx.bundleId !== bundleId) return { ok: false, reason: "wrong_bundle" };
  if (typeof tx.originalTransactionId !== "string" || !/^[0-9]{1,30}$/.test(tx.originalTransactionId)) {
    return { ok: false, reason: "no_transaction" };
  }
  const tier = typeof tx.productId === "string" ? tierOf(tx.productId) : null;
  if (!tier) return { ok: false, reason: "unknown_product" };
  if (tx.revocationDate !== undefined && tx.revocationDate !== null) return { ok: false, reason: "revoked" };
  if (typeof tx.expiresDate !== "number" || !(tx.expiresDate > nowMs)) return { ok: false, reason: "expired" };
  const inTrial = tx.offerType === 1 && (tx.offerDiscountType === undefined || tx.offerDiscountType === "FREE_TRIAL");
  return {
    ok: true,
    tier,
    expiresAt: new Date(tx.expiresDate).toISOString(),
    inTrial,
    originalTransactionId: tx.originalTransactionId,
    productId: tx.productId as string,
  };
}

/** Prefer an active entitlement; among those the latest expiry (plus wins a tie). */
export function bestAppleEntitlement(list: AppleEntitlement[]): AppleEntitlement {
  const ok = list.filter((e): e is Extract<AppleEntitlement, { ok: true }> => e.ok);
  if (ok.length === 0) return list.find((e) => !e.ok && e.reason !== "unknown_product") ?? list[0] ?? { ok: false, reason: "no_transaction" };
  ok.sort((a, b) => Date.parse(b.expiresAt) - Date.parse(a.expiresAt) || (a.tier === "plus" ? -1 : 1));
  return ok[0];
}

/**
 * verifyPurchase on iOS. [verificationData] is what in_app_purchase sends as
 * serverVerificationData: a base64 app receipt (StoreKit 1) or a signed transaction (StoreKit 2).
 * Either way only Apple-signed data decides the result.
 */
export async function verifyAppleSubscription(
  deps: AppleDeps,
  verificationData: string,
  nowMs: number,
  tierOf: (productId: string) => Tier | null,
): Promise<AppleEntitlement> {
  let transactionId: string | null;
  if (looksLikeJws(verificationData)) {
    // Proves the JWS is ours (signature + chain + bundle + environment) before we trust its id.
    const tx = await deps.verifyTransaction(verificationData);
    if (tx.bundleId !== (deps.bundleId ?? APPLE_BUNDLE_ID)) return { ok: false, reason: "wrong_bundle" };
    transactionId = tx.originalTransactionId ?? tx.transactionId ?? null;
  } else {
    transactionId = deps.transactionIdFromReceipt(verificationData);
  }
  if (!transactionId || !/^[0-9]{1,30}$/.test(transactionId)) return { ok: false, reason: "no_transaction" };
  return latestAppleEntitlement(deps, transactionId, nowMs, tierOf);
}

/** The current state of the subscription that [transactionId] belongs to, from Apple. */
export async function latestAppleEntitlement(
  deps: AppleDeps,
  transactionId: string,
  nowMs: number,
  tierOf: (productId: string) => Tier | null,
): Promise<AppleEntitlement> {
  let signed = await deps.latestSignedTransactions(transactionId);
  if (signed.length === 0) {
    const one = await deps.signedTransactionInfo(transactionId);
    signed = one ? [one] : [];
  }
  const results: AppleEntitlement[] = [];
  for (const jws of signed.slice(0, 10)) {
    results.push(appleEntitlement(await deps.verifyTransaction(jws), nowMs, tierOf, deps.bundleId ?? APPLE_BUNDLE_ID));
  }
  return bestAppleEntitlement(results);
}

export type AppleNotificationAction = "refresh" | "revoke" | "ignore";

/**
 * What appStoreNotifications does with a verified notification. Every subscription change
 * re-reads the latest state from Apple ("refresh"); refunds and revocations end the plan now.
 */
export function appleNotificationAction(n: AppleNotification): AppleNotificationAction {
  switch (n.notificationType) {
    case "REFUND":
    case "REVOKE":
      return "revoke";
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "DID_CHANGE_RENEWAL_PREF":
    case "DID_CHANGE_RENEWAL_STATUS":
    case "DID_FAIL_TO_RENEW":
    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
    case "OFFER_REDEEMED":
    case "REFUND_REVERSED":
    case "RENEWAL_EXTENDED":
      return "refresh";
    default:
      return "ignore"; // TEST, CONSUMPTION_REQUEST, PRICE_INCREASE, ...
  }
}

/** First paid renewal after a trial/intro offer: the moment a referral counts (as on Google Play). */
export function isFirstPaidRenewal(n: AppleNotification, tx: AppleTransaction): boolean {
  return n.notificationType === "DID_RENEW" && tx.offerType === undefined;
}

/** Ownership key in purchases/{sha256(key)}: stable across renewals (the JWS changes every time). */
export function appleOwnershipKey(originalTransactionId: string): string {
  return `apple:${originalTransactionId}`;
}
