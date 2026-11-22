/**
 * Real Apple dependencies for apple-logic.ts: SignedDataVerifier (JWS signature + x5c chain up to
 * Apple's root CA, bundle id, environment, OCSP) and the App Store Server API client.
 *
 * Configuration (never hardcoded; see backend/README.md "App Store"):
 *   APPLE_ENVIRONMENT   param   "Production" | "Sandbox"
 *   APPLE_ISSUER_ID     param   App Store Connect → Users and Access → Integrations → In-App Purchase
 *   APPLE_KEY_ID        param   id of that In-App Purchase key
 *   APPLE_APP_APPLE_ID  param   numeric Apple ID of Zad X Play (App Store Connect → App Information)
 *   APPLE_KIDS_APP_APPLE_ID param numeric Apple ID of Zad X Kids (only needed once Kids is on the App Store)
 *   APPLE_PRIVATE_KEY   secret  the .p8 key contents
 *   certs/AppleRootCA-G3.cer (+ AppleRootCA-G2.cer, AppleIncRootCertificate.cer)
 *                       Apple's public root certificates, downloaded from
 *                       https://www.apple.com/certificateauthority/ by scripts/fetch-apple-root-certs.sh
 * Anything missing → appleDeps() returns null and the callers fail closed (no entitlement).
 * One verifier + API client per app: com.zadx.app (Zad X Play) and com.zadx.kids (Zad X Kids) share
 * the In-App Purchase key but each checks its own bundle id (APPLE_BUNDLE_IDS).
 */
import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import {
  AppStoreServerAPIClient, Environment, ReceiptUtility, SignedDataVerifier,
} from "@apple/app-store-server-library";
import { defineSecret, defineString } from "firebase-functions/params";
import { APPLE_BUNDLE_IDS, AppleDeps, AppleNotification, AppleTransaction, appleConfigProblems, parseAppleEnvironment } from "./apple-logic";
import type { StoreApp } from "./security";

export const APPLE_PRIVATE_KEY = defineSecret("APPLE_PRIVATE_KEY");
const APPLE_ENVIRONMENT = defineString("APPLE_ENVIRONMENT", { default: "" });
const APPLE_ISSUER_ID = defineString("APPLE_ISSUER_ID", { default: "" });
const APPLE_KEY_ID = defineString("APPLE_KEY_ID", { default: "" });
const APPLE_APP_APPLE_ID = defineString("APPLE_APP_APPLE_ID", { default: "" });
const APPLE_KIDS_APP_APPLE_ID = defineString("APPLE_KIDS_APP_APPLE_ID", { default: "" });
const APP_APPLE_ID_PARAM: Readonly<Record<StoreApp, { name: string; value(): string }>> = {
  play: { name: "APPLE_APP_APPLE_ID", value: () => APPLE_APP_APPLE_ID.value() },
  kids: { name: "APPLE_KIDS_APP_APPLE_ID", value: () => APPLE_KIDS_APP_APPLE_ID.value() },
};

const CERT_DIR = join(__dirname, "..", "certs");

function loadRootCertificates(): Buffer[] {
  try {
    return readdirSync(CERT_DIR)
      .filter((f) => f.toLowerCase().endsWith(".cer"))
      .sort()
      .map((f) => readFileSync(join(CERT_DIR, f)));
  } catch {
    return [];
  }
}

const cached: Partial<Record<StoreApp, AppleDeps>> = {};

/** Apple verifier + API client for [app]'s bundle, or null (logged) when the configuration is incomplete. */
export function appleDeps(app: StoreApp): AppleDeps | null {
  const hit = cached[app];
  if (hit) return hit;
  const bundleId = APPLE_BUNDLE_IDS[app];
  const appIdParam = APP_APPLE_ID_PARAM[app];
  const roots = loadRootCertificates();
  let privateKey = "";
  try {
    privateKey = APPLE_PRIVATE_KEY.value() ?? "";
  } catch {
    privateKey = "";
  }
  const cfg = {
    environment: APPLE_ENVIRONMENT.value(),
    issuerId: APPLE_ISSUER_ID.value(),
    keyId: APPLE_KEY_ID.value(),
    privateKey,
    appAppleId: appIdParam.value(),
    rootCertificates: roots.length,
  };
  const problems = appleConfigProblems(cfg).map((p) => (p === "APPLE_APP_APPLE_ID" ? appIdParam.name : p));
  if (problems.length > 0) {
    // Names of the missing settings only, never their values.
    console.error(`App Store verification for ${bundleId} not configured (${problems.join(", ")}): failing closed, no entitlement`);
    return null;
  }
  const env = parseAppleEnvironment(cfg.environment) === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleId = cfg.appAppleId ? Number(cfg.appAppleId) : undefined;
  const verifier = new SignedDataVerifier(roots, true, env, bundleId, appAppleId);
  const api = new AppStoreServerAPIClient(cfg.privateKey, cfg.keyId, cfg.issuerId, bundleId, env);
  const receipts = new ReceiptUtility();

  const deps: AppleDeps = {
    bundleId,
    async verifyTransaction(jws: string): Promise<AppleTransaction> {
      return (await verifier.verifyAndDecodeTransaction(jws)) as unknown as AppleTransaction;
    },
    async verifyNotification(signedPayload: string): Promise<AppleNotification> {
      return (await verifier.verifyAndDecodeNotification(signedPayload)) as unknown as AppleNotification;
    },
    transactionIdFromReceipt(appReceipt: string): string | null {
      try {
        return receipts.extractTransactionIdFromAppReceipt(appReceipt) ?? null;
      } catch {
        return null;
      }
    },
    async signedTransactionInfo(transactionId: string): Promise<string | undefined> {
      const res = await api.getTransactionInfo(transactionId);
      return res.signedTransactionInfo ?? undefined;
    },
    async latestSignedTransactions(transactionId: string): Promise<string[]> {
      const res = await api.getAllSubscriptionStatuses(transactionId);
      const out: string[] = [];
      for (const group of res.data ?? []) {
        for (const item of group.lastTransactions ?? []) {
          if (typeof item.signedTransactionInfo === "string") out.push(item.signedTransactionInfo);
        }
      }
      return out;
    },
  };
  cached[app] = deps;
  return deps;
}
