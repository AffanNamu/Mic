import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/deen_theme.dart';
import '../../../domain/song/song_validation.dart';

/// The four-stage progress indicator. Progress is linear: stages before the
/// active one are finished (check), the active stage is gold, later stages are
/// muted. [active] comes from the real draft, so it advances as the user
/// completes each part. Tapping a stage scrolls to its section.
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.active,
    required this.onStepTap,
  });

  final SongStep active;
  final ValueChanged<SongStep> onStepTap;

  static const double circle = 22;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final column = constraints.maxWidth / SongStep.values.length;
          return Stack(
            children: [
              Positioned(
                left: column / 2,
                right: column / 2,
                top: circle / 2 - 0.75,
                child: Container(height: 1.5, color: const Color(0xFF1F2D2E)),
              ),
              Row(
                children: [
                  for (final step in SongStep.values)
                    Expanded(
                      child: _StepColumn(
                        step: step,
                        number: step.index + 1,
                        isActive: step == active,
                        isDone: step.index < active.index,
                        onTap: () => onStepTap(step),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StepColumn extends StatelessWidget {
  const _StepColumn({
    required this.step,
    required this.number,
    required this.isActive,
    required this.isDone,
    required this.onTap,
  });

  final SongStep step;
  final int number;
  final bool isActive;
  final bool isDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = isActive
        ? 'current step'
        : isDone
        ? 'completed'
        : 'not started';
    return Semantics(
      button: true,
      selected: isActive,
      label: 'Step $number, ${step.label}, $status',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Bubble(number: number, isActive: isActive, isDone: isDone),
            const SizedBox(height: 7.8),
            Text(
              step.label,
              textAlign: TextAlign.center,
              style: isActive
                  ? DeenText.stepLabel
                  : DeenText.stepLabel.copyWith(
                      color: DeenColors.textSecondary,
                      fontWeight: FontWeight.w400,
                      fontVariations: const [FontVariation('wght', 400)],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.number,
    required this.isActive,
    required this.isDone,
  });

  final int number;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    const size = StepIndicator.circle;
    if (isActive) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [DeenColors.goldBright, DeenColors.goldDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: DeenColors.gold.withValues(alpha: 0.35),
              blurRadius: 8,
            ),
          ],
        ),
        child: Text(
          '$number',
          style: DeenText.stepNumber.copyWith(color: DeenColors.onGold),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0E1618),
        border: Border.all(
          color: isDone ? DeenColors.goldBorder : const Color(0xFF3A4547),
          width: 0.75,
        ),
      ),
      child: isDone
          ? const Icon(LucideIcons.check, size: 11, color: DeenColors.gold)
          : Text('$number', style: DeenText.stepNumber),
    );
  }
}
