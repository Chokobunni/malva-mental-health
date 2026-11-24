import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import 'diary_design.dart';
import 'friendly_error.dart';

const _teal = Color(0xff145754);
const _mint = Color(0xffade9df);
const _ink = Color(0xff1f2937);

class DiaryAccessRow extends StatelessWidget {
  const DiaryAccessRow({
    super.key,
    required this.recipients,
    required this.onPressed,
    this.showNames = false,
  });

  final List<DiaryAccessRecipient> recipients;
  final VoidCallback? onPressed;
  final bool showNames;

  @override
  Widget build(BuildContext context) {
    final shared = recipients.isNotEmpty;
    final status = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(shared ? Icons.people_outline : Icons.lock_outline,
          size: 20, color: shared ? _teal : diaryPurple),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              shared
                  ? 'Dibagikan ke ${recipients.length} profesional'
                  : 'Pribadi',
              style: TextStyle(
                  color: shared ? _teal : diaryPurple,
                  fontSize: showNames ? 13 : 12,
                  fontWeight: FontWeight.w700)),
          if (showNames)
            for (final recipient in recipients)
              Text(recipient.displayName,
                  style: const TextStyle(color: _ink, fontSize: 12)),
        ]),
      ),
    ]);
    final action = OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.share_outlined, size: 16),
      label: Text(shared ? 'Kelola akses' : 'Bagikan'),
      style: OutlinedButton.styleFrom(
        foregroundColor: diaryPlum,
        side:
            BorderSide(color: onPressed == null ? Colors.black26 : diaryPurple),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.4) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [status, action]);
    }
    return Row(
        crossAxisAlignment: showNames && shared
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
              child: Padding(
                  padding: EdgeInsets.only(top: showNames && shared ? 10 : 0),
                  child: status)),
          const SizedBox(width: 8),
          action
        ]);
  }
}

class DiaryAccessSheet extends StatefulWidget {
  const DiaryAccessSheet({
    super.key,
    required this.entry,
    required this.api,
    required this.accessToken,
    required this.onChanged,
  });

  final DiaryEntry entry;
  final MalvaApiClient api;
  final String? Function() accessToken;
  final ValueChanged<List<DiaryAccessRecipient>> onChanged;

  @override
  State<DiaryAccessSheet> createState() => _DiaryAccessSheetState();
}

class _DiaryAccessSheetState extends State<DiaryAccessSheet> {
  BackendDiaryAccess? _access;
  bool _busy = false;
  bool _picking = false;
  String? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_request());
  }

  Future<void> _request({String? professionalId, bool grant = false}) async {
    if (_busy) return;
    final token = widget.accessToken();
    if (token == null || token.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = professionalId == null
          ? await widget.api
              .fetchDiaryAccess(accessToken: token, diaryId: widget.entry.id)
          : await widget.api.updateDiaryAccess(
              accessToken: token,
              diaryId: widget.entry.id,
              professionalId: professionalId,
              grant: grant);
      if (!mounted || widget.accessToken() == null) return;
      setState(() {
        _access = access;
        _picking = professionalId == null && access.recipients.isEmpty;
        _selected = null;
      });
      widget.onChanged(access.recipients);
    } on Object catch (error) {
      if (mounted && widget.accessToken() != null) {
        setState(() => _error = friendlyErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancelPicking() {
    if (_access?.recipients.isEmpty ?? true) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _picking = false;
      _selected = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final primaryAction = FilledButton.styleFrom(
        backgroundColor: diaryPlum,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700));
    final recipientIds =
        access?.recipients.map((row) => row.professionalId).toSet() ??
            const <String>{};
    final eligible = access?.eligible
            .where((row) => !recipientIds.contains(row.professionalId))
            .toList() ??
        const <DiaryAccessRecipient>[];
    return PopScope(
        canPop: !_busy,
        child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .82),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                              child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: const Color(0xffaeb0b7),
                                      borderRadius: BorderRadius.circular(4)))),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                                child: Text(
                                    _picking
                                        ? 'Bagikan jurnal'
                                        : 'Kelola akses',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800))),
                            IconButton(
                                tooltip: 'Tutup',
                                onPressed:
                                    _busy ? null : () => Navigator.pop(context),
                                icon: const Icon(Icons.close)),
                          ]),
                          Text(widget.entry.title,
                              style: const TextStyle(
                                  color: Color(0xff4b5563), fontSize: 14)),
                          const SizedBox(height: 12),
                          if (_busy)
                            const LinearProgressIndicator(minHeight: 2),
                          if (_error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                          if (access == null && !_busy)
                            TextButton(
                                onPressed: _request,
                                child: const Text('Coba lagi')),
                          if (access != null && _picking) ...[
                            if (eligible.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                      'Belum ada profesional yang dapat ditambahkan.')),
                            RadioGroup<String>(
                              groupValue: _selected,
                              onChanged: (id) => setState(() {
                                _selected = id;
                                _error = null;
                              }),
                              child: Column(children: [
                                for (final recipient in eligible)
                                  RadioListTile<String>(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _avatar(recipient),
                                      controlAffinity:
                                          ListTileControlAffinity.trailing,
                                      value: recipient.professionalId,
                                      title: Text(recipient.displayName),
                                      enabled: !_busy),
                              ]),
                            ),
                            const SizedBox(height: 12),
                            if (eligible.isNotEmpty)
                              FilledButton(
                                  style: primaryAction,
                                  onPressed: _busy || _selected == null
                                      ? null
                                      : () => _request(
                                          professionalId: _selected,
                                          grant: true),
                                  child: const Text('Bagikan')),
                            TextButton(
                                onPressed: _busy ? null : _cancelPicking,
                                child: const Text('Batal')),
                          ],
                          if (access != null && !_picking) ...[
                            if (access.recipients.isEmpty)
                              const Text('Pribadi'),
                            for (var index = 0;
                                index < access.recipients.length;
                                index++) ...[
                              if (index > 0) const Divider(height: 1),
                              _recipientRow(access.recipients[index]),
                            ],
                            const SizedBox(height: 16),
                            FilledButton.icon(
                                style: primaryAction,
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _picking = true;
                                          _error = null;
                                        }),
                                icon: const Icon(Icons.add),
                                label: const Text('Tambah penerima')),
                          ],
                        ])))));
  }

  Widget _recipientRow(DiaryAccessRecipient recipient) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        _avatar(recipient),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(recipient.displayName,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const Text('Akses baca', style: TextStyle(fontSize: 12, color: _ink)),
        ])),
        TextButton(
            onPressed: _busy
                ? null
                : () => _request(professionalId: recipient.professionalId),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xff9b1c42),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            child: const Text('Cabut akses')),
      ]));

  Widget _avatar(DiaryAccessRecipient recipient) {
    final name = recipient.displayName
        .trim()
        .replaceFirst(RegExp(r'^(dr\.?|dokter)\s+', caseSensitive: false), '');
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return CircleAvatar(
        radius: 18,
        backgroundColor: _mint,
        foregroundColor: _teal,
        child: Text(initials,
            style: const TextStyle(fontWeight: FontWeight.w800)));
  }
}
