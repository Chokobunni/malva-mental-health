import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';

class MedicationHistoryScreen extends ConsumerStatefulWidget {
  const MedicationHistoryScreen({super.key, this.session, this.apiClient});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<MedicationHistoryScreen> createState() =>
      _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState
    extends ConsumerState<MedicationHistoryScreen> {
  late final String? _owner;
  bool _bound = false, _invalid = false, _loading = true;
  int _generation = 0;
  String? _error;
  List<BackendMedicationLog> _logs = [];
  String? _key(AuthSession? s) =>
      s == null ? null : '${s.role.name}|${s.backendUserId ?? s.identifier}';
  AuthSession? get _session {
    final active = ref.read(authStateProvider).session;
    if (_invalid ||
        (_bound && _key(active) != _owner) ||
        (active != null && _key(active) != _owner)) return null;
    return active ?? widget.session;
  }

  @override
  void initState() {
    super.initState();
    final active = ref.read(authStateProvider).session;
    _owner = _key(widget.session ?? active);
    _bound = active != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _logs = [];
        _error = 'Masuk ke akun untuk memuat riwayat obat.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = widget.apiClient ?? ref.read(apiClientProvider);
      if (api == null) throw StateError('Api unavailable');
      final logs = await api.listMedicationLogs(accessToken: token, limit: 0);
      if (!mounted || generation != _generation || _session == null) return;
      logs.sort((a, b) {
        final at = a.takenAt ?? a.createdAt, bt = b.takenAt ?? b.createdAt;
        if (at == null) return bt == null ? a.id.compareTo(b.id) : 1;
        if (bt == null) return -1;
        final order = bt.compareTo(at);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _generation || _session == null) return;
      setState(() {
        _loading = false;
        _error = 'Riwayat minum obat belum dapat dimuat. Coba lagi.';
      });
    }
  }

  String _date(DateTime? value) {
    if (value == null) return 'Tanggal tidak tercatat';
    final d = toWib(value);
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (next.session != null) _bound = true;
      if (_key(next.session) != _owner &&
          (previous?.session != null || next.session != null)) {
        _generation++;
        setState(() {
          _invalid = true;
          _logs = [];
          _loading = false;
          _error = null;
        });
      }
    });
    final grouped = <String, List<BackendMedicationLog>>{};
    for (final log in _logs) {
      final day = _date(log.takenAt ?? log.createdAt);
      grouped.putIfAbsent(day, () => []).add(log);
    }
    return Scaffold(
        backgroundColor: const Color(0xfffafafa),
        body: Column(children: [
          Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xff88459c), Color(0xffcf80d8)])),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 20, 19),
                      child: Row(children: [
                        IconButton(
                            tooltip: 'Kembali',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 20)),
                        const Expanded(
                            child: Text('Riwayat Minum Obat',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700))),
                      ])))),
          Expanded(
              child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
                      children: [
                        if (_invalid)
                          const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'Akun berubah. Buka kembali riwayat dari akun aktif.'))
                        else if (_loading)
                          const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator()))
                        else if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Column(children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Coba Lagi'))
                              ]))
                        else if (_logs.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(28),
                              child: Text('Belum ada riwayat minum obat.',
                                  textAlign: TextAlign.center))
                        else
                          for (final group in grouped.entries) ...[
                            Padding(
                                padding:
                                    const EdgeInsets.only(top: 26, bottom: 21),
                                child: Center(
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 17, vertical: 7),
                                        decoration: BoxDecoration(
                                            color: const Color(0xfff8edf9),
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                        child: Text(group.key,
                                            style: const TextStyle(
                                                color: Color(0xffa06aa8),
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w700))))),
                            for (final log in group.value)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 15),
                                  child: _log(log)),
                          ],
                      ]))),
        ]));
  }

  Widget _log(BackendMedicationLog log) {
    final color = switch (log.status) {
      'taken' => const Color(0xff29c8b7),
      'partial' => const Color(0xffae69b7),
      'skipped' => const Color(0xffd8a236),
      _ => const Color(0xffdf676d)
    };
    final icon = switch (log.status) {
      'taken' => Icons.check_rounded,
      'partial' => Icons.hourglass_bottom_rounded,
      'skipped' => Icons.skip_next_rounded,
      _ => Icons.close_rounded
    };
    final at = log.takenAt ?? log.createdAt;
    final time = at == null ? 'Waktu tidak tercatat' : formatWibBubbleTime(at);
    return Container(
        key: ValueKey('medication-log-${log.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 19),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xfff2f2f2)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x05000000), blurRadius: 7, offset: Offset(0, 3))
            ]),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 25)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    log.medicationName.isEmpty
                        ? 'Nama obat tidak tercatat'
                        : log.medicationName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        color: Color(0xff27333c))),
                const SizedBox(height: 5),
                Text(
                    '${log.status.isEmpty ? 'STATUS TIDAK TERCATAT' : log.status.toUpperCase()} · $time',
                    style:
                        const TextStyle(color: Color(0xff818991), fontSize: 15))
              ])),
        ]));
  }
}
