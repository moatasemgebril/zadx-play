#!/usr/bin/env node
/**
 * One-off migration (run before/at the deploy of fix/family-entitlement-restore, see backend/README.md):
 * moves the raw store `purchaseToken` off every families/{id} doc (readable by all members, child
 * devices included) into server-only storage:
 *   purchases/{sha256(token)} = { familyId, store, migratedAt }
 *   families/{id}/private/billing = { purchaseToken }
 * and deletes the field. Idempotent; dry run unless --apply is given.
 *
 *   cd backend/functions && npm run build
 *   GOOGLE_APPLICATION_CREDENTIALS=<admin key, never committed> node scripts/migrate-purchase-tokens.js [--apply]
 *
 * Only ever run against the Zad X Firebase project. Tokens are never printed.
 */
const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { sha256Hex, tokenMigrationAction } = require("../lib/security.js");

async function main() {
  const apply = process.argv.includes("--apply");
  initializeApp();
  const db = getFirestore();
  const counts = { move: 0, skip: 0, conflict: 0 };
  // Every doc that still has the field (string tokens sort after "").
  const snap = await db.collection("families").where("purchaseToken", ">", "").get();
  for (const doc of snap.docs) {
    const result = await db.runTransaction(async (tx) => {
      const family = await tx.get(doc.ref);
      const token = family.get("purchaseToken");
      if (typeof token !== "string" || token.length === 0) return "skip";
      const purchaseRef = db.doc(`purchases/${sha256Hex(token)}`);
      const owner = await tx.get(purchaseRef);
      const action = tokenMigrationAction(doc.id, token, owner.exists ? owner.get("familyId") : undefined);
      if (action !== "move" || !apply) return action;
      tx.set(purchaseRef, { familyId: doc.id, store: family.get("store") ?? null, migratedAt: FieldValue.serverTimestamp() }, { merge: true });
      tx.set(doc.ref.collection("private").doc("billing"), { purchaseToken: token }, { merge: true });
      tx.update(doc.ref, { purchaseToken: FieldValue.delete() });
      return action;
    });
    counts[result] += 1;
    if (result === "conflict") console.warn(`conflict: family ${doc.id} holds a token owned by another family (left unchanged)`);
  }
  console.log(`${apply ? "applied" : "dry run (add --apply)"}: ${JSON.stringify(counts)}`);
  if (counts.conflict > 0) process.exitCode = 2;
}

main().catch((e) => {
  console.error("migration failed", e instanceof Error ? e.name : typeof e);
  process.exitCode = 1;
});
