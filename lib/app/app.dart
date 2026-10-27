import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/onboarding_controller.dart';
import '../application/providers.dart';
import '../application/session_controller.dart';
import '../core/theme/deen_theme.dart';
import '../core/widgets/brand.dart';
import '../presentation/auth/welcome_screen.dart';
import '../presentation/onboarding/onboarding_screen.dart';
import '../presentation/shell/app_shell.dart';

class DeenVoiceApp extends StatefulWidget {
  /// [home] replaces the launch flow. Tests use it to open one screen on its
  /// own; the shipped app never passes it.
  const DeenVoiceApp({super.key, this.home});

  final Widget? home;

  @override
  State<DeenVoiceApp> createState() => _DeenVoiceAppState();
}

class _DeenVoiceAppState extends State<DeenVoiceApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'DeenVoice',
      debugShowCheckedModeBanner: false,
      theme: buildDeenTheme(),
      builder: (context, child) {
        // Honour the user's text-size setting, but cap it: the reference
        // layout is dense and would break past ~1.3x.
        final scaler = MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 1, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: _SessionGuard(navigator: _navigator, child: child!),
        );
      },
      home: widget.home ?? const _Root(),
    );
  }
}

/// When the signed-in user is signed out (they chose to, the server ended the
/// session, or the account was deleted) every screen they had open is closed,
/// so nothing of theirs stays on screen over the welcome screen.
///
/// It sits above the navigator, not on a screen: a screen covered by another
/// stops listening, and this must hear it however deep the user is.
class _SessionGuard extends ConsumerWidget {
  const _SessionGuard({required this.navigator, required this.child});

  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.value != null && next.value == null) {
        navigator.currentState?.popUntil((route) => route.isFirst);
      }
    });
    return child;
  }
}

/// First launch: the introduction. After that, with a backend, the welcome
/// screen until someone is signed in, then the app. Without a backend there is
/// no account, and the app opens straight to Home with every feature saying
/// honestly that it is not connected.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardingCompletedProvider);
    if (onboarded.isLoading) return const _Splash();
    // A failure to read the flag must not lock the user out: show the app.
    if (onboarded.value == false) return const OnboardingScreen();
    if (ref.watch(apiBaseUrlProvider).isEmpty) return const AppShell();
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => const _Splash(),
      error: (_, _) => const WelcomeScreen(),
      data: (s) => s == null ? const WelcomeScreen() : const AppShell(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: DeenAppIcon(size: 96, glow: true)));
}
