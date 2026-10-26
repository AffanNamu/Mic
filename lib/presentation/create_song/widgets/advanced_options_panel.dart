import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../domain/generation/advanced_options.dart';
import '../../../domain/generation/generation_capabilities.dart';

/// Collapsible advanced settings. Only options the connected engine supports
/// are editable; the rest are shown disabled with the reason, never as if they
/// worked.
class AdvancedOptionsPanel extends ConsumerStatefulWidget {
  const AdvancedOptionsPanel({super.key});

  @override
  ConsumerState<AdvancedOptionsPanel> createState() =>
      _AdvancedOptionsPanelState();
}

class _AdvancedOptionsPanelState extends ConsumerState<AdvancedOptionsPanel> {
  bool _expanded = false;

  static const _fill = Color(0xFF0A1717);
  static const _border = Color(0xFF243031);

  @override
  Widget build(BuildContext context) {
    final capabilities =
        ref.watch(capabilitiesProvider).value ?? GenerationCapabilities.none;
    final chosen = ref.watch(songDraftProvider.select((s) => s.draft.advanced));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: 'Advanced Options. Pitch, vocal style, arrangement, more.',
          excludeSemantics: true,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Material(
            color: _fill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _border, width: 0.75),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 34.5),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9.5, 6, 11, 6),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.settings,
                        size: 16,
                        color: DeenColors.textPrimary,
                      ),
                      const SizedBox(width: 11.5),
                      Text('Advanced Options', style: DeenText.advancedTitle),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pitch, vocal style, arrangement, more',
                          style: DeenText.advancedHint,
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          LucideIcons500.chevronDown,
                          size: 14,
                          color: DeenColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                    decoration: BoxDecoration(
                      color: _fill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border, width: 0.75),
                    ),
                    child: _Body(capabilities: capabilities, chosen: chosen),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.capabilities, required this.chosen});

  final GenerationCapabilities capabilities;
  final Map<String, String> chosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = capabilities.engineName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          engine == null
              ? 'These settings depend on the generation engine. No engine '
                    'is connected yet, so they can’t be changed.'
              : 'Settings supported by $engine can be changed. Others are '
                    'shown for reference only.',
          style: DeenText.sectionHint,
        ),
        for (final option in advancedOptionCatalogue)
          _OptionRow(
            option: option,
            supported: capabilities.advancedOptionIds.contains(option.id),
            engineName: engine,
            value: chosen[option.id] ?? option.defaultValue,
            onChanged: (v) =>
                ref.read(songDraftProvider.notifier).setAdvanced(option.id, v),
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.supported,
    required this.engineName,
    required this.value,
    required this.onChanged,
  });

  final AdvancedOption option;
  final bool supported;
  final String? engineName;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: supported ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(top: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(option.label, style: DeenText.fieldLabel),
                if (!supported) ...[
                  const SizedBox(width: 8),
                  Text(
                    engineName == null
                        ? 'Unavailable'
                        : 'Not supported by $engineName',
                    style: DeenText.sectionHint,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (wire, label) in option.choices)
                  _Choice(
                    label: label,
                    selected: wire == value,
                    enabled: supported,
                    onTap: () => onChanged(wire),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        color: selected ? DeenColors.selectedFill : DeenColors.field,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? DeenColors.goldBorder : DeenColors.border,
            width: 0.75,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              style: DeenText.chipLabel.copyWith(
                color: selected ? DeenColors.gold : DeenColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
