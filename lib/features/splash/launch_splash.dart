import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/app_variant.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/brand_logo.dart';
import '../settings/settings_controller.dart' show defaultLanguageFor;
import '../startup/startup_fallback.dart';

/// Brand launch screen, shown while the start-up work in `main()` runs. One per app:
///
/// * **Zad X Play**: the Zad X logo ([BrandLogo]), the Latin "Zad X" wordmark and the identity
///   line in Arabic and English ([IslamicBrand.identityAr] / [IslamicBrand.identityEn]) on a
///   soft navy → purple gradient.
/// * **Zad X Kids**: the Latin "ZAD X KIDS" wordmark ([BrandLogo] in Kids) on a bright, neutral
///   navy → teal sky with sun-yellow and coral light. No Arabic script, no religious line, no
///   artwork logo (docs/decisions/ZADX-KIDS-VARIANT.md).
///
/// Shared behaviour:
/// * The native splash (Android `launch_background`, iOS `LaunchScreen.storyboard`) uses
///   [LaunchSplash.background] (navy, both apps) so there is no white flash before the first
///   Flutter frame; both gradients start from that navy.
/// * The reveal (fade + scale + one shimmer pass) takes [revealDuration] (≤ 1.6 s together
///   with the exit fade). The app is built underneath while it plays, so start-up is not
///   delayed: the splash leaves as soon as both the reveal and the app are ready.
/// * Reduced motion (`MediaQuery.disableAnimations`): no animation, the final frame is shown
///   for [reducedMotionHold] and then the app appears without a fade.
/// * Bundled assets and the platform default font only: no network, no runtime font download.
/// * Screen readers hear one label: "Zad X Kids", or "Zad X — <identity line>" in Zad X Play.
/// * Never stuck: if start-up fails ([LaunchSplashHandle.fail]) or is not done after [maxHold],
///   the splash hands over to [StartupFallback] (friendly message + "Try again"); the app replaces
///   it as soon as it is ready.
class LaunchSplash {
  const LaunchSplash._();

  /// Same colour as the native launch background (android `zadx_splash_bg`, iOS storyboard).
  static const background = AppColors.navy;

  static const revealDuration = Duration(milliseconds: 1300);
  static const exitDuration = Duration(milliseconds: 300);
  static const reducedMotionHold = Duration(milliseconds: 500);

  /// Longest time the splash waits for start-up before showing [StartupFallback].
  static const maxHold = Duration(seconds: 6);

  /// Screen-reader label of the splash for [variant] in [lang].
  static String semanticsLabel(AppVariant variant, String lang) => !kIsKids && variant == AppVariant.islamic
      ? '${AppConfig.brandName} — ${IslamicBrand.identityFor(lang)}'
      : KidsBrand.storeName;

  /// Shows the splash right away (`runApp`) and returns a handle. Hand the real app to
  /// [LaunchSplashHandle.complete] once start-up is done, or the error to
  /// [LaunchSplashHandle.fail]. [retry] runs start-up again from the fallback's "Try again".
  static LaunchSplashHandle show({Future<Widget> Function()? retry}) {
    final handle = LaunchSplashHandle();
    runApp(LaunchSplashHost(app: handle.app, retry: retry));
    return handle;
  }
}

/// Passes the real app (or the start-up error) to the splash.
class LaunchSplashHandle {
  LaunchSplashHandle() {
    // The host listens a frame later (runApp attaches the root asynchronously): an early failure
    // must not be reported as an unhandled error meanwhile.
    _app.future.ignore();
  }

  final _app = Completer<Widget>();

  Future<Widget> get app => _app.future;

  void complete(Widget app) {
    if (!_app.isCompleted) _app.complete(app);
  }

  /// Start-up failed: the splash shows [StartupFallback] instead of waiting forever.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!_app.isCompleted) _app.completeError(error, stackTrace);
  }
}

/// Root widget during start-up: the app (once ready) underneath, the splash on top until
/// it has finished, then only the app. The app keeps its state when the splash leaves.
class LaunchSplashHost extends StatefulWidget {
  const LaunchSplashHost({
    super.key,
    required this.app,
    this.variant = appVariant,
    this.language,
    this.revealDuration = LaunchSplash.revealDuration,
    this.exitDuration = LaunchSplash.exitDuration,
    this.reducedMotionHold = LaunchSplash.reducedMotionHold,
    this.maxHold = LaunchSplash.maxHold,
    this.retry,
  });

  /// The app once start-up is done; an error shows [StartupFallback].
  final Future<Widget> app;

  /// Runs start-up again ("Try again" on the fallback). Null: no button.
  final Future<Widget> Function()? retry;

  /// After this long without an app, [StartupFallback] is shown (the app still replaces it when
  /// it arrives).
  final Duration maxHold;

  /// Which app's splash (default: this build; the Kids build always shows the Kids splash).
  final AppVariant variant;

  /// Language of the screen-reader label. Default: the first-run language of [variant] for the
  /// phone's language (settings are not loaded yet at this point).
  final String? language;

  final Duration revealDuration;
  final Duration exitDuration;
  final Duration reducedMotionHold;

  @override
  State<LaunchSplashHost> createState() => _LaunchSplashHostState();
}

class _LaunchSplashHostState extends State<LaunchSplashHost> {
  static const _appKey = ValueKey('zadx-app');
  static const _splashKey = ValueKey('zadx-splash');

  static const _fallbackKey = ValueKey('zadx-startup-fallback');

  Widget? _app;
  bool _splashDone = false;
  StartupProblem? _problem;
  bool _retrying = false;
  Timer? _maxHold;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _wait(widget.app);
  }

  /// Waits for one start-up attempt; a newer attempt makes an older result irrelevant, except
  /// that any finished app is always taken.
  void _wait(Future<Widget> attempt) {
    final id = ++_attempt;
    _maxHold?.cancel();
    _maxHold = Timer(widget.maxHold, () {
      if (!mounted || _app != null || id != _attempt) return;
      // Also ends a retry that hangs: the button can be pressed again.
      setState(() {
        _problem = StartupProblem.slow;
        _retrying = false;
      });
    });
    attempt.then((app) {
      if (!mounted || _app != null) return;
      _maxHold?.cancel();
      setState(() {
        _app = app;
        _problem = null;
        _retrying = false;
      });
    }, onError: (Object e, StackTrace st) {
      debugPrint('start-up failed: $e');
      if (!mounted || _app != null || id != _attempt) return;
      _maxHold?.cancel();
      setState(() {
        _problem = StartupProblem.failed;
        _retrying = false;
      });
    });
  }

  void _onRetry() {
    final retry = widget.retry;
    if (retry == null || _retrying) return;
    setState(() => _retrying = true);
    Future<Widget> next;
    try {
      next = retry();
    } catch (e, st) {
      next = Future<Widget>.error(e, st);
    }
    _wait(next);
  }

  @override
  void dispose() {
    _maxHold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final variant = kIsKids ? AppVariant.kids : widget.variant;
    final deviceLanguage = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final lang = widget.language ?? defaultLanguageFor(variant, deviceLanguage);
    final problem = app == null ? _problem : null;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        if (app != null)
          // Hidden from screen readers while the splash covers it.
          ExcludeSemantics(key: _appKey, excluding: !_splashDone, child: app)
        else if (problem != null)
          ExcludeSemantics(
            key: _fallbackKey,
            excluding: !_splashDone,
            child: StartupFallback(
              problem: problem,
              lang: StartupText.languageFor(variant, widget.language ?? deviceLanguage),
              onRetry: widget.retry == null ? null : _onRetry,
              retrying: _retrying,
            ),
          ),
        if (!_splashDone)
          MediaQuery.fromView(
            key: _splashKey,
            view: View.of(context),
            child: Directionality(
              // The wordmarks are Latin, so the stage reads left to right (RTL app included).
              textDirection: TextDirection.ltr,
              child: _SplashStage(
                variant: variant,
                label: LaunchSplash.semanticsLabel(variant, lang),
                // Leave for the app, or for the fallback when start-up failed / is too slow.
                appReady: app != null || problem != null,
                revealDuration: widget.revealDuration,
                exitDuration: widget.exitDuration,
                reducedMotionHold: widget.reducedMotionHold,
                onFinished: () {
                  if (mounted) setState(() => _splashDone = true);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashStage extends StatefulWidget {
  const _SplashStage({
    required this.variant,
    required this.label,
    required this.appReady,
    required this.revealDuration,
    required this.exitDuration,
    required this.reducedMotionHold,
    required this.onFinished,
  });

  final AppVariant variant;
  final String label;
  final bool appReady;
  final Duration revealDuration;
  final Duration exitDuration;
  final Duration reducedMotionHold;
  final VoidCallback onFinished;

  @override
  State<_SplashStage> createState() => _SplashStageState();
}

class _SplashStageState extends State<_SplashStage> with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(vsync: this, duration: widget.revealDuration);
  late final AnimationController _exit = AnimationController(vsync: this, duration: widget.exitDuration);
  Timer? _hold;
  bool _started = false;
  bool _reduced = false;
  bool _revealed = false;
  bool _leaving = false;

  bool get _play => !kIsKids && widget.variant == AppVariant.islamic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      // No motion: show the final frame, hold it briefly, then hand over.
      _reveal.value = 1;
      _hold = Timer(widget.reducedMotionHold, _onRevealed);
    } else {
      // Zad X Play only: the Kids bundle has no artwork logo (tools/kids_variant_prepare.py).
      if (_play) precacheImage(const AssetImage(BrandLogo.islamicAsset), context, onError: (_, __) {});
      _reveal.forward().whenComplete(_onRevealed);
    }
  }

  @override
  void didUpdateWidget(_SplashStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appReady && !oldWidget.appReady) _maybeLeave();
  }

  void _onRevealed() {
    if (!mounted) return;
    _revealed = true;
    _maybeLeave();
  }

  void _maybeLeave() {
    if (!_revealed || !widget.appReady || _leaving) return;
    _leaving = true;
    if (_reduced) {
      // May be reached from didUpdateWidget (during a build): hand over after this frame.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (mounted) widget.onFinished();
        })
        ..ensureVisualUpdate();
    } else {
      _exit.forward().whenComplete(() {
        if (mounted) widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _reveal.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: Semantics(
        label: widget.label,
        container: true,
        excludeSemantics: true,
        child: FadeTransition(
          opacity: ReverseAnimation(_exit),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _play
                    ? const [LaunchSplash.background, Color(0xFF1A2C7A), AppColors.purpleDark]
                    : const [LaunchSplash.background, KidsColors.tealDeep, KidsColors.teal],
                stops: const [0, 0.6, 1],
              ),
            ),
            child: AnimatedBuilder(
              animation: _reveal,
              builder: (context, _) => _play
                  ? _PlayContent(t: _reveal.value, animate: !_reduced)
                  : _KidsContent(t: _reveal.value, animate: !_reduced),
            ),
          ),
        ),
      ),
    );
  }
}

double _interval(double t, double begin, double end, Curve curve) =>
    curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

double _logoWidth(BuildContext context) => (MediaQuery.sizeOf(context).width * 0.62).clamp(160.0, 300.0);

/// Zad X Play: logo, "Zad X" wordmark, a fine gold rule and the identity line (Arabic, English).
class _PlayContent extends StatelessWidget {
  const _PlayContent({required this.t, required this.animate});

  /// Reveal progress 0 → 1.
  final double t;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final logo = _interval(t, 0, 0.5, Curves.easeOutCubic);
    final word = _interval(t, 0.2, 0.7, Curves.easeOutCubic);
    final line = _interval(t, 0.45, 0.9, Curves.easeOutCubic);
    final shine = animate ? _interval(t, 0.55, 1, Curves.easeInOut) : 1.0;
    final logoWidth = _logoWidth(context);

    return Stack(fit: StackFit.expand, children: [
      // Soft glow behind the logo.
      Center(
        child: Opacity(
          opacity: 0.55 * logo,
          child: Container(
            width: logoWidth * 1.5,
            height: logoWidth * 1.5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0x666C3BEB), Color(0x006C3BEB)]),
            ),
          ),
        ),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: logo,
              child: Transform.scale(
                scale: 0.9 + 0.1 * logo,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BrandLogo(width: logoWidth, height: logoWidth * 0.66, variant: AppVariant.islamic),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Opacity(
              opacity: word,
              child: Transform.scale(
                scale: 0.94 + 0.06 * word,
                child: _Shimmer(progress: shine, enabled: animate, child: const _PlayWordmark()),
              ),
            ),
            const SizedBox(height: 14),
            Opacity(
              opacity: line,
              child: Transform.translate(offset: Offset(0, 6 * (1 - line)), child: const _IdentityLine()),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// "Zad X" in the platform's default font (bundled with the OS, nothing downloaded).
class _PlayWordmark extends StatelessWidget {
  const _PlayWordmark();

  @override
  Widget build(BuildContext context) => const Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Zad ', style: TextStyle(color: Colors.white)),
          TextSpan(text: 'X', style: TextStyle(color: AppColors.yellow)),
        ]),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 56,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          height: 1.1,
          decoration: TextDecoration.none,
          shadows: [Shadow(color: Color(0x806C3BEB), blurRadius: 24)],
        ),
      );
}

/// The Zad X Play identity line: a fine gold rule, then Arabic over English.
/// Warm cream on navy/purple: ≥ 8.4:1 (Arabic) and ≥ 7.8:1 (English) at every point of the gradient.
class _IdentityLine extends StatelessWidget {
  const _IdentityLine();

  static const _cream = Color(0xFFFFEFC7);
  static const _soft = Color(0xFFE9E4FF);

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 28, height: 1.2, color: AppColors.yellow.withValues(alpha: 0.7)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Transform.rotate(
              angle: 0.785398, // a small gold diamond
              child: Container(width: 6, height: 6, color: AppColors.yellow),
            ),
          ),
          Container(width: 28, height: 1.2, color: AppColors.yellow.withValues(alpha: 0.7)),
        ]),
        const SizedBox(height: 12),
        const Text(
          IslamicBrand.identityAr,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _cream, height: 1.3, decoration: TextDecoration.none),
        ),
        const SizedBox(height: 4),
        const Text(
          IslamicBrand.identityEn,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.4,
            color: _soft,
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
      ]);
}

/// Zad X Kids: the Latin "ZAD X KIDS" wordmark on a white badge, with soft sun and coral light.
class _KidsContent extends StatelessWidget {
  const _KidsContent({required this.t, required this.animate});

  final double t;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final light = _interval(t, 0, 0.6, Curves.easeOutCubic);
    final badge = _interval(t, 0.1, 0.65, Curves.easeOutBack);
    final shine = animate ? _interval(t, 0.55, 1, Curves.easeInOut) : 1.0;
    final size = MediaQuery.sizeOf(context);
    final logoWidth = _logoWidth(context);

    Widget glow(Alignment at, double d, Color c, double alpha) => Align(
          alignment: at,
          child: Opacity(
            opacity: light,
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)]),
              ),
            ),
          ),
        );

    return Stack(fit: StackFit.expand, children: [
      // Sun-yellow light top-end, coral light bottom-start, a hint of mint in the middle.
      glow(const Alignment(0.95, -0.85), size.shortestSide * 0.9, KidsColors.sun, 0.45),
      glow(const Alignment(-1.0, 0.95), size.shortestSide * 0.8, KidsColors.coral, 0.4),
      glow(Alignment.center, logoWidth * 1.6, KidsColors.mint, 0.22),
      // A few playful dots (static, fade in with the light).
      for (final (x, y, d, c) in const [
        (-0.7, -0.55, 14.0, KidsColors.sun),
        (0.78, 0.42, 18.0, KidsColors.coral),
        (-0.55, 0.62, 10.0, KidsColors.mint),
        (0.6, -0.5, 9.0, KidsColors.mint),
      ])
        Align(
          alignment: Alignment(x, y),
          child: Opacity(
            opacity: 0.8 * light,
            child: Container(width: d, height: d, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          ),
        ),
      Center(
        child: Opacity(
          opacity: badge.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.88 + 0.12 * badge,
            child: _Shimmer(
              progress: shine,
              enabled: animate,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: BrandLogo(width: logoWidth, height: logoWidth * 0.62, variant: AppVariant.kids),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// One soft light band sweeping across [child].
class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.progress, required this.enabled, required this.child});

  final double progress;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || progress <= 0 || progress >= 1) return child;
    final x = -1.0 + 3.0 * progress; // band centre moves from -1 to 2 (beyond the child)
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
        stops: [
          (x - 0.25).clamp(0.0, 1.0),
          x.clamp(0.0, 1.0),
          (x + 0.25).clamp(0.0, 1.0),
        ],
      ).createShader(rect),
      child: child,
    );
  }
}
