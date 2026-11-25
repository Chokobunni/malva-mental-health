import 'dart:async';

import 'package:flutter/material.dart';

import 'icd10_service.dart';

class DiagnosisSearchField extends StatefulWidget {
  const DiagnosisSearchField({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.service,
    this.showSelectionCards = false,
  });

  final List<Icd10Diagnosis> selected;
  final ValueChanged<List<Icd10Diagnosis>> onChanged;
  final bool enabled;
  final Icd10Service? service;
  final bool showSelectionCards;

  @override
  State<DiagnosisSearchField> createState() => _DiagnosisSearchFieldState();
}

class _DiagnosisSearchFieldState extends State<DiagnosisSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late Icd10Service _service = widget.service ?? Icd10Service();
  late Future<List<Icd10Diagnosis>> _catalog = _service.load();
  String? _feedbackQuery, _feedback;

  @override
  void didUpdateWidget(covariant DiagnosisSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.service != oldWidget.service) {
      _service = widget.service ?? Icd10Service();
      _catalog = _service.load();
      _controller.clear();
      _feedback = null;
    }
    if (!widget.enabled && oldWidget.enabled) _focus.unfocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(Icd10Diagnosis selected) {
    // Autocomplete finishes applying its selected value before we reset the query.
    scheduleMicrotask(() {
      if (mounted && _controller.text == selected.code) _controller.clear();
    });
    if (!widget.enabled || _isSelected(selected)) return;
    widget.onChanged(List.unmodifiable([...widget.selected, selected]));
  }

  void _remove(Icd10Diagnosis diagnosis) {
    widget.onChanged(List.unmodifiable(widget.selected
        .where((item) => item.codeClean != diagnosis.codeClean)));
  }

  bool _isSelected(Icd10Diagnosis option) =>
      widget.selected.any((item) => item.codeClean == option.codeClean);

  void _retryCatalog() {
    final request = _service.load();
    setState(() {
      _catalog = request;
    });
  }

  Future<Iterable<Icd10Diagnosis>> _search(TextEditingValue value) async {
    final query = value.text.trim();
    if (!widget.enabled || query.isEmpty) return const [];
    final service = _service;
    try {
      final results = await service.search(query);
      if (!mounted ||
          service != _service ||
          !widget.enabled ||
          _controller.text != value.text) return const [];
      final available =
          results.where((item) => !_isSelected(item)).toList(growable: false);
      _searchFeedback(
          value.text, available.isEmpty ? 'Diagnosis tidak ditemukan.' : null);
      return available;
    } on Object {
      if (mounted && service == _service && _controller.text == value.text) {
        _searchFeedback(value.text, 'Pencarian gagal. Coba ubah kata kunci.');
      }
      return const [];
    }
  }

  void _searchFeedback(String query, String? message) {
    if (_feedbackQuery == query && _feedback == message) return;
    setState(() {
      _feedbackQuery = query;
      _feedback = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Icd10Diagnosis>>(
      future: _catalog,
      builder: (context, catalog) {
        final loaded = catalog.connectionState == ConnectionState.done &&
            !catalog.hasError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<Icd10Diagnosis>(
              textEditingController: _controller,
              focusNode: _focus,
              optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
              displayStringForOption: (option) => option.code,
              onSelected: _select,
              optionsBuilder: (value) => loaded ? _search(value) : const [],
              optionsViewBuilder: _optionsView,
              fieldViewBuilder: (context, controller, focus, submit) =>
                  ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  controller: controller,
                  focusNode: focus,
                  enabled: loaded && widget.enabled,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: 'Cari diagnosis ICD-10',
                    prefixIcon: const Icon(Icons.search),
                    helperText: value.text == _feedbackQuery ? _feedback : null,
                    helperMaxLines: 2,
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            onPressed: loaded && widget.enabled
                                ? controller.clear
                                : null,
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
            ),
            if (catalog.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Memuat katalog diagnosis',
                ),
              ),
            if (catalog.hasError &&
                catalog.connectionState == ConnectionState.done)
              TextButton.icon(
                onPressed: widget.enabled ? _retryCatalog : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Katalog gagal dimuat. Coba lagi'),
              ),
            if (widget.showSelectionCards && widget.selected.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('DIAGNOSIS TERPILIH (${widget.selected.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              for (final (index, diagnosis) in widget.selected.indexed)
                Card.outlined(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFEDE8F1)),
                  ),
                  child: ListTile(
                    title: Text(
                        '${index == 0 ? 'Primary' : 'Secondary'} - ${diagnosis.code}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(diagnosis.title),
                    trailing: IconButton(
                      tooltip: 'Hapus ${diagnosis.code}',
                      onPressed:
                          widget.enabled ? () => _remove(diagnosis) : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
            ] else if (widget.selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final (index, diagnosis) in widget.selected.indexed)
                      InputChip(
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${index == 0 ? 'Primary' : 'Secondary'} - ${diagnosis.code}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(diagnosis.title),
                          ],
                        ),
                        deleteButtonTooltipMessage: 'Hapus ${diagnosis.code}',
                        onDeleted:
                            widget.enabled ? () => _remove(diagnosis) : null,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _optionsView(
      BuildContext context,
      AutocompleteOnSelected<Icd10Diagnosis> select,
      Iterable<Icd10Diagnosis> options) {
    final results = options.toList(growable: false);
    final highlighted = AutocompleteHighlightedOption.of(context);
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final option = results[index];
            return Semantics(
              button: true,
              child: Ink(
                color:
                    index == highlighted ? Theme.of(context).focusColor : null,
                child: InkWell(
                  onTap: () => select(option),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(option.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            _CategoryBadge(type: option.type),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(option.title),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final (label, ink, background) = switch (type) {
      'disorder' => (
          'Disorder',
          const Color(0xff0b5b53),
          const Color(0xffd6f5ed)
        ),
      'psychosocial' => (
          'Psychosocial',
          const Color(0xff234e83),
          const Color(0xffe3efff)
        ),
      'risk_indicator' => (
          'Risk / Self-Harm',
          const Color(0xff9b2034),
          const Color(0xffffe4e8)
        ),
      _ => ('', Colors.transparent, Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label,
            style: TextStyle(
                color: ink, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
