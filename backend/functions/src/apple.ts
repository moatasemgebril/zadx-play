/**
 * Real Apple dependencies for apple-logic.ts: SignedDataVerifier (JWS signature + x5c chain up to
 * Apple's root CA, bundle id, environment, OCSP) and the App Store Server API client.
 *
 * Configuration (never hardcoded; see backend/README.md "App Store"):
 *   APPLE_ENVIRONMENT   param   "Production" | "Sandbox"
 *   APPLE_ISSUER_ID     param   App Store Connect → Users and Access → Integrations → In-App Purchase
 *   APPLE_KEY_ID        param   id of that In-App Purchase key
 *   APPLE_APP_APPLE_ID  param   numeric Apple ID of the app (App Store Connect → App Information)
 *   APPLE_PRIVATE_KEY   secret  the .p8 key contents
 *   certs/AppleRootCA-G3.cer (+ AppleRootCA-G2.cer, AppleIncRootCertificate.cer)
 *                       Apple's public root certificates, downloaded from
 *                       https://www.apple.com/certificateauthority/ by scripts/fetch-apple-root-certs.sh
 * Anything missing → appleDeps() returns null and the callers fail closed (no entitlement).
 */
import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import {
  AppStoreServerAPIClient, Environment, ReceiptUtility, SignedDataVerifier,
} from "@apple/app-store-server-library";
import { defineSecret, defineString } from "firebase-functions/params";
import { APPLE_BUNDLE_ID, AppleDeps, AppleNotification, AppleTransaction, appleConfigProblems, parseAppleEnvironment } from "./apple-logic";

export const APPLE_PRIVATE_KEY = defineSecret("APPLE_PRIVATE_KEY");
const APPLE_ENVIRONMENT = defineString("APPLE_ENVIRONMENT", { default: "" });
const APPLE_ISSUER_ID = defineString("APPLE_ISSUER_ID", { default: "" });
const APPLE_KEY_ID = defineString("APPLE_KEY_ID", { default: "" });
const APPLE_APP_APPLE_ID = defineString("APPLE_APP_APPLE_ID", { default: "" });

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

let cached: AppleDeps | null = null;

/** Apple verifier + API client, or null (logged) when the configuration is incomplete. */
export function appleDeps(): AppleDeps | null {
  if (cached) return cached;
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
    appAppleId: APPLE_APP_APPLE_ID.value(),
    rootCertificates: roots.length,
  };
  const problems = appleConfigProblems(cfg);
  if (problems.length > 0) {
    // Names of the missing settings only, never their values.
    console.error(`App Store verification not configured (${problems.join(", ")}): failing closed, no entitlement`);
    return null;
  }
  const env = parseAppleEnvironment(cfg.environment) === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleId = cfg.appAppleId ? Number(cfg.appAppleId) : undefined;
  const verifier = new SignedDataVerifier(roots, true, env, APPLE_BUNDLE_ID, appAppleId);
  const api = new AppStoreServerAPIClient(cfg.privateKey, cfg.keyId, cfg.issuerId, APPLE_BUNDLE_ID, env);
  const receipts = new ReceiptUtility();

  cached = {
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
  return cached;
}
