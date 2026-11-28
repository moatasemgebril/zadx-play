# ZADX Team — company operating manual

Product: Zad X Play (Islamic kids' app). Brand: Zad X. Owner: Moatasem Gebril.
Current design: https://claude.ai/artifact/4BzBKtLrSH4JJvdQx6U6Yv · Project notes: https://claude.ai/artifact/GMt77Hu5FWieAgss7sp7h9
Brand (owner decision 2026-11-27): the "ZX" artwork is the app icon of both apps; "ZX ZAD X" is the logo inside
Zad X Play (`BrandLogo`). Brand navy backdrop for the splash and the parent area only; child screens stay bright.
All brand images come from `tools/gen_brand_assets.py` (sources in `tools/branding/source/`).

## One work cycle
1. zadx-orchestrator reads BACKLOG.md + reports/, then picks the top priorities.
2. Specialists work in parallel (design, engineering, security, research, marketing, skills team).
3. Security team reviews every change → QA tests → bug-fixer fixes.
4. zadx-quality-gate grades everything A–F. Only Grade A ships.
5. zadx-daily-reporter writes reports/daily/<date>.md in Arabic, then it is emailed to the owner.

## Saving usage (owner decision 2026-11-20)
- Two work cycles a day (morning: security + engineering + QA; afternoon: design/games/content on even days, approvals/marketing/add-ons on odd days). Max 3–4 subagents and 2 PRs per cycle.
- CI: light checks on PRs, heavy jobs on `main` only when their files change, the emulator nightly (if main changed), iOS/Windows/real phones weekly on Sunday or by hand. See docs/DEVICE_TESTING.md.
- Merge rule: a PR merges when its light PR checks are green and the Quality Gate approves. If a nightly/weekly/`main` heavy run fails, fixing it is P0 in the next morning cycle and no new features merge until it is green again.
- Prototype republished at most once a day; Gmail source backup weekly (Fridays).

## Zero cost (owner decision 2026-11-28)
- No paid lawyers, certificates or services; use free tiers only (Firebase Spark: Auth, Firestore within free quotas, Hosting). No Blaze, no card.
- The privacy-lawyer track is cancelled: the team writes the privacy policy and COPPA/GDPR-K checks from official free guidance; residual legal risk accepted by the owner.
- Spark cannot run Cloud Functions: server logic must move to Firestore rules + client/offline logic (BACKLOG "Zero-cost backend").

## Order of priority
Child safety & privacy > Islamic accuracy > security > working features > design polish > marketing.

## Done = "prime condition"
All areas Grade A on reports/quality/scorecard.md, zero open P0/P1 bugs, zero high/critical security findings,
WCAG 2.2 AA, Lighthouse ≥ 95, legal/privacy review and scholar review signed off by the owner.
