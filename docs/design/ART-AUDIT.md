# Zad X Play — Kids Art Audit (2026-11-21)

Auditor: **zadx-kids-art-director** (standards: `.claude/agents/zadx-kids-art-director.md`).
Scope: every screen's background, icons, illustrations and motion in the Flutter app (`lib/`).
Grades: A (world-class) … F (harmful). Four axes: **Appeal** (joy for ages 5–12, fit for the area's mood),
**Clarity** (clear focal point, background never competes with content), **Accessibility** (contrast ≥ 4.5:1,
reduce-motion, no flashing, RTL), **Performance** (60 fps on low-end Android).

> "After" grades are the Art Director's self-assessment from code review and automated tests
> (`test/kids_art_test.dart`). Flutter was not available locally, so nothing has been looked at on a
> real screen yet. The Quality Gate gives the final grade after a device check of the CI APK.
> Nothing ships below A.

## 1. What was wrong before (shared by every screen)

Every screen used `PatternBackground`: a flat tint, 36 random confetti stars/dots, and the Zad X logo
**rotated, faded to 12 % and masked** behind the content.

| Problem | Why it matters | Fix |
|---|---|---|
| Same confetti on every screen, Quran included | No mood per area; Quran screen looked like a game screen (not calm or respectful) | One scene per area (`ZadSceneBackground`) |
| Owner's logo rotated, faded and masked as a watermark | Brand rule: the owner's real logo is used as-is; a ghost logo behind text is also visual noise | Watermark removed from backgrounds; logo stays in the header untouched |
| `ShaderMask` + full JPEG decode behind every screen | `ShaderMask` forces an offscreen layer each frame the screen repaints; a 340 px JPEG decoded per screen | Vector `CustomPainter` layers inside `RepaintBoundary`, no bitmaps |
| Stock Material icons in the navigation | Generic, not brand, one-colour, nothing "kid" about them | Original two-tone `ZadIcon` set |
| No sense of progress in Tasks | Children get no visual reward as they finish tasks | Garden that grows with today's progress + celebration burst |
| No prayer-time mood | The prayer card was a plain table | Sky strip that follows the prayer day |
| Celebration = static dots + star scale | Fine, but flat; the scale ignored reduce-motion | Short star burst (1.2 s) + reduce-motion respected |

## 2. Grades per screen

| Screen | Before (Appeal / Clarity / A11y / Perf → overall) | What was wrong | Fix shipped in this PR | After (self-assessed) |
|---|---|---|---|---|
| **Home** | C / B / B / C → **C** | Flat cream + confetti + ghost logo; mosque/moon were stock icons on a mint box | Sunrise sky over a little town with a mosque silhouette (dome, minaret, gold crescents), drifting clouds, softly breathing sun glow. Hero uses the new mosque icon; prayer card gets the prayer-sky strip; tasks card gets the tasks icon | A- / A / A / A → **A-** |
| **Games** | C / B / B / C → **C** | Same confetti as every screen; hero had a stock gamepad | Floating islands (trees, gold stars), two balloons drifting up, soft gold sparkles; motion bright but slow (24 s loop). Hero uses the new gamepad icon | A- / A / A / A → **A-** |
| **Tasks** | C / B / B / C → **C** | No feeling of progress | Garden: 9 flower spots; flowers bloom with the share of today's tasks done (read-only from `walletProvider`); sprouts wait for the next task; a butterfly visits once a task is done. Star burst when a task is handed in or approved | A / A / A / A → **A-** (needs device check) |
| **Quran** | D / B / B / C → **D** | Playful confetti behind the Quran list: wrong mood for the Quran | Calm night sky: crescent with soft halo, slow-twinkling stars (12–24 s per twinkle), three hanging lanterns with < 2° sway, faint eight-point-star lattice, quiet skyline. No playful motion | A / A / A / A → **A-** |
| **Adhkar** (Quran tab 3) | D / B / B / C → **D** | Same as Quran | Shares the Quran night scene | **A-** |
| **Prayer times** (card on Home) | D / B / B / B → **D** | Plain table, no sense of time of day | `PrayerSkyBanner`: dawn → day → afternoon → sunset → night, chosen from the existing prayer providers (`prayerTimesProvider`, `cityNowProvider`), with sun/moon, stars or clouds | A / A / A / A → **A-** |
| **Parent area** | C / B / B / C → **C** | Children's confetti in a professional area | Clean, light eight-point-star lattice; **no motion**, no scrim needed | A / A / A / A → **A** |
| **Settings** | C / B / B / C → **C** | Same as parent | Parent pattern | **A** |
| **Help** | C / B / B / C → **C** | Used the games tint | Parent pattern (calm, readable FAQ) | **A-** |
| **Subscription** | C / B / B / C → **C** | Confetti behind prices | Parent pattern (no playful pressure near payments) | **A** |
| **Edu games** (letters, prophets, mosque) | B- / B / B / C → **B-** | Confetti behind quiz questions; celebration scale ignored reduce-motion | Games scene as a **still frame** (no motion while the child reads a question). Celebration: original star/confetti burst (1.2 s); star pop-in respects reduce-motion; star chip uses the new star icon. Prophets scenes already draw scenery only (no figures): kept | A- / A / A / A → **A-** |
| **Bottom navigation / rail** | C / A / B / A → **C** | Stock icons | Original two-tone icons: muted when idle (outline ≥ 3:1 on white), brand colours + gentle 0.42 s pop when selected (skipped with reduce-motion). Parent badge kept | A / A / A / A → **A** |
| **Header** | B / A / A / B → **B** | Globe/help stock icons | White + gold `ZadIcon` settings/help on navy; logo untouched | **A-** |
| **Exercise cards** (Tasks; added 2026-11-21, branch feat/exercise-figures) | C / C / B / A → **C** | One generic stock dumbbell for all five exercises: nothing showed the child *what* to do | `lib/shared/art/exercise_figures.dart`: an original, code-drawn faceless kid per exercise (push-up, sit-up, jumping jack, squat, toe touch; a gentle stretch for unknown ids). Long sleeves, long trousers, neutral cap, outfit in the exercise colour, soft outline, floor shadow (mat for floor moves). Eased 1.2 s loop between two key poses; small hop + gold sparkles on "+1"; still pose with reduce-motion or once handed in; mirrored in RTL to face the text; `RepaintBoundary`, no rebuilds per frame. Tests: `test/exercise_figures_test.dart` | A- / A / A / A → **A-** (needs device check at 64 dp) |

## 3. How each standard is met

- **Original art only.** Everything is drawn in Dart (`lib/shared/art/`): no bitmaps, no third-party art,
  no copied characters. Shapes: sky gradients, hills, houses, domes, minarets, crescents, stars,
  lanterns, islands, flowers, a butterfly, balloons, an eight-point-star motif.
- **Islamic sensitivity.** No person, face, prophet, angel or companion anywhere. No music notes or
  instruments. Quran/Adhkar scene is the calmest (48 s loop, < 2° lantern sway, slow twinkle).
- **Readability.** Light scenes use high-luminance pastels plus a 35 % cream scrim. A unit test composites
  every scene colour under its scrim and checks contrast ≥ 4.5:1 against muted (#5E5A78), ink,
  purple-dark and mint text. Worst case: tasks stem green → 4.73:1 with muted text. The night scene only
  ever carries opaque white cards (no loose text); the prayer strip is decorative and carries no text.
- **Reduce motion.** `MediaQuery.disableAnimations` → every scene shows one still frame (no ticker runs),
  icons skip the pop, the burst shows a still sprinkle for 1.2 s then disappears. Tested.
- **No flashing.** All motion is slow position/alpha waves (≤ ~1.6 changes per second for the
  butterfly's wings, far slower elsewhere); nothing blinks or changes brightness sharply.
- **RTL.** Scenes are mirrored in RTL so the focal point (sun, moon) sits on the trailing side, away from
  where headings start. Tested in both directions.
- **Performance.** Static and moving layers are separate `CustomPaint`s, each in its own
  `RepaintBoundary`; the moving painter repaints from the animation directly (no widget rebuilds).
  Tickers are muted automatically for inactive tabs and covered routes (`TickerMode`), so off-screen
  scenes cost nothing. No `ShaderMask`, no blur filters, no images.

## 4. Open items (not done in this PR)

1. **Device check** (Quality Gate): install the CI APK, look at every scene on a low-end phone, confirm
   60 fps with the Flutter performance overlay, and confirm the scenes look as intended.
2. **Golden screenshots**: skipped on purpose (Google Fonts make goldens flaky in CI). Consider goldens
   with a bundled test font later.
3. **Web prototype** should adopt the same scenes and icons (port the painters to SVG/CSS).
4. **Old `PatternBackground`** is now unused by screens; remove it once the web prototype stops
   referencing the old look.
5. **Celebrations for adhkar sections** (section done) could reuse `ZadCelebrationBurst`.
6. **Illustrations for exercise tiles** (BACKLOG owner request 5): exercise figures done (see table). Still open: a
   girl variant with a modest head scarf (hijab) to choose per child, a jump-rope figure, and the non-exercise
   task illustrations (reading, tidying, prayer mat).
