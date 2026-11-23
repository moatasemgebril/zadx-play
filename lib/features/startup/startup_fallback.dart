import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/localized.dart';
import '../../core/theme/app_colors.dart';

/// Why the start-up fallback is shown.
enum StartupProblem {
  /// A start-up step threw (storage, Firebase, notifications…).
  failed,

  /// Start-up has not finished within the splash's maximum hold.
  slow,
}

/// Friendly texts of [StartupFallback]. Zad X Kids is always shown in English (no Arabic script
/// before the settings are loaded, Western market); Zad X Play follows the phone language.
abstract final class StartupText {
  static const failedTitle = Localized('حصلت مشكلة صغيرة', 'Something went wrong');
  static const failedBody = Localized(
    'Zad X ما قدرش يفتح دلوقتي. اتأكد من الإنترنت وجرّب تاني.',
    'Zad X could not start. Check your connection and try again.',
  );
  static const slowTitle = Localized('بياخد وقت أكتر من العادي', 'This is taking longer than usual');
  static const slowBody = Localized(
    'ممكن تستنى شوية، أو تجرّب تاني.',
    'You can wait a little, or try again.',
  );
  static const retry = Localized('جرّب تاني', 'Try again');

  /// Language of the fallback for [variant] and the phone language [deviceLanguage].
  static String languageFor(AppVariant variant, String deviceLanguage) =>
      kIsKids || variant == AppVariant.kids ? 'en' : (deviceLanguage == 'en' ? 'en' : 'ar');
}

/// Shown instead of an endless splash when start-up fails or takes too long: a calm message and
/// a big "Try again" button. Built on its own [MaterialApp] (the real app is not there yet).
/// No network images, no artwork with text; works in both apps.
class StartupFallback extends StatelessWidget {
  const StartupFallback({
    super.key,
    required this.problem,
    required this.lang,
    this.onRetry,
    this.retrying = false,
  });

  final StartupProblem problem;
  final String lang;

  /// Null hides the button (nothing to retry).
  final VoidCallback? onRetry;

  /// A retry is running: the button shows a spinner and cannot be pressed again.
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final failed = problem == StartupProblem.failed;
    final title = (failed ? StartupText.failedTitle : StartupText.slowTitle).of(lang);
    final body = (failed ? StartupText.failedBody : StartupText.slowBody).of(lang);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kIsKids ? 'Zad X Kids' : 'Zad X',
      home: Directionality(
        textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: AppColors.navy,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(failed ? Icons.wifi_off_rounded : Icons.hourglass_bottom_rounded, size: 56, color: Colors.white),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, height: 1.5, color: Colors.white),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.navy,
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          onPressed: retrying ? null : onRetry,
                          child: retrying
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                              : Text(StartupText.retry.of(lang)),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
