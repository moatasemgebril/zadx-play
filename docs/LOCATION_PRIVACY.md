# Child location ("Where is my child" / "مكان الطفل") — privacy & safety design

Status: **design only, not built.** Owner decision 2026-11-21. Ships behind
`FeatureFlags.locationMap` (`lib/core/feature_flags.dart`), which is **always off in release builds**
until every item in "Before release" is signed off. Claims marked *(to verify)* must be checked
against the current official text before we rely on them.

Priority reminder (CLAUDE.md): child safety & privacy come before every other goal. If any review
below says "no", we ship only the "Find my child" button (section 9) and drop the map.

## 1. What the feature is
- A map **only in the parent dashboard** showing where a child's paired phone is now.
- The **child never sees a map**, never sees other people's locations, and nothing about the
  location is shown on child screens except the sharing notice (section 3).
- One-shot "locate now" by default. No continuous tracking, **no movement history**.

## 2. Consent and defaults
- **Off by default**, per child. Turning it on needs the parent PIN and an explicit consent screen
  (plain AR/EN text: what is collected, who sees it, 24 h deletion, how to turn it off).
- Every consent change is **logged**: `families/{f}/children/{c}/locationConsentLog/{id}` =
  `{enabled, precise, byUid, at: request.time, textVersion}` — create-only, no edits.
- The current state lives in `families/{f}/children/{c}/locationSettings/current`
  (`{enabled, precise, updatedAt}`), parent-write only.
- Turning it off stops sharing immediately and deletes the current location document.
- All parent devices of the family are notified when sharing is turned on (via the parent push
  system from PR #8, once merged) so a hidden activation by one adult is visible to the others.

## 3. Notice on the child's device
While sharing is on, the child's device shows a persistent, friendly notice on the home screen:
**"موقعك ظاهر لأهلك" / "Your location is being shared with your parent"**. It cannot be hidden by
the parent. Copy goes through the AR/EN content review; the icon must not be frightening.

## 4. Data, transport, storage
- Data: `{lat, lng, accuracyM, approximate: bool, capturedAt, expireAt}`. No address lookup, no
  speed, no altitude, no Wi-Fi/cell ids, no device identifiers.
- **Approximate by default** (OS coarse location: Android `ACCESS_COARSE_LOCATION`, iOS reduced
  accuracy; additionally rounded on-device to about 1 km). **Precise only if the parent chooses
  it** in the consent screen *and* the OS permission allows it.
- **In transit:** TLS (Firestore SDK). **At rest:** Google-managed encryption. Optional upgrade
  for the owner to decide: end-to-end encryption with a key held only by paired parent devices,
  so neither Zad X staff nor a rules mistake can expose a location.
- **Single document, overwritten** (`families/{f}/children/{c}/location/current`) — never an
  append-only collection, so there is no movement history.
- **Auto-delete after 24 h:** Firestore TTL policy on `expireAt` (TTL deletion can lag — Google
  documents "typically within 24 hours" after expiry *(to verify)*), backed by a scheduled
  Function that deletes anything older than 24 h. Scheduled Functions need the Blaze plan
  (owner decision, see BACKLOG "Firebase status"); TTL policies work without Functions
  *(to verify on Spark)*.
- No third parties receive location: **no analytics, ads or crash SDK fields with location**.

## 5. Firestore rules (sketch) and required rules tests
```
// inside match /families/{familyId}/children/{childId}
match /locationSettings/{doc} {
  allow read: if isParent(familyId) || isChildDevice(familyId, childId);
  allow write: if isParent(familyId) && doc == 'current'
    && request.resource.data.keys().hasOnly(['enabled', 'precise', 'updatedAt'])
    && request.resource.data.enabled is bool && request.resource.data.precise is bool
    && request.resource.data.updatedAt == request.time;
}
match /locationConsentLog/{id} {
  allow read: if isParent(familyId);
  allow create: if isParent(familyId)
    && request.resource.data.keys().hasOnly(['enabled', 'precise', 'byUid', 'at', 'textVersion'])
    && request.resource.data.byUid == request.auth.uid
    && request.resource.data.at == request.time;
  allow update, delete: if false;          // deletion only via the family-deletion Function (R-08)
}
match /location/{doc} {
  // Readable ONLY by the family's parents, never by the child device or anyone else.
  allow read: if isParent(familyId);
  allow delete: if isParent(familyId) || isChildDevice(familyId, childId);
  allow create, update: if isChildDevice(familyId, childId) && doc == 'current'
    && get(/databases/$(database)/documents/families/$(familyId)/children/$(childId)/locationSettings/current).data.enabled == true
    && validLocation(familyId, childId);
}
function validLocation(familyId, childId) {
  let d = request.resource.data;
  let s = get(/databases/$(database)/documents/families/$(familyId)/children/$(childId)/locationSettings/current).data;
  return d.keys().hasOnly(['lat', 'lng', 'accuracyM', 'approximate', 'capturedAt', 'expireAt'])
    && d.lat is number && d.lat >= -90 && d.lat <= 90
    && d.lng is number && d.lng >= -180 && d.lng <= 180
    && d.accuracyM is number && d.accuracyM >= 0
    && d.approximate is bool && (s.precise == true || d.approximate == true)
    && d.capturedAt == request.time
    && d.expireAt == request.time + duration.value(24, 'h');
}
```
Required rules tests (emulator, `@firebase/rules-unit-testing`) before the flag can move:
1. Parent of the family can read `location/current`; the bound child device **cannot** read it.
2. A member of another family, an unauthenticated user and a signed-in stranger cannot read it.
3. A child device bound to child A cannot write child B's location.
4. Write is denied when `locationSettings/current.enabled` is false or missing.
5. `approximate: false` is denied unless the parent set `precise: true`.
6. Extra fields, out-of-range coordinates, wrong `expireAt` or a client `capturedAt` are denied.
7. A child device cannot create or change `locationSettings` or the consent log.
8. Consent log entries cannot be updated or deleted by anyone through the client.
9. Writes to any other doc id or a sub-collection under `location` are denied (no history).

**Pre-condition:** the rules treat "member without a `childDevices` entry" as a parent. Legacy
unbound child devices (risk **R-28**) would therefore see the map. R-28 must be fixed (and R-02's
"parent confirms new devices" step done) before this feature can be enabled for anyone.

## 6. Map: OpenStreetMap via flutter_map
- Map widget: `flutter_map` (BSD-3-Clause *(to verify)*). **No Google Maps SDK, no ad or
  analytics SDKs**, no Mapbox SDK telemetry.
- OSM tile usage policy (https://operations.osmfoundation.org/policies/tiles/): visible
  attribution "© OpenStreetMap contributors", a real identifying User-Agent
  (`userAgentPackageName: 'com.zadx.app'`), respect cache headers, no bulk/offline prefetch, and
  `tile.openstreetmap.org` is not for heavy production use *(to verify current wording)*.
- **Owner decision — tile provider for production.** Options: a commercial OSM tile host
  (e.g. MapTiler, Stadia Maps, Thunderforest — free tiers and prices *to verify*), or
  self-hosted vector tiles (e.g. Protomaps PMTiles on our own storage; no per-request fee, we pay
  storage/egress). Privacy point: the tile server sees the parent's IP and the area being viewed,
  i.e. roughly where the child is. Prefer self-hosting, or a provider with a DPA and no logging of
  tile requests. Any API key must have a spending cap and be restricted to our app ids.

## 7. Store and legal policy (all *to verify* with the current policy text)
- **Google Play:** Families policy + Location Permissions policy; the Data safety form must list
  approximate/precise location. Play's Families policy may restrict location permissions in
  apps that target children *(to verify — possible blocker)*. **No background location**
  (`ACCESS_BACKGROUND_LOCATION`) unless the policy review explicitly clears it; one-shot
  foreground "locate now" first. "Safe places" arrival/leave alerts (BACKLOG item 6) need
  background location/geofencing, so they are **deferred** until that review.
- **Apple:** Kids category rules (no third-party analytics/ads, parental gate), App Review 5.1.1
  and 5.1.4 (kids data) *(to verify)*; `NSLocationWhenInUseUsageDescription` text in AR/EN; no
  "Always" location unless the review clears it; interaction with Family Controls entitlement.
- **COPPA:** geolocation precise enough to identify a street and city is "personal information"
  (16 CFR 312.2) — needs verifiable parental consent (VPC) before collection. Today parents are
  anonymous (risk **R-27**), so there is no VPC: **blocker** until parent sign-in + VPC exist
  (PRIVO conversation in `security/APPROVALS-TRACKER.md`).
- **GDPR-K / UK Children's Code:** Art. 8 consent by the holder of parental responsibility;
  geolocation off by default and obvious to the child while on (UK Age Appropriate Design Code
  standard 10 *(to verify)*); a DPIA is very likely required for children's location data.
- **Egypt PDPL (Law 151/2020)** and other launch markets: ask the privacy lawyer *(to verify)*.

## 8. Threats (summary — full entry in security/THREAT-MODEL.md §3.8, risk R-31)
Stalking/abuse by a non-custodial adult who has (or gets) a parent device; leaked pairing code;
data kept longer than 24 h; rules misconfiguration; tile provider learning locations.

## 9. Simpler alternative shipped first: "Find my child"
A parent-dashboard button that opens **Google Family Link** (Android) or **Apple Find My**
(iOS) — the OS vendors' own, already-reviewed location features. Zad X collects nothing. Deep
links/package ids *(to verify)*: Family Link `com.google.android.apps.kids.familylink`, web
https://families.google/familylink/; Find My URL scheme `findmy://`. Not behind the flag (no data),
but still reviewed by the child-safety officer.

## 10. Before release (all required; the flag stays off until then)
- [ ] Policy review: Google Play Families + Location Permissions + Data safety (owner's console).
- [ ] Policy review: Apple Kids category + location strings (owner's developer account).
- [ ] COPPA VPC for geolocation and GDPR-K consent flow (PRIVO / privacy lawyer).
- [ ] Privacy-lawyer question: "Can a kids' app operated from Egypt collect a child's
      approximate location, with parental consent logged as in §2 and 24 h deletion, for parents in
      the US, EU/UK, Egypt and the Gulf? What consent method and DPIA do we need?"
- [ ] DPIA written and privacy policy updated (location section, retention, tile provider).
- [ ] R-28 fixed, R-02 parent device confirmation done, rules + 9 rules tests above green.
- [ ] Tile provider decision by the owner.
- [ ] Owner sign-off recorded in the ZADX LOG.
