import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../application/session_controller.dart';
import '../../core/theme/deen_theme.dart';
import '../../core/widgets/brand.dart';
import '../../domain/failures.dart';
import '../shared/dialogs.dart';
import '../shared/language_sheet.dart';

/// The signed-out screen: the DeenVoice welcome, and email sign-in or account
/// creation in the same card.
///
/// Google and Apple sign-in are shown, as designed, but disabled and labelled:
/// they are not built, and the app does not pretend otherwise.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _Mode { options, email }

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const _maxWidth = 480.0;

  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.options;
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _problem() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (_creating && _password.text.length < 10) {
      return 'Use a password of at least 10 characters.';
    }
    if (_password.text.isEmpty) return 'Enter your password.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      if (_creating) {
        await session.register(_email.text, _password.text);
      } else {
        await session.signIn(_email.text, _password.text);
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showEmail() => setState(() {
    _mode = _Mode.email;
    _error = null;
  });

  void _showOptions() => setState(() {
    _mode = _Mode.options;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width, _maxWidth);
    final heroHeight = width * 700 / 852;
    final safeTop = MediaQuery.paddingOf(context).top;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: _mode == _Mode.options,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showOptions();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: DeenColors.background,
        body: Stack(
          children: [
            const Positioned.fill(child: _Ground()),
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: insets),
                  child: Column(
                    children: [
                      // The wordmark sits over the foot of the artwork, as in the
                      // reference: the art paints past the space it takes.
                      Align(
                        alignment: Alignment.topCenter,
                        heightFactor: (heroHeight - 2) / heroHeight,
                        child: SizedBox(
                          height: heroHeight,
                          child: _Hero(safeTop: safeTop, width: width),
                        ),
                      ),
                      Semantics(
                        header: true,
                        child: const DeenWordmark(fontSize: 41),
                      ),
                      const SizedBox(height: 3),
                      ExcludeSemantics(
                        child: Text(
                          'AI NASHEEDS FOR A BRIGHTER UMMAH',
                          style: DeenText.taglineLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: _ArchCard(
                          child: _mode == _Mode.options
                              ? _Options(onEmail: _showEmail)
                              : _EmailForm(
                                  email: _email,
                                  password: _password,
                                  creating: _creating,
                                  busy: _busy,
                                  error: _error,
                                  onSubmit: _submit,
                                  onToggle: () => setState(() {
                                    _creating = !_creating;
                                    _error = null;
                                  }),
                                  onBack: _showOptions,
                                ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deep green that deepens toward the bottom, as in the reference.
class _Ground extends StatelessWidget {
  const _Ground();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF001B12), Color(0xFF001A12), DeenColors.background],
        stops: [0, 0.55, 1],
      ),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.safeTop, required this.width});

  final double safeTop;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Positions are the reference's (852 px wide) halved, scaled to this width.
    final k = width / 426;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.9, 1],
              ).createShader(rect),
              child: Image.asset(
                'assets/art/login_hero.webp',
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        Positioned(
          // Where the reference has it (under a 44 pt status bar), or just below
          // a taller one.
          top: math.max(53 * k, safeTop + 9),
          right: 17 * k,
          child: const _LanguagePill(),
        ),
        Positioned(
          top: 234 * k,
          left: 0,
          right: 0,
          child: Center(child: DeenAppIcon(size: 102 * k, glow: true)),
        ),
      ],
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Language: English',
      excludeSemantics: true,
      child: Material(
        color: const Color(0xB3081513),
        shape: StadiumBorder(
          side: BorderSide(
            color: DeenColors.goldBorder.withValues(alpha: 0.55),
            width: 0.9,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showLanguageSheet(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.globe, size: 15, color: DeenColors.goldBorder),
                SizedBox(width: 6),
                Text('English', style: _pillText),
                SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: DeenColors.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _pillText = TextStyle(
  fontFamily: 'Inter',
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: DeenColors.textPrimary,
);

// --- The card --------------------------------------------------------------

class _ArchCard extends StatelessWidget {
  const _ArchCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArchPainter(),
      child: ClipPath(
        clipper: _ArchClipper(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 78),
          child: child,
        ),
      ),
    );
  }
}

/// The card outline: rounded at the top, and at the bottom the pointed arch of
/// the reference.
Path _archPath(Size size) {
  const r = 26.0;
  final w = size.width;
  final h = size.height;
  final shoulder = h - 64;
  return Path()
    ..moveTo(0, r)
    ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
    ..lineTo(w - r, 0)
    ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
    ..lineTo(w, shoulder)
    ..cubicTo(
      w,
      shoulder + 26,
      w * 0.82,
      shoulder + 36,
      w * 0.66,
      shoulder + 42,
    )
    ..cubicTo(w * 0.57, shoulder + 45, w * 0.53, shoulder + 52, w * 0.5, h)
    ..cubicTo(
      w * 0.47,
      shoulder + 52,
      w * 0.43,
      shoulder + 45,
      w * 0.34,
      shoulder + 42,
    )
    ..cubicTo(w * 0.18, shoulder + 36, 0, shoulder + 26, 0, shoulder)
    ..close();
}

class _ArchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _archPath(size);

  @override
  bool shouldReclip(_ArchClipper oldClipper) => false;
}

class _ArchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _archPath(size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE60A1A17), Color(0xE6071513), Color(0xE603211A)],
          stops: [0, 0.7, 1],
        ).createShader(Offset.zero & size),
    );
    // A faint full outline, with the gold weighted toward the arch.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = DeenColors.panelEdge,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            DeenColors.goldBorder.withValues(alpha: 0),
            DeenColors.goldBorder.withValues(alpha: 0.05),
            DeenColors.goldBorder,
          ],
          stops: const [0, 0.72, 0.9],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ArchPainter oldDelegate) => false;
}

// --- Sign-in options --------------------------------------------------------

class _Options extends ConsumerWidget {
  const _Options({required this.onEmail});

  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Welcome Back',
            style: DeenText.authTitle,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 244),
            child: Text(
              'Sign in to continue creating beautiful Islamic songs with AI.',
              style: DeenText.authSubtitle,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const _ProviderButton(
          label: 'Continue with Google',
          leading: GoogleGMark(size: 20),
          background: Color(0xFFF0F0F0),
          foreground: Color(0xFF1F1F1F),
        ),
        const SizedBox(height: 12),
        const _ProviderButton(
          label: 'Continue with Apple',
          leading: Icon(Icons.apple, size: 24, color: Colors.white),
          background: Colors.black,
          foreground: Colors.white,
          border: DeenColors.borderStrong,
        ),
        const SizedBox(height: 10),
        Text(
          'Google and Apple sign-in aren’t available yet. Use email.',
          style: DeenText.sectionHint,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        const _OrDivider(),
        const SizedBox(height: 14),
        Semantics(
          button: true,
          label: 'Continue with Email',
          excludeSemantics: true,
          onTap: onEmail,
          child: Material(
            color: const Color(0xFF051F19),
            shape: StadiumBorder(
              side: BorderSide(
                color: DeenColors.goldBorder.withValues(alpha: 0.85),
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onEmail,
              child: SizedBox(
                height: 45,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned(
                      left: 31,
                      child: Icon(
                        LucideIcons.mail,
                        size: 20,
                        color: DeenColors.textPrimary,
                      ),
                    ),
                    Text('Continue with Email', style: DeenText.authButton),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _LegalNote(),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.leading,
    required this.background,
    required this.foreground,
    this.border,
  });

  final String label;
  final Widget leading;
  final Color background;
  final Color foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: false,
      label: '$label, not available yet',
      excludeSemantics: true,
      child: Opacity(
        opacity: 0.5,
        child: Container(
          height: 45,
          decoration: ShapeDecoration(
            color: background,
            shape: StadiumBorder(
              side: border == null
                  ? BorderSide.none
                  : BorderSide(color: border!),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(left: 31, child: leading),
              Text(
                label,
                style: DeenText.authButton.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: Divider(height: 1, thickness: 0.8, color: Color(0xFF364240)),
    );
    return ExcludeSemantics(
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('OR', style: DeenText.authNote),
          ),
          line,
        ],
      ),
    );
  }
}

/// "By continuing, you agree to our Terms of Service and Privacy Policy." only
/// when both documents exist. Otherwise the app says so instead of pointing at
/// pages that are not there.
class _LegalNote extends ConsumerStatefulWidget {
  const _LegalNote();

  @override
  ConsumerState<_LegalNote> createState() => _LegalNoteState();
}

class _LegalNoteState extends ConsumerState<_LegalNote> {
  final _terms = TapGestureRecognizer();
  final _privacy = TapGestureRecognizer();

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(Uri? url) async {
    if (url == null) return;
    final ok = await ref.read(linkOpenerProvider).open(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('That page couldn’t be opened.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = ref.watch(legalLinksProvider);
    if (!links.hasBoth) {
      return Text(
        'Terms of Service and Privacy Policy aren’t published for this '
        'build yet.',
        style: DeenText.authNote,
        textAlign: TextAlign.center,
      );
    }
    _terms.onTap = () => _open(links.terms);
    _privacy.onTap = () => _open(links.privacy);
    const link = TextStyle(color: DeenColors.gold);
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      style: DeenText.authNote,
      textAlign: TextAlign.center,
    );
  }
}

// --- Email ------------------------------------------------------------------

class _EmailForm extends StatelessWidget {
  const _EmailForm({
    required this.email,
    required this.password,
    required this.creating,
    required this.busy,
    required this.error,
    required this.onSubmit,
    required this.onToggle,
    required this.onBack,
  });

  final TextEditingController email;
  final TextEditingController password;
  final bool creating;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onToggle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              creating ? 'Create your account' : 'Sign in with email',
              style: DeenText.authTitle.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your voice recordings and songs are private to your account.',
            style: DeenText.authSubtitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: email,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            style: DeenText.input,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            autofillHints: [
              creating ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            style: DeenText.input,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: creating ? 'At least 10 characters' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(error!, style: DeenText.error),
            ),
          ],
          if (!creating)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => _showForgotPassword(context),
                child: const Text('Forgot password?'),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: busy ? null : onSubmit,
              child: Text(
                busy
                    ? 'Please wait…'
                    : (creating ? 'Create account' : 'Sign in'),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: busy ? null : onToggle,
            child: Text(
              creating ? 'I already have an account' : 'Create a new account',
            ),
          ),
          TextButton(
            onPressed: busy ? null : onBack,
            child: const Text('Other ways to continue'),
          ),
        ],
      ),
    );
  }
}

/// There is no password reset: the service cannot send email yet. Say so,
/// rather than offering a link that leads nowhere.
void _showForgotPassword(BuildContext context) {
  showInfoDialog(
    context,
    title: 'Password reset isn’t available yet',
    message:
        'DeenVoice can’t send email yet, so a reset link can’t be sent. If you '
        'can’t sign in, you can create a new account with a different email '
        'address. Songs and voices in the old account can’t be moved over.',
  );
}
