import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

import '../../../core/theme/deen_theme.dart';
import '../../../domain/song/song_options.dart';
import '../../shared/option_picker_sheet.dart';

const double _boxRadius = 10;

/// A bordered field whose [label] sits as a dark chip across the top border.
class ChipLabeledFrame extends StatelessWidget {
  const ChipLabeledFrame({
    super.key,
    required this.label,
    required this.child,
    this.hasError = false,
    this.height = 38.5,
  });

  final String label;
  final Widget child;
  final bool hasError;
  final double height;

  static const double chipOverhang = 6.5;

  @override
  Widget build(BuildContext context) {
    // Grows with the user's text size so a larger font never overflows it.
    final scaledHeight = height * MediaQuery.textScalerOf(context).scale(1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(top: chipOverhang),
          height: scaledHeight,
          decoration: _boxDecoration(hasError: hasError),
          child: child,
        ),
        Positioned(
          left: 2,
          top: 2.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF06120F),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label, style: DeenText.fieldLabel),
          ),
        ),
      ],
    );
  }
}

BoxDecoration _boxDecoration({bool hasError = false}) => BoxDecoration(
  color: DeenColors.field,
  borderRadius: BorderRadius.circular(_boxRadius),
  border: Border.all(
    color: hasError ? DeenColors.danger : DeenColors.border,
    width: 0.75,
  ),
);

/// Tappable select box: leading icon, value (+ optional subtitle), chevron.
class SelectBox extends StatelessWidget {
  const SelectBox({
    super.key,
    required this.icon,
    required this.value,
    required this.onTap,
    required this.semanticLabel,
    this.subtitle,
    this.valueStyle,
    this.height = 35,
  });

  final Widget icon;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;
  final String semanticLabel;
  final TextStyle? valueStyle;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semanticLabel: $value${subtitle == null ? '' : ', $subtitle'}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(_boxRadius),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.fromLTRB(11, 4, 8, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_boxRadius),
            ),
            child: Row(
              children: [
                SizedBox(width: 13, child: Center(child: icon)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: valueStyle ?? DeenText.fieldValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: DeenText.fieldSubvalue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  LucideIcons500.chevronDown,
                  size: 13,
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

/// A [SelectBox] inside a bordered frame with its label above it.
class LabeledSelect<T extends SongOption> extends StatelessWidget {
  const LabeledSelect({
    super.key,
    required this.label,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final Widget icon;
  final List<T> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DeenText.fieldLabel),
        const SizedBox(height: 1.8),
        DecoratedBox(
          decoration: _boxDecoration(),
          child: _pickerBox(context, label: label, icon: icon),
        ),
      ],
    );
  }

  Widget _pickerBox(
    BuildContext context, {
    required String label,
    required Widget icon,
  }) {
    return SelectBox(
      icon: icon,
      value: selected.label,
      subtitle: selected.subtitle,
      semanticLabel: label,
      onTap: () async {
        final choice = await showOptionPicker<T>(
          context,
          title: label,
          options: options,
          selected: selected,
        );
        if (choice != null) onChanged(choice);
      },
    );
  }
}

/// A [SelectBox] whose label is a chip across the top border (Language).
class ChipLabeledSelect<T extends SongOption> extends StatelessWidget {
  const ChipLabeledSelect({
    super.key,
    required this.label,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final Widget icon;
  final List<T> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ChipLabeledFrame(
      label: label,
      child: SelectBox(
        icon: icon,
        value: selected.label,
        semanticLabel: label,
        valueStyle: DeenText.fieldValue.copyWith(fontSize: 10),
        onTap: () async {
          final choice = await showOptionPicker<T>(
            context,
            title: label,
            options: options,
            selected: selected,
          );
          if (choice != null) onChanged(choice);
        },
      ),
    );
  }
}
