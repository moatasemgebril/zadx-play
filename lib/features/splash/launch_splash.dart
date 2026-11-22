import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Brand launch screen: the "Zad X" wordmark (always in Latin letters, also in Arabic)
/// on a soft navy → purple gradient, shown while the start-up work in `main()` runs.
///
/// * The native splash (Android `launch_background`, iOS `LaunchScreen.storyboard`) uses
///   [LaunchSplash.background] so there is no white flash before the first Flutter frame.
/// * The reveal (fade + scale + one shimmer pass) takes [revealDuration] (≤ 1.6 s together
///   with the exit fade). The app is built underneath while it plays, so start-up is not
///   delayed: the splash leaves as soon as both the reveal and the app are ready.
/// * Reduced motion (`MediaQuery.disableAnimations`): no animation, the wordmark is shown
///   for [reducedMotionHold] and then the app appears without a fade.
/// * Bundled assets and the platform default font only: no network, no runtime font download.
class LaunchSplash {
  const LaunchSplash._();

  /// Same colour as the native launch background (android `zadx_splash_bg`, iOS storyboard).
  static const background = AppColors.navy;

  static const revealDuration = Duration(milliseconds: 1300);
  static const exitDuration = Duration(milliseconds: 300);
  static const reducedMotionHold = Duration(milliseconds: 500);

  /// Shows the splash right away (`runApp`) and returns a handle. Hand the real app to
  /// [LaunchSplashHandle.complete] once start-up is done.
  static LaunchSplashHandle show() {
    final handle = LaunchSplashHandle();
    runApp(LaunchSplashHost(app: handle.app));
    return handle;
  }
}

/// Passes the real app to the splash when start-up is done.
class LaunchSplashHandle {
  final _app = Completer<Widget>();

  Future<Widget> get app => _app.future;

  void complete(Widget app) {
    if (!_app.isCompleted) _app.complete(app);
  }
}

/// Root widget during start-up: the app (once ready) underneath, the splash on top until
/// it has finished, then only the app. The app keeps its state when the splash leaves.
class LaunchSplashHost extends StatefulWidget {
  const LaunchSplashHost({
    super.key,
    required this.app,
    this.revealDuration = LaunchSplash.revealDuration,
    this.exitDuration = LaunchSplash.exitDuration,
    this.reducedMotionHold = LaunchSplash.reducedMotionHold,
  });

  final Future<Widget> app;
  final Duration revealDuration;
  final Duration exitDuration;
  final Duration reducedMotionHold;

  @override
  State<LaunchSplashHost> createState() => _LaunchSplashHostState();
}

class _LaunchSplashHostState extends State<LaunchSplashHost> {
  static const _appKey = ValueKey('zadx-app');
  static const _splashKey = ValueKey('zadx-splash');

  Widget? _app;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    widget.app.then((app) {
      if (mounted) setState(() => _app = app);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        if (app != null)
          // Hidden from screen readers while the splash covers it.
          ExcludeSemantics(key: _appKey, excluding: !_splashDone, child: app),
        if (!_splashDone)
          MediaQuery.fromView(
            key: _splashKey,
            view: View.of(context),
            child: Directionality(
              // The wordmark is Latin, so it always reads left to right (RTL app included).
              textDirection: TextDirection.ltr,
              child: _SplashStage(
                appReady: app != null,
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
    required this.appReady,
    required this.revealDuration,
    required this.exitDuration,
    required this.reducedMotionHold,
    required this.onFinished,
  });

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
      precacheImage(const AssetImage(_logoAsset), context, onError: (_, __) {});
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
        label: 'Zad X',
        container: true,
        excludeSemantics: true,
        child: FadeTransition(
          opacity: ReverseAnimation(_exit),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [LaunchSplash.background, Color(0xFF1A2C7A), AppColors.purpleDark],
                stops: [0, 0.6, 1],
              ),
            ),
            child: AnimatedBuilder(
              animation: _reveal,
              builder: (context, _) => _SplashContent(t: _reveal.value, animate: !_reduced),
            ),
          ),
        ),
      ),
    );
  }
}

const _logoAsset = 'assets/images/zadx_logo.jpg';

class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.t, required this.animate});

  /// Reveal progress 0 → 1.
  final double t;
  final bool animate;

  static double _interval(double t, double begin, double end, Curve curve) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final logo = _interval(t, 0, 0.5, Curves.easeOutCubic);
    final word = _interval(t, 0.2, 0.7, Curves.easeOutCubic);
    final shine = animate ? _interval(t, 0.55, 1, Curves.easeInOut) : 1.0;
    final width = MediaQuery.sizeOf(context).width;
    final logoWidth = (width * 0.62).clamp(160.0, 300.0);

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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
            opacity: logo,
            child: Transform.scale(
              scale: 0.9 + 0.1 * logo,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  _logoAsset,
                  width: logoWidth,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => SizedBox(width: logoWidth),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Opacity(
            opacity: word,
            child: Transform.scale(
              scale: 0.94 + 0.06 * word,
              child: _Shimmer(progress: shine, enabled: animate, child: const _Wordmark()),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// "Zad X" in the platform's default font (bundled with the OS, nothing downloaded).
class _Wordmark extends StatelessWidget {
  const _Wordmark();

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

/// One soft light band sweeping across the wordmark.
class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.progress, required this.enabled, required this.child});

  final double progress;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || progress <= 0 || progress >= 1) return child;
    final x = -1.0 + 3.0 * progress; // band centre moves from -1 to 2 (beyond the text)
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
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
