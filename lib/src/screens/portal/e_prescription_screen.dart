export 'prescription_wizard_screen.dart' show EPrescriptionFormScreen;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models.dart';
import '../../professional_role.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import 'prescription_editor_screen.dart';
import 'prescription_widgets.dart';
import 'prescription_wizard_screen.dart';

class EPrescriptionScreen extends ConsumerStatefulWidget {
  const EPrescriptionScreen(
      {super.key,
      this.session,
      this.apiClient,
      this.preselectedPatientId = '',
      this.preselectedPatientName = ''});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String preselectedPatientId;
  final String preselectedPatientName;
  @override
  ConsumerState<EPrescriptionScreen> createState() =>
      _EPrescriptionScreenState();
}

class _EPrescriptionScreenState extends ConsumerState<EPrescriptionScreen> {
  final _search = TextEditingController();
  late final PrescriptionAccountGuard _account;
  List<BackendEPrescription> _prescriptions = [];
  List<BackendPatientProfessionalLink> _links = [];
  bool _loading = true;
  bool _psychiatrist = false;
  String? _error;
  String _filter = 'all';
  int _request = 0;
  AuthSession? get _session =>
      _account.session(ref.read(authStateProvider).session);
  @override
  void initState() {
    super.initState();
    _account = PrescriptionAccountGuard(
        widget.session, ref.read(authStateProvider).session);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_request;
    final api = widget.apiClient;
    final session = _session;
    if (api == null || session?.accessToken?.isNotEmpty != true) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Hubungkan ke server untuk melihat resep.';
        });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.listEPrescriptions(accessToken: session!.accessToken!),
        api.listPatientProfessionalLinks(accessToken: session.accessToken!),
        api.getMyCredentials(accessToken: session.accessToken!)
      ]);
      if (!mounted || generation != _request || _session == null) return;
      final credential = results[2] as BackendProfessionalCredential?;
      setState(() {
        _prescriptions = results[0] as List<BackendEPrescription>;
        _links = results[1] as List<BackendPatientProfessionalLink>;
        _psychiatrist = credential != null &&
            isPsychiatristSpecialization(credential.specialization);
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted && generation == _request && _session != null)
        setState(() {
          _loading = false;
          _error = friendlyErrorMessage(e);
        });
    }
  }

  String _patient(BackendEPrescription rx) =>
      _links
          .where((l) => l.patientId == rx.patientId)
          .firstOrNull
          ?.patientDisplayName ??
      (widget.preselectedPatientId == rx.patientId &&
              widget.preselectedPatientName.isNotEmpty
          ? widget.preselectedPatientName
          : 'Pasien terhubung');
  Future<void> _detail(BackendEPrescription rx) async {
    await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => EPrescriptionDetailScreen(
                session: _session,
                apiClient: widget.apiClient,
                prescriptionId: rx.id,
                patientName: _patient(rx))));
    if (mounted && _session != null) await _load();
  }

  Future<void> _edit(BackendEPrescription rx) async {
    await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => EPrescriptionEditorScreen(
                session: _session,
                apiClient: widget.apiClient,
                prescription: rx,
                patientName: _patient(rx))));
    if (mounted && _session != null) await _load();
  }

  Future<void> _delete(BackendEPrescription rx) async {
    if (!await confirmPrescriptionDelete(context) || !mounted) return;
    final session = _session;
    final api = widget.apiClient;
    if (session?.accessToken == null || api == null) return;
    try {
      await api.deleteEPrescription(
          accessToken: session!.accessToken!, prescriptionId: rx.id);
      if (mounted && _session != null) await _load();
    } on Object catch (e) {
      if (mounted && _session != null)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(authStateProvider).session;
    final valid = _account.current(active);
    final query = _search.text.trim().toLowerCase();
    final shown = _prescriptions
        .where((rx) =>
            (_filter == 'all' || rx.status == _filter) &&
            (query.isEmpty ||
                [_patient(rx), rx.qrToken, ...rx.items.map((i) => i.name)]
                    .any((s) => s.toLowerCase().contains(query))))
        .toList();
    return Scaffold(
        backgroundColor: const Color(0xfffcfbfd),
        appBar: AppBar(
            title: const Text('E-Prescription',
                style: TextStyle(
                    fontFamily: 'Roboto', fontWeight: FontWeight.w800)),
            backgroundColor: prescriptionPurple,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(24)))),
        floatingActionButton: valid && !_loading && _psychiatrist
            ? FloatingActionButton.extended(
                heroTag: 'erx_add_fab',
                backgroundColor: prescriptionPurple,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('Resep Baru'),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EPrescriptionFormScreen(
                              session: _session,
                              apiClient: widget.apiClient,
                              links: _links,
                              preselectedPatientId: widget.preselectedPatientId,
                              preselectedPatientName:
                                  widget.preselectedPatientName)));
                  if (mounted && _session != null) await _load();
                })
            : null,
        body: !valid
            ? const Center(
                child: Text('Sesi akun berubah. Buka kembali halaman resep.'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 100),
                    children: [
                      TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                              labelText: 'Cari obat, pasien, atau QR',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: const Color(0xfff7f7fa),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: const BorderSide(
                                      color: Color(0xffe4e5e9))))),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final filter in [
                          ('all', 'Semua'),
                          ('issued', 'Issued'),
                          ('draft', 'Draft')
                        ])
                          ChoiceChip(
                              label: Text(
                                  '${filter.$2}  ${_prescriptions.where((r) => filter.$1 == 'all' || r.status == filter.$1).length}'),
                              selected: _filter == filter.$1,
                              selectedColor: prescriptionPurple,
                              labelStyle: TextStyle(
                                  color: _filter == filter.$1
                                      ? Colors.white
                                      : const Color(0xff566170),
                                  fontWeight: FontWeight.w700),
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setState(() => _filter = filter.$1))
                      ]),
                      const SizedBox(height: 18),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        PrescriptionPanel(
                            child: Column(children: [
                          Text(_error!),
                          TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Coba Lagi'))
                        ]))
                      else if (!_psychiatrist)
                        const PrescriptionPanel(
                            child: Text(
                                'Hanya Psikiater (Sp.KJ) terverifikasi yang dapat meresepkan obat.'))
                      else if (shown.isEmpty)
                        EmptyState(
                            icon: Icons.medication_outlined,
                            title: query.isEmpty
                                ? 'Belum ada resep'
                                : 'Resep tidak ditemukan',
                            subtitle: query.isEmpty
                                ? 'Resep yang diterbitkan akan tercatat di sini.'
                                : 'Coba kata pencarian atau filter lain.')
                      else
                        for (final rx in shown) ...[
                          _PrescriptionCard(
                              rx: rx,
                              patientName: _patient(rx),
                              onDetail: () => _detail(rx),
                              onEdit: () => _edit(rx),
                              onDelete: () => _delete(rx)),
                          const SizedBox(height: 16),
                        ],
                    ])));
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard(
      {required this.rx,
      required this.patientName,
      required this.onDetail,
      required this.onEdit,
      required this.onDelete});
  final BackendEPrescription rx;
  final String patientName;
  final VoidCallback onDetail, onEdit, onDelete;
  @override
  Widget build(BuildContext context) => PrescriptionPanel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: Color(0xffe0f3ef), shape: BoxShape.circle),
              child: const Icon(Icons.medication_rounded,
                  color: prescriptionGreen, size: 25)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${rx.items.length} item obat',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 19)),
                const SizedBox(height: 8),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xfff8effb),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(patientName,
                        style: const TextStyle(
                            color: prescriptionPurple,
                            fontWeight: FontWeight.w700))),
              ])),
          const SizedBox(width: 5),
          PrescriptionStatus(status: rx.status)
        ]),
        const SizedBox(height: 10),
        if (rx.status == 'issued' && rx.qrToken.isNotEmpty)
          Row(children: [
            Expanded(
                child: Text('QR: ${rx.qrToken}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12))),
            IconButton(
                tooltip: 'Salin kode QR',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: rx.qrToken)),
                icon: const Icon(Icons.copy_outlined, size: 17))
          ]),
        const Divider(height: 22),
        PrescriptionPanel(
            color: const Color(0xfff8f9fb),
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              for (var i = 0; i < rx.items.length && i < 2; i++) ...[
                _MedicationPreview(item: rx.items[i], index: i + 1),
                if (i < rx.items.length - 1 && i < 1) const SizedBox(height: 8),
              ],
              if (rx.items.length > 2)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                        '+${rx.items.length - 2} obat lainnya (${rx.items.skip(2).map((i) => i.name).join(', ')})',
                        style: const TextStyle(
                            color: prescriptionPurple,
                            fontWeight: FontWeight.w700)))
            ])),
        const SizedBox(height: 12),
        if (rx.createdAt != null)
          Row(children: [
            const Icon(Icons.calendar_today_outlined,
                size: 15, color: Colors.grey),
            const SizedBox(width: 7),
            Text(formatWibDateTime(rx.createdAt!),
                style: const TextStyle(fontSize: 12, color: Color(0xff7c8794)))
          ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
              key: Key('rx-detail-${rx.id}'),
              onPressed: onDetail,
              icon: const Icon(Icons.qr_code, size: 18),
              label: const Text('QR & Detail')),
          IconButton(
              key: Key('rx-edit-${rx.id}'),
              tooltip: 'Edit resep',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20)),
          IconButton(
              key: Key('rx-delete-${rx.id}'),
              tooltip: 'Hapus resep',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20))
        ]),
      ]));
}

class _MedicationPreview extends StatelessWidget {
  const _MedicationPreview({required this.item, required this.index});
  final BackendEPrescriptionItem item;
  final int index;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffedeef2)),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xfff5e9fa),
                borderRadius: BorderRadius.circular(6)),
            child: Text('$index',
                style: const TextStyle(
                    color: prescriptionPurple, fontWeight: FontWeight.w800))),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item.name}  ${item.dosage}',
              style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2),
          const SizedBox(height: 3),
          Text(
              [
                item.frequency,
                if (item.schedule?.relationToMeal.isNotEmpty == true)
                  item.schedule!.relationToMeal
              ].join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xff7b8491)))
        ])),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${item.currentStock} ${item.form}',
              style: const TextStyle(
                  color: prescriptionGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          if (item.remainingStock != null)
            Text('Sisa ${item.remainingStock}',
                style: const TextStyle(color: Color(0xff7b8491), fontSize: 11))
        ])
      ]));
}

class EPrescriptionDetailScreen extends ConsumerStatefulWidget {
  const EPrescriptionDetailScreen(
      {super.key,
      this.session,
      this.apiClient,
      required this.prescriptionId,
      this.patientName = 'Pasien terhubung'});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String prescriptionId;
  final String patientName;
  @override
  ConsumerState<EPrescriptionDetailScreen> createState() =>
      _EPrescriptionDetailScreenState();
}

class _EPrescriptionDetailScreenState
    extends ConsumerState<EPrescriptionDetailScreen> {
  late final PrescriptionAccountGuard _account;
  BackendEPrescription? _rx;
  String? _error;
  bool _loading = true, _busy = false;
  AuthSession? get _session =>
      _account.session(ref.read(authStateProvider).session);
  @override
  void initState() {
    super.initState();
    _account = PrescriptionAccountGuard(
        widget.session, ref.read(authStateProvider).session);
    _load();
  }

  Future<void> _load() async {
    final api = widget.apiClient;
    final token = _session?.accessToken;
    if (api == null || token == null) {
      setState(() {
        _loading = false;
        _error = 'Hubungkan ke server untuk melihat detail resep.';
      });
      return;
    }
    try {
      final rx = await api.getEPrescription(
          accessToken: token, prescriptionId: widget.prescriptionId);
      if (mounted && _session != null)
        setState(() {
          _rx = rx;
          _loading = false;
          _error = null;
        });
    } on Object catch (e) {
      if (mounted && _session != null)
        setState(() {
          _error = friendlyErrorMessage(e);
          _loading = false;
        });
    }
  }

  Future<void> _status() async {
    final rx = _rx;
    final api = widget.apiClient;
    final token = _session?.accessToken;
    if (rx == null || api == null || token == null) return;
    setState(() => _busy = true);
    try {
      final updated = await api.updateEPrescription(
          accessToken: token,
          prescriptionId: rx.id,
          patientId: rx.patientId,
          items: rx.items,
          notes: rx.notes,
          instructions: rx.instructions,
          diagnosis: rx.diagnosis,
          status: rx.status == 'issued' ? 'draft' : 'issued');
      if (mounted && _session != null) setState(() => _rx = updated);
    } on Object catch (e) {
      if (mounted && _session != null)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmPrescriptionDelete(context) || !mounted) return;
    final token = _session?.accessToken;
    if (token == null || widget.apiClient == null) return;
    setState(() => _busy = true);
    try {
      await widget.apiClient!.deleteEPrescription(
          accessToken: token, prescriptionId: widget.prescriptionId);
      if (mounted && _session != null) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted && _session != null)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _account.current(ref.watch(authStateProvider).session);
    final rx = _rx;
    final canEdit = valid &&
        rx != null &&
        _session?.role == UserRole.professional &&
        _session?.backendUserId == rx.professionalId;
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            toolbarHeight: 86,
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DETAIL E-PRESCRIPTION',
                  style: TextStyle(
                      fontFamily: 'Roboto', fontSize: 12, letterSpacing: .5)),
              const SizedBox(height: 6),
              Text(valid ? widget.patientName : 'Detail Resep',
                  style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w800,
                      fontSize: 20))
            ]),
            backgroundColor: prescriptionPurple,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(26)))),
        body: !valid
            ? const Center(
                child: Text('Sesi akun berubah. Buka kembali halaman resep.'))
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            Text(_error!),
                            TextButton(
                                onPressed: _load,
                                child: const Text('Coba Lagi'))
                          ]))
                    : rx == null
                        ? const Center(child: Text('Resep tidak ditemukan.'))
                        : ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                                PrescriptionPanel(
                                    color: const Color(0xfff8f9fb),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (rx.status == 'issued' &&
                                                    rx.qrToken.isNotEmpty) ...[
                                                  PrescriptionQr(
                                                      value: widget
                                                          .apiClient!.baseUri
                                                          .replace(
                                                              path:
                                                                  '/v1/e-prescriptions/verify',
                                                              queryParameters: {
                                                            'token': rx.qrToken
                                                          }).toString(),
                                                      size: 100),
                                                  const SizedBox(width: 12)
                                                ],
                                                Expanded(
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                      PrescriptionStatus(
                                                          status: rx.status),
                                                      if (rx.createdAt != null)
                                                        Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        8),
                                                            child: Text(
                                                                formatWibDateTime(rx
                                                                    .createdAt!),
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .grey))),
                                                      if (rx.status == 'issued')
                                                        SelectableText(
                                                            rx.qrToken,
                                                            style: const TextStyle(
                                                                fontFamily:
                                                                    'monospace',
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700))
                                                      else
                                                        const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                    top: 10),
                                                            child: Text(
                                                                'Draft belum memiliki QR yang berlaku.'))
                                                    ]))
                                              ]),
                                          if (rx.status == 'issued')
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: Text(
                                                    'Ditandatangani secara digital • STR/SIP: ${rx.signatureData['str_number'] ?? rx.signatureData['sip_number'] ?? 'Belum tersedia'}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xff677482))))
                                        ])),
                                const SizedBox(height: 18),
                                if (rx.diagnosis.isNotEmpty ||
                                    rx.notes.isNotEmpty ||
                                    rx.instructions.isNotEmpty)
                                  PrescriptionPanel(
                                      color: const Color(0xfffcf8ff),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (rx.diagnosis.isNotEmpty) ...[
                                              const Text('Diagnosis Klinis',
                                                  style: TextStyle(
                                                      color:
                                                          Color(0xff7c8794))),
                                              const SizedBox(height: 5),
                                              Text(rx.diagnosis,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              const Divider(height: 24)
                                            ],
                                            if (rx.notes.isNotEmpty) ...[
                                              const Text('Catatan Psikiater',
                                                  style: TextStyle(
                                                      color:
                                                          Color(0xff7c8794))),
                                              const SizedBox(height: 5),
                                              Text(rx.notes)
                                            ],
                                            if (rx.instructions.isNotEmpty &&
                                                rx.instructions !=
                                                    rx.notes) ...[
                                              const SizedBox(height: 10),
                                              const Text('Instruksi umum',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              Text(rx.instructions)
                                            ]
                                          ])),
                                const Padding(
                                    padding:
                                        EdgeInsets.only(top: 24, bottom: 14),
                                    child: Text('RINCIAN OBAT DIRESEPKAN',
                                        style: TextStyle(
                                            color: Color(0xff7c8794),
                                            fontWeight: FontWeight.w700))),
                                for (var i = 0; i < rx.items.length; i++) ...[
                                  _MedicationPreview(
                                      item: rx.items[i], index: i + 1),
                                  if (rx.items[i].schedule != null)
                                    Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 8, 10, 4),
                                        child: Text(rx.items[i].schedule!.label,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: prescriptionPurple))),
                                  if (rx.items[i].schedule?.instructions
                                          .isNotEmpty ==
                                      true)
                                    Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 4, 10, 8),
                                        child: Text(
                                            'Catatan: ${rx.items[i].schedule!.instructions}')),
                                  const SizedBox(height: 12)
                                ],
                                if (canEdit) ...[
                                  const Divider(height: 28),
                                  Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                            onPressed: _busy ? null : _delete,
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            label: const Text('Hapus'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.red.shade700)),
                                        OutlinedButton.icon(
                                            onPressed: _busy ? null : _status,
                                            icon: const Icon(Icons.sync),
                                            label: Text(rx.status == 'issued'
                                                ? 'Jadikan Draft'
                                                : 'Terbitkan Resep')),
                                        FilledButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () async {
                                                    await Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                            builder: (_) => EPrescriptionEditorScreen(
                                                                session:
                                                                    _session,
                                                                apiClient: widget
                                                                    .apiClient,
                                                                prescription:
                                                                    rx,
                                                                patientName: widget
                                                                    .patientName)));
                                                    if (mounted &&
                                                        _session != null)
                                                      await _load();
                                                  },
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            label: const Text('Edit Resep'),
                                            style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    prescriptionPurple,
                                                textStyle: const TextStyle(
                                                    fontFamily: 'Roboto',
                                                    fontWeight:
                                                        FontWeight.w700),
                                                minimumSize: const Size(0, 50)))
                                      ])
                                ],
                              ]));
  }
}
