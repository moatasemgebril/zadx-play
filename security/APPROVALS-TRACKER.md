# Zad X Play — approvals & licensing tracker

Owned by the Approvals & Licensing Officer. Updated 2026-11-21 (branch `feat/offline-first-1`).
Only official contacts from the party's own website/console are listed; "source URL to verify"
means the address still needs a link to the page that publishes it. **OWNER** = only Moatasem can
do it (his accounts, signature or money). Never send on the owner's behalf without his approval.

Status values: Approved · Awaiting reply · Not sent · Blocked.

| Party | Need | Official contact + source URL | Date sent | Status | Next step |
|---|---|---|---|---|---|
| Quran Foundation | Use QF APIs (Quran text + recitations) in a paid kids' app | developers@quran.com; source URL to verify (QF developer docs: https://api-docs.quran.foundation/) | 2026-11-21 | **Approved** in writing 2026-11-21 by basit@quran.com: Alafasy, Abdul Basit (murattal), Al-Husary, Al-Minshawi (murattal) via QF APIs. Abdur-Rashid Sufi **not available → removed**. No rehosting on our servers (user-device downloads OK). Attribution "Quran data provided by Quran Foundation" + credit each reciter | Switch recitation source to the QF API (today everyayah.com), add attribution screen, request production credentials in the QF Developer Console |
| PRIVO | COPPA Safe Harbor / verifiable parental consent (incl. child geolocation) | info@privo.com; source URL to verify | 2026-11-21 | Awaiting reply | Follow up after 5 business days; prepare product summary + data map |
| Microsoft (trademarks) | Use of "Xbox" / Microsoft Family Safety names in app text | trademarks@microsoft.com; source URL to verify | 2026-11-21 | Awaiting reply (auto-reply only) | Follow up after 10 business days; meanwhile use plain descriptive wording only |
| Apple | Family Controls Distribution entitlement | Apple Developer account → entitlement request form; source URL to verify | — | Not sent (**OWNER**) | Owner submits from his developer account |
| Apple | Kids category listing | App Store Connect; App Review Guidelines 1.3 / 5.1.4; source URL to verify | — | Not sent (**OWNER**) | Decide category after location/analytics review |
| Apple | Offer Codes (subscriptions / referral rewards) | App Store Connect; source URL to verify | — | Not sent (**OWNER**) | Owner configures in App Store Connect |
| Google Play | Accessibility API declaration (game lock) | Play Console → App content; source URL to verify | — | Not sent (**OWNER**) | Owner fills declaration + demo video |
| Google Play | Families policy / Designed for Families + Data safety | Play Console → App content; source URL to verify | — | Not sent (**OWNER**) | Owner completes after privacy policy update |
| Google Play | Location permissions review (child location map) | Play Console; Location Permissions + Families policy; source URL to verify | — | Not sent (**OWNER**) | Only if the map passes docs/LOCATION_PRIVACY.md reviews |
| Islamic scholar | Review of adhkar (`lib/data/catalog/adhkar.dart`) and prophets quiz (`lib/data/catalog/prophets_quiz.dart`), praise phrases | Scholar to be chosen by the owner; no contact yet | — | Not sent | Islamic Content Reviewer prepares the review pack (text + source per item) |
| Adhan recordings | Licence for the four bundled adhans (`assets/audio/adhan_*.mp3`, missing today) | Rights holders per recording; source URL to verify | — | Not sent | Identify each recording's rights holder; until then no adhan audio ships |
| Trademark | "Zad X" / "Zad X Play" clearance search + filing | Trademark attorney (to choose); source URL to verify | — | Not sent (**OWNER**) | Get 2–3 quotes for search in Egypt, US, EU, GCC |
| Windows code signing | Authenticode / EV certificate for Zad X Guard (R-19) | Vendors (e.g. DigiCert, Sectigo, Azure Trusted Signing); source URL to verify | — | Not sent (**OWNER**) | Compare price + identity-verification needs |
| Privacy lawyers | COPPA, GDPR-K, Egypt PDPL review incl. **child geolocation consent** | Firms to shortlist; source URL to verify | — | Not sent (**OWNER**) | Send the question in docs/LOCATION_PRIVACY.md §10 with the data map |
| Sony / Microsoft | PlayStation Family app + Microsoft Family Safety: terms for deep-linking and naming | Official developer/brand pages; source URL to verify | — | Not sent | Check published terms; ask only if terms are unclear |
