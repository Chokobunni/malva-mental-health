import 'package:flutter/material.dart';

import '../../theme.dart';
import '../services/web_assessment_service.dart';
import '../web_theme.dart';

/// Satu pertanyaan asesmen dengan tombol pilihan besar (radio) + tooltip makna.
///
/// Dipakai runner PHQ-9/GAD-7 (skala 0–3 angka) maupun DASS-21 (0–3 berlabel)
/// dan WHO-5 (0–5 berlabel). Nomor soal berasal dari data, bukan urutan render,
/// supaya penomoran tetap benar ketika seksi berganti.
class WebScaleQuestion extends StatelessWidget {
  const WebScaleQuestion({
    super.key,
    required this.item,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final WebAssessmentItem item;
  final int? value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WebSpacing.card),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(
          color: value == null
              ? const Color(0xFFEDE6F1)
              : MalvaColors.seed.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MalvaColors.seed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  item.number,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: MalvaColors.plum,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: item.values.map((int option) {
              final selected = value == option;
              return Tooltip(
                message: item.tooltipFor(option),
                waitDuration: const Duration(milliseconds: 350),
                child: InkWell(
                  key: Key('scale-${item.number}-$option'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: enabled ? () => onChanged(option) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    constraints: const BoxConstraints(minWidth: 84),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color:
                          selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? MalvaColors.seed
                            : const Color(0xFFEADFF2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color:
                              selected ? Colors.white : const Color(0xFF9C93A6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.shortLabelFor(option),
                          style: TextStyle(
                            fontSize: 12.5,
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
          ),
        ],
      ),
    );
  }
}
