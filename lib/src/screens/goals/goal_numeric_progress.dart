import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'goal_reference_widgets.dart';

class GoalNumericProgress extends StatefulWidget {
  const GoalNumericProgress(
      {super.key,
      required this.id,
      required this.title,
      required this.value,
      required this.target,
      required this.unit,
      required this.locked,
      required this.readOnly,
      required this.onSave});
  final String id, title, unit;
  final int value, target;
  final bool locked, readOnly;
  final Future<void> Function(int) onSave;

  @override
  State<GoalNumericProgress> createState() => _GoalNumericProgressState();
}

class _GoalNumericProgressState extends State<GoalNumericProgress> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _save();
  }

  @override
  void didUpdateWidget(covariant GoalNumericProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || (!_focus.hasFocus && !_saving)) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save([int adjustment = 0]) async {
    if (widget.locked || _saving) return;
    final entered = int.tryParse(_controller.text);
    if (entered == null || entered < 0 || entered > 1000000) {
      _controller.text = '${widget.value}';
      return;
    }
    final next = (entered + adjustment).clamp(0, 1000000);
    if (next == widget.value) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(next);
    } finally {
      if (mounted) {
        _controller.text = '${widget.value}';
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => GoalSurface(
        color: const Color(0xFFFAF3FD),
        border: const Color(0xFFF0E7F5),
        radius: 13,
        padding: const EdgeInsets.all(12),
        child: TextFieldTapRegion(
            groupId: _focus,
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: widget.readOnly
                        ? Text(
                            'Progres: ${widget.value} / ${widget.target} ${widget.unit}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF424C59)))
                        : Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 5,
                            runSpacing: 5,
                            children: [
                                const Text('Progres:',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF424C59))),
                                SizedBox(
                                    width: 62,
                                    child: TextField(
                                      key: Key('goal-value-${widget.id}'),
                                      groupId: _focus,
                                      controller: _controller,
                                      focusNode: _focus,
                                      readOnly: widget.locked || _saving,
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      textAlign: TextAlign.center,
                                      onChanged: (_) => setState(() {}),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(7)
                                      ],
                                      style: const TextStyle(
                                          color: goalPurple,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14),
                                      decoration: InputDecoration(
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 7, horizontal: 5),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFFD4BADF))),
                                          enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFFD4BADF))),
                                          focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: goalPurple,
                                                  width: 1.5)),
                                          semanticCounterText:
                                              'Progres ${widget.title}'),
                                      onSubmitted: (_) {
                                        _focus.unfocus();
                                        _save();
                                      },
                                      onTapOutside: (_) {
                                        _focus.unfocus();
                                        _save();
                                      },
                                    )),
                                Text('/ ${widget.target} ${widget.unit}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF424C59))),
                              ])),
                const SizedBox(width: 6),
                for (final add in [false, true]) ...[
                  if (add) const SizedBox(width: 6),
                  SizedBox(
                      width: 34,
                      height: 34,
                      child: IconButton(
                          tooltip:
                              '${add ? 'Tambah' : 'Kurangi'} progres ${widget.title}',
                          onPressed: widget.locked ||
                                  _saving ||
                                  (!add &&
                                      (int.tryParse(_controller.text) ?? 0) ==
                                          0) ||
                                  (add &&
                                      (int.tryParse(_controller.text) ?? 0) >=
                                          1000000)
                              ? null
                              : () => _save(add ? 1 : -1),
                          style: IconButton.styleFrom(
                              backgroundColor: add ? goalPurple : Colors.white,
                              foregroundColor: add ? Colors.white : goalPurple,
                              disabledForegroundColor: goalMuted,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          icon:
                              Icon(add ? Icons.add : Icons.remove, size: 20))),
                ],
              ]),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value: (widget.value / widget.target).clamp(0, 1),
                  minHeight: 8,
                  color: goalPurple,
                  backgroundColor: Colors.white,
                  borderRadius: BorderRadius.circular(99)),
            ])),
      );
}
