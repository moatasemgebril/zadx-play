/// Which app this binary is: the Islamic "Zad X Play" or the non-religious "Zad X Kids".
///
/// Decision record: docs/decisions/ZADX-KIDS-VARIANT.md (owner decision 2026-11-22).
///
/// The variant is fixed at COMPILE time:
///
/// ```sh
/// flutter run                                   # Zad X Play (default)
/// flutter run --dart-define=ZADX_VARIANT=kids   # Zad X Kids
/// ```
///
/// Every check uses the `const` values below ([kIsKids], [appVariant]), so the compiler removes
/// the branches of the other variant: in a Kids release build the Quran, prayer, adhan, adhkar,
/// mosque and prophets code is unreachable and tree-shaken, not just hidden.
library;

enum AppVariant {
  /// "Zad X Play": the Islamic app (Quran, prayer times, adhan, adhkar…).
  islamic,

  /// "Zad X Kids": the same app with NOTHING religious; prayer locks are replaced by
  /// study / bedtime / reading schedules.
  kids;

  /// Parses a `ZADX_VARIANT` value. Anything other than `kids` is the Islamic app.
  static AppVariant parse(String value) => value.trim().toLowerCase() == 'kids' ? kids : islamic;
}

/// Raw `--dart-define=ZADX_VARIANT=...` value.
const String appVariantDefine = String.fromEnvironment('ZADX_VARIANT', defaultValue: 'islamic');

/// True in the Zad X Kids build. Compile-time constant: use it for `if` checks so the other
/// variant's code is tree-shaken.
const bool kIsKids = appVariantDefine == 'kids';

/// The variant of this build.
const AppVariant appVariant = kIsKids ? AppVariant.kids : AppVariant.islamic;
