import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../core/widgets/deen_icons.dart';
import '../../../domain/song/song_validation.dart';
import 'credits_pill.dart';
import 'step_indicator.dart';

/// Header of the Create Song screen: masjid artwork, brand bar with credits,
/// the screen title, and the step indicator.
class CreateSongHeader extends ConsumerWidget {
  const CreateSongHeader({
    super.key,
    required this.onBack,
    required this.onCreditsTap,
    required this.onStepTap,
  });

  final VoidCallback onBack;
  final VoidCallback onCreditsTap;
  final ValueChanged<SongStep> onStepTap;

  /// Height of the header below the status-bar inset.
  static const double contentHeight = 207.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(stepProgressProvider);
    final safeTop = MediaQuery.paddingOf(context).top;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: contentHeight + safeTop),
      child: Stack(
        children: [
          const Positioned.fill(child: _HeaderBackground()),
          const Positioned.fill(child: _HeaderLattice()),
          Positioned(
            top: safeTop + 62,
            left: 15,
            width: 205,
            height: 0.5,
            child: const _Hairline(),
          ),
          Positioned(top: safeTop, right: 0, child: const _MasjidArtwork()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, safeTop + 16.5, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(onBack: onBack, onCreditsTap: onCreditsTap),
                    const SizedBox(height: 17.6),
                    Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text.rich(
                              const TextSpan(
                                children: [
                                  TextSpan(text: 'Create '),
                                  TextSpan(
                                    text: 'Song',
                                    style: TextStyle(color: DeenColors.gold),
                                  ),
                                ],
                              ),
                              style: DeenText.screenTitle,
                            ),
                          ),
                          const SizedBox(height: 8.3),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              'Turn your ideas into beautiful Islamic songs '
                              'using AI and your own voice.',
                              style: DeenText.screenSubtitle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9.9),
              StepIndicator(active: progress.active, onStepTap: onStepTap),
              const SizedBox(height: 13.9),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onCreditsTap});

  final VoidCallback onBack;
  final VoidCallback onCreditsTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            onTap: onBack,
            child: Material(
              color: const Color(0xFF0C181A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
                side: const BorderSide(color: Color(0xFF2A3739), width: 0.75),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: onBack,
                child: const SizedBox(
                  width: 35,
                  height: 35,
                  child: Icon(
                    LucideIcons.arrowLeft,
                    size: 17,
                    color: DeenColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Deen',
                        style: TextStyle(color: DeenColors.gold),
                      ),
                      TextSpan(
                        text: 'Voice',
                        style: TextStyle(color: DeenColors.textPrimary),
                      ),
                    ],
                  ),
                  style: DeenText.wordmark(DeenColors.textPrimary),
                ),
                const SizedBox(height: 4.65),
                Text(
                  'AI NASHEEDS FOR A BRIGHTER UMMAH',
                  style: DeenText.tagline,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 3.5),
            child: CreditsPill(onTap: onCreditsTap),
          ),
        ],
      ),
    );
  }
}

class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF021612), DeenColors.background],
        ),
      ),
    );
  }
}

/// The illuminated masjid scene, faded into the background on its left and
/// bottom edges.
///
/// The asset is 412 x 300 px extracted from the design reference, shown at its
/// native 2x size (206 x 150 pt). See assets/README.md for provenance and the
/// resolution limit.
class _MasjidArtwork extends StatelessWidget {
  const _MasjidArtwork();

  static const double width = 206;
  static const double height = 150;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, Colors.black],
            stops: [0.0, 0.16],
          ).createShader(rect),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0.0, 0.78, 1.0],
            ).createShader(rect),
            child: Image.asset(
              'assets/art/masjid_header.webp',
              width: width,
              height: height,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet lattice that fades out toward the artwork and the bottom edge.
class _HeaderLattice extends StatelessWidget {
  const _HeaderLattice();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const RadialGradient(
          center: Alignment(-1, -1),
          radius: 1.05,
          colors: [Colors.black, Colors.transparent],
        ).createShader(rect),
        child: CustomPaint(
          painter: LatticePainter(
            color: DeenColors.gold.withValues(alpha: 0.075),
          ),
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
        ),
      ),
    );
  }
}
