import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/onboarding_controller.dart';
import '../../core/theme/deen_theme.dart';

/// Three short pages shown once, the first time the app opens. What they say is
/// what the app does: nothing here promises a result the engine may not give.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    LucideIcons.mic,
    'Songs in your own voice',
    'Add your voice, write or paste your lyrics and choose a style. DeenVoice '
        'sends them to an AI music engine and brings back a finished song.',
  ),
  _Page(
    LucideIcons.shieldCheck,
    'Only voices you may use',
    'Before a voice is saved you confirm it is yours, or that its owner '
        'agreed. Recordings stay private to your account and you can delete '
        'them at any time. A music provider may keep its own copy a while '
        'longer, and the app tells you when that applies.',
  ),
  _Page(
    LucideIcons.languages,
    'Hausa, Arabic and English',
    'Write lyrics in any of them, or mix them. What can be sung depends on '
        'the music engine, and the app checks before it uses a credit.',
  ),
];

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _index == _pages.length - 1;

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(onboardingCompletedProvider.notifier).complete();
  }

  void _next() {
    if (_last) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _controller.previousPage(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned(top: 0, left: 0, right: 0, child: _Backdrop()),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                          child: Opacity(
                            opacity: _last ? 0 : 1,
                            child: TextButton(
                              onPressed: _last || _finishing ? null : _finish,
                              child: const Text('Skip'),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: _pages.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (context, i) =>
                              _PageView(page: _pages[i]),
                        ),
                      ),
                      Semantics(
                        label: 'Page ${_index + 1} of ${_pages.length}',
                        liveRegion: true,
                        child: ExcludeSemantics(child: _Dots(index: _index)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _finishing ? null : _next,
                            child: Text(_last ? 'Get started' : 'Next'),
                          ),
                        ),
                      ),
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

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 320,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ).createShader(rect),
        child: Image.asset(
          'assets/art/home_hero.webp',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    // Top-aligned, so the icon is in the same place on every page.
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DeenColors.panel,
                border: Border.all(color: DeenColors.goldBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: DeenColors.gold.withValues(alpha: 0.25),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: Icon(page.icon, size: 40, color: DeenColors.gold),
            ),
            const SizedBox(height: 36),
            Semantics(
              header: true,
              child: Text(
                page.title,
                textAlign: TextAlign.center,
                style: DeenText.onboardTitle,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              page.body,
              textAlign: TextAlign.center,
              style: DeenText.authSubtitle.copyWith(fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < _pages.length; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == index ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: i == index ? DeenColors.gold : DeenColors.borderStrong,
          ),
        ),
    ],
  );
}
