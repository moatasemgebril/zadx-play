# ZADX Team — company operating manual

Product: Zad X Play (Islamic kids' app). Brand: Zad X. Owner: Moatasem Gebril.
Current design: https://claude.ai/artifact/4BzBKtLrSH4JJvdQx6U6Yv · Project notes: https://claude.ai/artifact/GMt77Hu5FWieAgss7sp7h9

## One work cycle
1. zadx-orchestrator reads BACKLOG.md + reports/, then picks the top priorities.
2. Specialists work in parallel (design, engineering, security, research, marketing, skills team).
3. Security team reviews every change → QA tests → bug-fixer fixes.
4. zadx-quality-gate grades everything A–F. Only Grade A ships.
5. zadx-daily-reporter writes reports/daily/<date>.md in Arabic, then it is emailed to the owner.

## Order of priority
Child safety & privacy > Islamic accuracy > security > working features > design polish > marketing.

## Done = "prime condition"
All areas Grade A on reports/quality/scorecard.md, zero open P0/P1 bugs, zero high/critical security findings,
WCAG 2.2 AA, Lighthouse ≥ 95, legal/privacy review and scholar review signed off by the owner.
