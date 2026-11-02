import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/therapy_library.dart';
import '../services/web_therapy_service.dart';
import '../web_theme.dart';

/// Satu kolom worksheet terapi web, mendukung SEMUA [TherapyFieldKind].
///
/// Nilai disimpan langsung ke [WebWorksheetAnswers] (mutable) lalu
/// [onChanged] dipanggil agar induk membangun ulang. Controller teks dimiliki
/// induk (runner) supaya isi tidak hilang saat rebuild.
class WebWorksheetFieldInput extends StatelessWidget {
  const WebWorksheetFieldInput({
    super.key,
    required this.field,
    required this.answers,
    required this.onChanged,
    this.textController,
    this.pointControllers = const <TextEditingController>[],
    this.enabled = true,
  });

  final TherapyWorksheetField field;
  final WebWorksheetAnswers answers;
  final VoidCallback onChanged;

  /// Controller untuk [TherapyFieldKind.text].
  final TextEditingController? textController;

  /// Controller per poin untuk [TherapyFieldKind.points].
  final List<TextEditingController> pointControllers;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WebSpacing.card),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (field.badge.isNotEmpty) ...<Widget>[
                Container(
                  constraints: const BoxConstraints(minWidth: 30),
                  height: 26,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: MalvaColors.seed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    field.badge,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: MalvaColors.plum,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  field.label,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (field.hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: field.badge.isEmpty ? 0 : 40),
              child: Text(
                field.hint,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: Color(0xFF8B8194),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildInput(context),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    switch (field.kind) {
      case TherapyFieldKind.text:
        return TextField(
          key: Key('ws-text-${field.id}'),
          controller: textController,
          enabled: enabled,
          minLines: field.multiline ? 3 : 1,
          maxLines: field.multiline ? 6 : 1,
          onChanged: (String value) {
            answers.texts[field.id] = value;
            onChanged();
          },
          style: const TextStyle(fontSize: 13.5, height: 1.45),
          decoration: const InputDecoration(
            hintText: 'Tulis di sini…',
            isDense: true,
          ),
        );
      case TherapyFieldKind.scale:
        return _OptionWrap(
          field: field,
          values: field.scaleValues,
          labelFor: field.scaleShortLabel,
          tooltipFor: field.scaleLabel,
          isSelected: (int value) => answers.scales[field.id] == value,
          keyPrefix: 'ws-${field.id}',
          enabled: enabled,
          onSelect: (int value) {
            answers.scales[field.id] = value;
            onChanged();
          },
        );
      case TherapyFieldKind.number:
        final min = field.minValue ?? 0;
        final max = field.maxValue ?? 99;
        final value = answers.numbers[field.id] ?? min;
        return Row(
          children: <Widget>[
            _RoundIconButton(
              key: Key('ws-number-${field.id}-minus'),
              icon: Icons.remove_rounded,
              enabled: enabled && value > min,
              onPressed: () {
                answers.numbers[field.id] = value - 1;
                onChanged();
              },
            ),
            Container(
              width: 64,
              alignment: Alignment.center,
              child: Text(
                '$value',
                key: Key('ws-number-${field.id}-value'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _RoundIconButton(
              key: Key('ws-number-${field.id}-plus'),
              icon: Icons.add_rounded,
              enabled: enabled && value < max,
              onPressed: () {
                answers.numbers[field.id] = value + 1;
                onChanged();
              },
            ),
            const SizedBox(width: 12),
            Text(
              'rentang $min–$max',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
            ),
          ],
        );
      case TherapyFieldKind.points:
        final labels = field.effectivePointLabels();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < field.pointCount; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3EDF8),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: Key('ws-point-${field.id}-$i'),
                        controller: i < pointControllers.length
                            ? pointControllers[i]
                            : null,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: 3,
                        onChanged: (String value) {
                          final list = answers.points.putIfAbsent(
                            field.id,
                            () => List<String>.filled(field.pointCount, ''),
                          );
                          if (i < list.length) list[i] = value;
                          onChanged();
                        },
                        style: const TextStyle(fontSize: 13.5, height: 1.45),
                        decoration: InputDecoration(
                          hintText:
                              i < labels.length ? labels[i] : 'Poin ${i + 1}',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case TherapyFieldKind.choice:
        final options = field.choices;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((String option) {
            final selected = answers.choices[field.id] == option;
            return _ChoiceChip(
              key: Key('ws-choice-${field.id}-$option'),
              label: option,
              selected: selected,
              enabled: enabled,
              onTap: () {
                answers.choices[field.id] = option;
                onChanged();
              },
            );
          }).toList(growable: false),
        );
      case TherapyFieldKind.choiceMulti:
        final options = field.choices;
        final selectedSet =
            answers.multiChoices.putIfAbsent(field.id, () => <String>{});
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((String option) {
            final selected = selectedSet.contains(option);
            return _ChoiceChip(
              key: Key('ws-multi-${field.id}-$option'),
              label: option,
              selected: selected,
              enabled: enabled,
              onTap: () {
                if (selected) {
                  selectedSet.remove(option);
                } else {
                  selectedSet.add(option);
                }
                onChanged();
              },
            );
          }).toList(growable: false),
        );
      case TherapyFieldKind.beforeAfter:
        final min = field.minValue ?? 0;
        final max = field.maxValue ?? 10;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _BeforeAfterRow(
              label: 'Sebelum',
              field: field,
              min: min,
              max: max,
              value: answers.before[field.id],
              keyPrefix: 'ws-before-${field.id}',
              enabled: enabled,
              onSelect: (int value) {
                answers.before[field.id] = value;
                onChanged();
              },
            ),
            const SizedBox(height: 10),
            _BeforeAfterRow(
              label: 'Sesudah',
              field: field,
              min: min,
              max: max,
              value: answers.after[field.id],
              keyPrefix: 'ws-after-${field.id}',
              enabled: enabled,
              onSelect: (int value) {
                answers.after[field.id] = value;
                onChanged();
              },
            ),
          ],
        );
    }
  }
}

class _OptionWrap extends StatelessWidget {
  const _OptionWrap({
    required this.field,
    required this.values,
    required this.labelFor,
    required this.tooltipFor,
    required this.isSelected,
    required this.keyPrefix,
    required this.enabled,
    required this.onSelect,
  });

  final TherapyWorksheetField field;
  final List<int> values;
  final String Function(int) labelFor;
  final String Function(int) tooltipFor;
  final bool Function(int) isSelected;
  final String keyPrefix;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((int value) {
        final selected = isSelected(value);
        return Tooltip(
          message: tooltipFor(value),
          waitDuration: const Duration(milliseconds: 350),
          child: InkWell(
            key: Key('$keyPrefix-$value'),
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? () => onSelect(value) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minWidth: 78),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? MalvaColors.seed : const Color(0xFFEADFF2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color: selected ? Colors.white : const Color(0xFF9C93A6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    labelFor(value),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : MalvaColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _BeforeAfterRow extends StatelessWidget {
  const _BeforeAfterRow({
    required this.label,
    required this.field,
    required this.min,
    required this.max,
    required this.value,
    required this.keyPrefix,
    required this.enabled,
    required this.onSelect,
  });

  final String label;
  final TherapyWorksheetField field;
  final int min;
  final int max;
  final int? value;
  final String keyPrefix;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <int>[
            for (var v = min; v <= max; v++) v,
          ].map((int option) {
            final selected = value == option;
            return InkWell(
              key: Key('$keyPrefix-$option'),
              borderRadius: BorderRadius.circular(8),
              onTap: enabled ? () => onSelect(option) : null,
              child: Container(
                width: 34,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        selected ? MalvaColors.seed : const Color(0xFFEADFF2),
                  ),
                ),
                child: Text(
                  '$option',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : MalvaColors.ink,
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    super.key,
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MalvaColors.seed : const Color(0xFFEADFF2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : MalvaColors.ink,
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        backgroundColor: const Color(0xFFF3EDF8),
        foregroundColor: MalvaColors.plum,
      ),
    );
  }
}
