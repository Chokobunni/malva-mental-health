import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/chat_service.dart';
import '../services/malva_api_client.dart';
import '../services/weekly_summary_service.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/mini_summary.dart';
import '../widgets/professional_avatar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserName,
    required this.otherUserId,
    this.otherUserPhotoUrl = '',
  });

  final String otherUserName;
  final String otherUserId;

  /// URL foto lawan bicara (profesional). Kosong = pakai gradien + inisial.
  final String otherUserPhotoUrl;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  ChatService? _chatService;
  ChatState _chatState = ChatState.disconnected;
  bool _otherTyping = false;
  bool _isLoadingHistory = false;
  BackendChatAccess _access = const BackendChatAccess();
  bool _accessLoaded = false;
  StreamSubscription<ChatState>? _stateSub;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription<ChatPresence>? _presenceSub;
  final Map<String, bool> _onlineUsers = {};

  /// Foto lawan bicara; diisi dari parameter atau diambil dari server.
  String _photoUrl = '';

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.otherUserPhotoUrl;
    _initChat();
    _loadHistory();
    _loadAccess();
    // Best effort: lengkapi foto profesional bila pemanggil tidak membawanya.
    unawaited(_loadProfessionalPhoto());
  }

  /// Ambil foto profesional dari server (GET /v1/doctors/{userId}).
  ///
  /// Tidak memblokir UI: bila gagal, avatar tetap tampil dengan gradien +
  /// inisial. Dijalankan sekali saat layar dibuka.
  Future<void> _loadProfessionalPhoto() async {
    if (_photoUrl.isNotEmpty) return;
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (session?.role != UserRole.patient) return;
    if (token == null || token.isEmpty) return;
    try {
      final profile = await ref.read(apiClientProvider).getDoctorProfile(
            accessToken: token,
            userId: widget.otherUserId,
          );
      final photo = profile.credential.photoIntroUrl;
      if (!mounted || photo.isEmpty) return;
      setState(() => _photoUrl = photo);
    } on Object {
      // Abaikan: foto hanya pelengkap tampilan.
    }
  }

  /// Muat izin chat: teks hanya saat sesi berjalan; share data milik
  /// pasien butuh paket aktif; profesional membahas saat sesi.
  Future<void> _loadAccess() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final myId = session?.backendUserId ?? session?.identifier;
    if (token == null || token.isEmpty || myId == null || myId.isEmpty) return;
    final isPatient = session?.role == UserRole.patient;
    try {
      final access = await ref.read(apiClientProvider).chatPermission(
            accessToken: token,
            patientId: isPatient ? myId : widget.otherUserId,
            professionalId: isPatient ? widget.otherUserId : myId,
          );
      if (!mounted) return;
      setState(() {
        _access = access;
        _accessLoaded = true;
      });
    } on Object {
      // Izin gagal dimuat: server tetap menegakkan aturan saat kirim.
    }
  }

  bool get _isPatient =>
      ref.read(currentSessionProvider)?.role == UserRole.patient;

  bool get _canSendText => _access.canSendText;

  bool get _canShare => _isPatient && _access.canShare;

  /// Muat riwayat chat dari server (GET /v1/messages) agar percakapan
  /// sebelumnya tidak hilang saat layar dibuka ulang.
  Future<void> _loadHistory() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final myId = session?.backendUserId ?? session?.identifier;
    if (token == null || token.isEmpty || myId == null || myId.isEmpty) return;
    final isPatient = session?.role == UserRole.patient;
    final patientId = isPatient ? myId : widget.otherUserId;
    final professionalId = isPatient ? widget.otherUserId : myId;
    setState(() => _isLoadingHistory = true);
    try {
      final history = await ref.read(apiClientProvider).listMessages(
            accessToken: token,
            patientId: patientId,
            professionalId: professionalId,
          );
      if (!mounted) return;
      // Server mengembalikan terbaru dulu; tampilkan lama -> baru.
      final ordered = history.reversed.toList(growable: false);
      setState(() {
        for (final msg in ordered) {
          if (_messages.any((m) => m.id == msg.id)) continue;
          _messages.add(
            ChatMessage(
              id: msg.id,
              senderId: msg.senderId,
              senderName: msg.senderName,
              text: msg.text,
              timestamp: msg.createdDateTime ?? DateTime.now(),
              isMine: msg.senderId == myId,
              kind: msg.kind,
              metadata: msg.metadata,
            ),
          );
        }
        _isLoadingHistory = false;
      });
      _scrollToBottom(animated: false);
    } on Object {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _initChat() {
    final session = ref.read(currentSessionProvider);
    final apiClient = ref.read(apiClientProvider);
    if (session?.accessToken == null || session!.accessToken!.isEmpty) return;

    final baseUri = apiClient.baseUri;
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final baseUrl =
        '$wsScheme://${baseUri.host}${baseUri.port == 80 || baseUri.port == 443 ? '' : ':${baseUri.port}'}';

    _chatService = ChatService(
      userId: session.backendUserId ?? session.identifier,
      accessToken: session.accessToken!,
      baseUrl: baseUrl,
      recipientId: widget.otherUserId,
      senderName: session.displayName,
    );

    _stateSub = _chatService!.stateStream.listen((state) {
      if (mounted) setState(() => _chatState = state);
    });

    _messageSub = _chatService!.messageStream.listen((msg) {
      if (!mounted) return;
      // Hindari duplikat (mis. share dikirim via REST + echo WS).
      if (_messages.any((m) => m.id == msg.id)) return;
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });

    _typingSub = _chatService!.typingStream.listen((isTyping) {
      if (mounted) setState(() => _otherTyping = isTyping);
    });

    _presenceSub = _chatService!.presenceStream.listen((presence) {
      if (mounted) {
        setState(() => _onlineUsers[presence.userId] = presence.isOnline);
      }
    });

    _chatService!.connect();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _stateSub?.cancel();
    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _chatService?.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (!_canSendText) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_access.reason.isEmpty
                ? 'Chat teks aktif saat sesi berjalan.'
                : _access.reason)),
      );
      return;
    }
    _sendText(text);
    _inputController.clear();
    _chatService?.stopTyping();
  }

  /// Kirim teks: lewat WebSocket bila tersambung, kalau tidak lewat REST
  /// (tetap tersimpan di server dan terkirim ke lawan bicara).
  void _sendText(String text) {
    if (_chatState == ChatState.connected) {
      _chatService?.sendMessage(text);
      return;
    }
    unawaited(_sendViaRest(text: text, kind: 'text'));
  }

  /// Kirim pesan terstruktur (share) agar pasti tersimpan di server.
  /// Share hanya untuk pasien dengan paket aktif (server menegakkan).
  ///
  /// Mengembalikan true HANYA bila pesan benar-benar terkirim, supaya UI tidak
  /// menampilkan toast "terkirim" padahal pengiriman gagal.
  Future<bool> _sendShare({
    required String kind,
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_canShare) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Berbagi data butuh paket sesi aktif dengan profesional ini.')),
        );
      }
      return false;
    }
    if (_chatState == ChatState.connected && metadata == null) {
      _chatService?.sendMessage(text, kind: kind);
      return true;
    }
    return _sendViaRest(text: text, kind: kind, metadata: metadata);
  }

  /// Kirim lewat REST (jalur cadangan saat WebSocket tidak tersambung).
  /// Mengembalikan true bila server menerima pesan.
  Future<bool> _sendViaRest({
    required String text,
    required String kind,
    Map<String, dynamic>? metadata,
  }) async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final myId = session?.backendUserId ?? session?.identifier;
    if (token == null || token.isEmpty || myId == null) return false;
    try {
      final sent = await ref.read(apiClientProvider).sendChatMessage(
            accessToken: token,
            recipientId: widget.otherUserId,
            text: text,
            kind: kind,
            metadata: metadata,
          );
      if (!mounted) return true;
      setState(() {
        if (!_messages.any((m) => m.id == sent.id)) {
          _messages.add(
            ChatMessage(
              id: sent.id,
              senderId: sent.senderId,
              senderName: sent.senderName,
              text: sent.text,
              timestamp: sent.createdDateTime ?? DateTime.now(),
              isMine: true,
              kind: sent.kind,
              metadata: sent.metadata,
            ),
          );
        }
      });
      _scrollToBottom();
      return true;
    } on Object {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengirim. Periksa koneksi ke server Malva.'),
          backgroundColor: MalvaColors.danger,
        ),
      );
      return false;
    }
  }

  void _onInputChanged(String value) {
    if (value.trim().isNotEmpty) {
      _chatService?.startTyping();
    } else {
      _chatService?.stopTyping();
    }
  }

  void _showShareSheet(BuildContext context) {
    if (!_isPatient) return; // hanya pasien yang bisa share data.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bagikan ke profesional',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text(
                'Data dikirim sebagai kartu ringkasan ke ${widget.otherUserName} '
                'dan tersimpan di riwayat chat.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              for (final item in const [
                (
                  Icons.auto_awesome_rounded,
                  'Ringkasan (Mini Summary)',
                  'summary',
                  MalvaColors.seed
                ),
                (
                  Icons.fact_check_rounded,
                  'Hasil Assessment',
                  'assessment',
                  MalvaColors.orchid
                ),
                (
                  Icons.medication_rounded,
                  'Obat & Resep',
                  'prescription',
                  MalvaColors.mint
                ),
                (
                  Icons.flag_rounded,
                  'Goals & Habits',
                  'goals',
                  MalvaColors.amber
                ),
                (
                  Icons.edit_note_rounded,
                  'Diary Terakhir',
                  'diary',
                  MalvaColors.plum
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: item.$4.withValues(alpha: 0.14),
                        child: Icon(item.$1, color: item.$4),
                      ),
                      title: Text(item.$2,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14)),
                      trailing: const Icon(Icons.send_rounded, size: 18),
                      onTap: () {
                        Navigator.pop(ctx);
                        _shareData(item.$3, item.$2);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menyusun ringkasan data lalu mengirimkannya ke chat profesional.
  ///
  /// Sumber data UTAMA adalah server (screening, worksheet DASS/WHO-5, obat,
  /// goals, diary). Store lokal hanya dipakai sebagai fallback ketika panggilan
  /// API gagal, karena store tidak selalu terhidrasi — itulah sebab dulu muncul
  /// toast "Belum ada goals/diary/assessment" padahal datanya ada di server.
  Future<void> _shareData(String kind, String label) async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final api = ref.read(apiClientProvider);
    final myId = session?.backendUserId ?? session?.identifier ?? '';
    if (token == null || token.isEmpty) {
      _toast('Login dulu untuk membagikan data.');
      return;
    }
    final store = ref.read(malvaStoreProvider);
    String text;
    Map<String, dynamic> metadata = {};

    switch (kind) {
      case 'summary':
        // Ringkasan 14 hari diambil dari SERVER, bukan dari store yang belum
        // tentu terhidrasi. Store hanya fallback — tanpa ini pesan ke
        // profesional bisa berisi angka palsu (0 check-in / 0 jam / 0%).
        final metrics = await loadWeeklySummary(
          api: api,
          accessToken: token,
          localMoods: [
            for (final entry in store.moodEntries)
              (
                at: entry.date,
                sleepHours: entry.sleepHours,
                moodScore: entry.mood.score,
              ),
          ],
          localLogs: [
            for (final log in store.medicationLogs)
              (at: log.takenAt, status: log.status),
          ],
        );
        if (metrics == null) {
          text = 'Ringkasan 14 hari belum tersedia '
              '(data check-in belum dimuat).';
          metadata = {'available': false};
          break;
        }
        // Hanya metrik yang benar-benar diketahui yang disebut; metrik yang
        // gagal dimuat tidak boleh muncul sebagai angka 0.
        final parts = <String>[
          if (metrics.moodKnown) '${metrics.moodCount} mood check-in',
          if (metrics.moodKnown && metrics.moodCount > 0)
            'tidur rata-rata ${metrics.avgSleepHours.toStringAsFixed(1)} jam',
          if (metrics.logsKnown) 'ketaatan obat ${metrics.adherencePercent}%',
        ];
        text = 'Ringkasan 14 hari: ${parts.join(', ')}.';
        metadata = {
          if (metrics.moodKnown) 'mood_count': metrics.moodCount,
          if (metrics.moodCount > 0)
            'avg_sleep_hours':
                double.parse(metrics.avgSleepHours.toStringAsFixed(1)),
          if (metrics.logsKnown)
            'medication_adherence': metrics.adherencePercent,
          'source': metrics.source,
        };
      case 'assessment':
        await _shareAssessment(
          token: token,
          api: api,
          patientId: myId,
          label: label,
        );
        return;
      case 'prescription':
        final meds = await _collectMedications(
          token: token,
          api: api,
          fallback: store,
        );
        if (meds.isEmpty) {
          _toast('Belum ada data obat untuk dibagikan.');
          return;
        }
        metadata = {'medications': meds};
        text = 'Daftar obat aktif: '
            '${meds.map((m) => '${m['name']} ${m['dosage']}').join(', ')}.';
      case 'goals':
        final goals = await _collectGoals(
          token: token,
          api: api,
          fallback: store,
        );
        if (goals.isEmpty) {
          _toast('Belum ada goals untuk dibagikan.');
          return;
        }
        metadata = {'goals': goals};
        text = 'Goals & habits: '
            '${goals.take(5).map((g) => '${g['title']} (${g['done_this_week']}/${g['target_per_week']} minggu ini)').join(', ')}.';
      case 'diary':
        final diary = await _collectLatestDiary(
          token: token,
          api: api,
          fallback: store,
        );
        if (diary == null) {
          _toast('Belum ada diary untuk dibagikan.');
          return;
        }
        metadata = diary.metadata;
        text = diary.text;
      default:
        return;
    }
    final sent = await _sendShare(kind: kind, text: text, metadata: metadata);
    if (sent && mounted) _toast('$label terkirim ke chat.');
  }

  /// Bagikan hasil assessment: screening PHQ-9/GAD-7 dan worksheet
  /// DASS-21/WHO-5 diambil dari server, lalu dipilih bila lebih dari satu.
  Future<void> _shareAssessment({
    required String token,
    required MalvaApiClient api,
    required String patientId,
    required String label,
  }) async {
    final candidates = await _assessmentCandidates(
      token: token,
      api: api,
      patientId: patientId,
    );
    if (!mounted) return;
    if (candidates.isEmpty) {
      _toast('Belum ada hasil assessment untuk dibagikan.');
      return;
    }
    var chosen = candidates.first;
    if (candidates.length > 1) {
      final picked = await _pickCandidate(candidates);
      if (picked == null) return; // pasien membatalkan
      chosen = picked;
    }
    final sent = await _sendShare(
      kind: 'assessment',
      text: chosen.text,
      metadata: chosen.metadata,
    );
    if (sent && mounted) _toast('$label terkirim ke chat.');
  }

  /// Kandidat hasil assessment: screening server + worksheet DASS/WHO-5.
  /// Bila API gagal total, jatuh ke data store lokal (best effort).
  Future<List<_ShareCandidate>> _assessmentCandidates({
    required String token,
    required MalvaApiClient api,
    required String patientId,
  }) async {
    final out = <_ShareCandidate>[];

    // 1) Screening PHQ-9 & GAD-7 dari server.
    try {
      final screenings = await api.listScreenings(
        accessToken: token,
        patientId: patientId,
        limit: 5,
      );
      for (final screening in screenings) {
        final text = 'Hasil screening: PHQ-9 '
            '${screening.phq9.score}/${screening.phq9.maxScore} '
            '(${screening.phq9.level}), GAD-7 '
            '${screening.gad7.score}/${screening.gad7.maxScore} '
            '(${screening.gad7.level}).';
        out.add(_ShareCandidate(
          title: 'PHQ-9 & GAD-7 — ${screening.overallLevel}',
          subtitle: _dateLabel(screening.createdAt),
          text: text,
          icon: Icons.fact_check_rounded,
          metadata: {
            'source': 'screening',
            'screening_id': screening.id,
            'overall_level': screening.overallLevel,
            'phq9_score': screening.phq9.score,
            'gad7_score': screening.gad7.score,
            'crisis_flag': screening.crisisFlag,
            'summary': text,
            'shared_at':
                (screening.createdAt ?? DateTime.now()).toIso8601String(),
          },
        ));
      }
    } on Object {
      // Lanjut ke sumber berikutnya.
    }

    // 2) Worksheet DASS-21 / WHO-5 dari server (summary sudah berformat baku).
    try {
      final submissions = await api.listTherapySubmissions(accessToken: token);
      for (final sub in submissions) {
        if (sub.moduleId != 'dass21' && sub.moduleId != 'who5') continue;
        final title = sub.title.trim().isEmpty
            ? sub.moduleId.toUpperCase()
            : sub.title.trim();
        final summary = sub.summary.trim();
        final text = 'Hasil $title: '
            '${summary.isEmpty ? 'skor belum tersedia' : summary}';
        out.add(_ShareCandidate(
          title: title,
          subtitle: '${_dateLabel(sub.createdDateTime)}'
              '${sub.isShared ? ' • Dibagikan' : ''}',
          text: text,
          icon: Icons.assignment_turned_in_rounded,
          metadata: {
            'source': 'therapy',
            'module_id': sub.moduleId,
            'submission_id': sub.id,
            'summary': summary,
            'shared_at':
                (sub.createdDateTime ?? DateTime.now()).toIso8601String(),
          },
        ));
      }
    } on Object {
      // Lanjut ke fallback store.
    }

    // 3) Fallback: hasil yang tersimpan di store lokal (mis. offline).
    if (out.isEmpty) {
      final store = ref.read(malvaStoreProvider);
      final bundle =
          store.screeningBundles.isEmpty ? null : store.screeningBundles.last;
      if (bundle != null) {
        final text = 'Hasil screening: PHQ-9 ${bundle.phq9.score} '
            '(${bundle.phq9.level.label}), GAD-7 ${bundle.gad7.score} '
            '(${bundle.gad7.level.label}).';
        out.add(_ShareCandidate(
          title: 'PHQ-9 & GAD-7 — ${bundle.overallLevel.label}',
          subtitle: _dateLabel(bundle.createdAt),
          text: text,
          icon: Icons.fact_check_rounded,
          metadata: {
            'source': 'screening',
            'phq9_score': bundle.phq9.score,
            'gad7_score': bundle.gad7.score,
            'overall_level': bundle.overallLevel.label,
            'crisis_flag': bundle.crisisFlag,
            'summary': text,
            'shared_at': bundle.createdAt.toIso8601String(),
          },
        ));
      }
      final result = store.assessments.isEmpty ? null : store.assessments.last;
      if (result != null) {
        final text = 'Hasil ${result.type.title}: '
            '${result.score}/${result.maxScore} (${result.level.label}).';
        out.add(_ShareCandidate(
          title: result.type.title,
          subtitle: _dateLabel(result.createdAt),
          text: text,
          icon: Icons.assignment_turned_in_rounded,
          metadata: {
            'source': 'therapy',
            'module_id': result.type.name,
            'summary': text,
            'shared_at': result.createdAt.toIso8601String(),
          },
        ));
      }
    }
    return out;
  }

  /// Bottom sheet pemilihan hasil assessment (dipanggil bila kandidat > 1).
  Future<_ShareCandidate?> _pickCandidate(List<_ShareCandidate> candidates) {
    return showModalBottomSheet<_ShareCandidate>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Pilih hasil assessment',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text(
                'Hasil yang dipilih akan dikirim ke ${widget.otherUserName}.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final candidate in candidates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SoftCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor:
                                  MalvaColors.orchid.withValues(alpha: 0.14),
                              child: Icon(candidate.icon,
                                  color: MalvaColors.orchid),
                            ),
                            title: Text(candidate.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14)),
                            subtitle: Text(candidate.subtitle),
                            trailing: const Icon(Icons.send_rounded, size: 18),
                            onTap: () => Navigator.pop(ctx, candidate),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Daftar obat: server dulu, fallback store lokal.
  Future<List<Map<String, dynamic>>> _collectMedications({
    required String token,
    required MalvaApiClient api,
    required MalvaStoreState fallback,
  }) async {
    try {
      final backendMeds = await api.listMedications(accessToken: token);
      if (backendMeds.isNotEmpty) {
        return [
          for (final med in backendMeds)
            {
              'name': med.name,
              'dosage': med.dosage,
              'form': med.form,
              'reminder_time': med.reminderTime,
            },
        ];
      }
    } on Object {
      // Fallback di bawah.
    }
    return [
      for (final med in fallback.medications)
        {
          'name': med.name,
          'dosage': med.dosage,
          'form': med.form,
          'reminder_time':
              med.reminders.isEmpty ? '' : med.reminders.first.label,
        },
    ];
  }

  /// Daftar goals aktif: server dulu, fallback store lokal.
  Future<List<Map<String, dynamic>>> _collectGoals({
    required String token,
    required MalvaApiClient api,
    required MalvaStoreState fallback,
  }) async {
    try {
      final backendGoals = await api.listGoals(accessToken: token);
      final active =
          backendGoals.where((goal) => goal.isActive).toList(growable: false);
      if (active.isNotEmpty) {
        return [
          for (final goal in active)
            {
              'title': goal.title,
              'target_per_week': goal.targetPerWeek,
              'done_this_week': goal.doneThisWeek,
              'is_active': goal.isActive,
            },
        ];
      }
    } on Object {
      // Fallback di bawah.
    }
    return [
      for (final goal in fallback.goals)
        {
          'title': goal.title,
          'target_per_week': 0,
          'done_this_week': goal.completedToday ? 1 : 0,
          'is_active': true,
        },
    ];
  }

  /// Diary terbaru: server dulu, fallback store lokal.
  Future<_ShareCandidate?> _collectLatestDiary({
    required String token,
    required MalvaApiClient api,
    required MalvaStoreState fallback,
  }) async {
    try {
      final diaries = await api.listDiaryEntries(
        accessToken: token,
        limit: 5,
      );
      if (diaries.isNotEmpty) {
        final latest = diaries.first;
        final mood = latest.mood.trim().isEmpty ? 'tanpa mood' : latest.mood;
        final raw = (latest.note.trim().isEmpty ? latest.title : latest.note)
            .trim()
            .replaceAll('\n', ' ');
        final excerpt = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
        return _ShareCandidate(
          title: latest.title.trim().isEmpty ? 'Diary' : latest.title.trim(),
          subtitle: _dateLabel(latest.occurredAt),
          text: 'Diary terakhir ($mood): "$excerpt".',
          icon: Icons.edit_note_rounded,
          metadata: {
            'title': latest.title,
            'mood': latest.mood,
            'occurred_at':
                (latest.occurredAt ?? DateTime.now()).toIso8601String(),
          },
        );
      }
    } on Object {
      // Fallback di bawah.
    }
    if (fallback.diaryEntries.isEmpty) return null;
    final latest = fallback.diaryEntries.first;
    final raw = (latest.note.trim().isEmpty ? latest.title : latest.note)
        .trim()
        .replaceAll('\n', ' ');
    final excerpt = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
    return _ShareCandidate(
      title: latest.title.trim().isEmpty ? 'Diary' : latest.title.trim(),
      subtitle: _dateLabel(latest.createdAt),
      text: 'Diary terakhir (${latest.mood.label}): "$excerpt".',
      icon: Icons.edit_note_rounded,
      metadata: {
        'title': latest.title,
        'mood': latest.mood.label,
        'occurred_at': latest.createdAt.toIso8601String(),
      },
    );
  }

  /// Label tanggal ringkas untuk subjudul pilihan (mis. "7/9/2026").
  static String _dateLabel(DateTime? date) {
    if (date == null) return 'Tanggal tidak tercatat';
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherOnline = _onlineUsers.values.any((online) => online);
    return Scaffold(
      appBar: AppBar(
        // AppBar global bertema transparan + teks putih; di layar chat latar
        // terang membuat nama profesional putih tidak terbaca. Jadi warna
        // di-set eksplisit di sini (ungu Malva) dan teksnya tetap putih.
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            ProfessionalAvatar(
              displayName: widget.otherUserName,
              photoUrl: _photoUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherUserName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ConnectionStatusChip(state: _chatState),
                      if (otherOnline) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: MalvaColors.mint,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Online',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          const MiniSummaryButton(),
          _TypingIndicator(isTyping: _otherTyping),
        ],
      ),
      body: Column(
        children: [
          if (_accessLoaded && !_access.inSession)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: MalvaColors.amber.withValues(alpha: 0.15),
              child: Text(
                _access.reason.isEmpty
                    ? 'Chat teks aktif saat sesi berjalan.'
                    : _access.reason,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          if (_accessLoaded && _access.inSession)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: MalvaColors.mint.withValues(alpha: 0.15),
              child: const Text(
                'Sesi berjalan — kamu & profesional bisa chat di sini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MalvaColors.mint),
              ),
            ),
          if (_chatState == ChatState.connecting)
            const LinearProgressIndicator(),
          if (_isLoadingHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Memuat riwayat…',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _EmptyChat(state: _chatState)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final showTimestamp = index == 0 ||
                          _messages[index - 1]
                                  .timestamp
                                  .difference(msg.timestamp)
                                  .inMinutes >
                              5;
                      return Column(
                        children: [
                          if (showTimestamp)
                            _TimestampLabel(date: msg.timestamp),
                          const SizedBox(height: 6),
                          _ChatBubble(message: msg),
                        ],
                      );
                    },
                  ),
          ),
          _ChatInput(
            controller: _inputController,
            enabled: _canSendText,
            onChanged: _onInputChanged,
            onSend: _send,
            onShareTap: _canShare ? () => _showShareSheet(context) : null,
            disabledHint: _accessLoaded
                ? (_access.reason.isEmpty
                    ? 'Chat aktif saat sesi berjalan'
                    : _access.reason)
                : null,
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ChatState.connecting => ('Menyambungkan...', MalvaColors.amber),
      ChatState.connected => ('Online', MalvaColors.mint),
      ChatState.disconnected => ('Offline', MalvaColors.danger),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.isTyping});

  final bool isTyping;

  @override
  Widget build(BuildContext context) {
    if (!isTyping) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 24,
        height: 24,
        child: _DotsTyping(),
      ),
    );
  }
}

class _DotsTyping extends StatefulWidget {
  const _DotsTyping();

  @override
  State<_DotsTyping> createState() => _DotsTypingState();
}

class _DotsTypingState extends State<_DotsTyping>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = i * 0.2;
            final opacity =
                ((_controller.value - offset).abs() * 4).clamp(0.2, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Opacity(
                opacity: opacity,
                child: const CircleAvatar(
                  radius: 3,
                  backgroundColor: Colors.white70,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (state) {
      ChatState.connecting => (
          Icons.sync_rounded,
          'Menyambungkan...',
          'Menunggu koneksi ke server'
        ),
      ChatState.connected => (
          Icons.chat_bubble_outline_rounded,
          'Mulai percakapan',
          'Kirim pesan pertama Anda'
        ),
      ChatState.disconnected => (
          Icons.cloud_off_rounded,
          'Tidak terhubung',
          'Periksa koneksi internet Anda'
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56, color: MalvaColors.seed.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimestampLabel extends StatelessWidget {
  const _TimestampLabel({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        _formatDate(date),
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.black38, fontWeight: FontWeight.w700),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final now = DateTime.now();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Hari ini $h:$m';
    }
    return '${d.day}/${d.month}/${d.year} $h:$m';
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? MalvaColors.seed
              : MalvaColors.seed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.senderName,
                  // Nama pengirim tampil di latar terang (bubble lavender),
                  // jadi wajib hitam agar terbaca. Bubble milik sendiri
                  // (isMine) tidak menampilkan nama ini.
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ),
            if (message.kind == 'file') ...[
              _FileBubble(message: message, isMine: isMine),
              const SizedBox(height: 6),
            ] else if (message.kind == 'voice') ...[
              _VoiceBubble(message: message, isMine: isMine),
              const SizedBox(height: 6),
            ] else if (message.kind != 'text') ...[
              _SharedCardBubble(message: message, isMine: isMine),
              const SizedBox(height: 6),
            ],
            Text(
              message.text,
              style: TextStyle(
                color: isMine ? Colors.white : MalvaColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _timeLabel(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMine
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeLabel(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.2)
            : MalvaColors.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              color: MalvaColors.danger, size: 34),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text.isEmpty ? 'Dokumen' : message.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isMine ? Colors.white : MalvaColors.ink,
                  ),
                ),
                Text(
                  'PDF • ketuk untuk buka',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.75)
                        : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.2)
            : MalvaColors.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_fill_rounded,
              color: isMine ? Colors.white : MalvaColors.seed, size: 32),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.5)
                        : MalvaColors.seed.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Voice note • 0:00',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.75)
                        : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedCardBubble extends StatelessWidget {
  const _SharedCardBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (message.kind) {
      'diary' => (Icons.edit_note_rounded, 'Diary'),
      'goals' => (Icons.flag_rounded, 'Goals & Habits'),
      'habits' => (Icons.flag_rounded, 'Goals & Habits'),
      'summary' => (Icons.auto_awesome_rounded, 'Ringkasan'),
      'assessment' => (Icons.fact_check_rounded, 'Assessment'),
      'worksheet' => (Icons.assignment_turned_in_rounded, 'Worksheet'),
      'prescription' => (Icons.medication_rounded, 'Obat & Resep'),
      'progress' => (Icons.show_chart_rounded, 'Progress'),
      _ => (Icons.insert_drive_file_rounded, 'Lampiran'),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.2)
            : MalvaColors.orchid.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: isMine ? Colors.white : MalvaColors.orchid, size: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${label}: ${message.text.isEmpty ? 'terlampir' : message.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isMine ? Colors.white : MalvaColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu kandidat data yang bisa dibagikan ke chat (dipakai pemilihan
/// assessment: screening PHQ-9/GAD-7 atau worksheet DASS-21/WHO-5).
class _ShareCandidate {
  const _ShareCandidate({
    required this.title,
    required this.subtitle,
    required this.text,
    required this.icon,
    required this.metadata,
  });

  final String title;
  final String subtitle;
  final String text;
  final IconData icon;
  final Map<String, dynamic> metadata;
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
    this.onShareTap,
    this.disabledHint,
  });

  final TextEditingController controller;

  /// True = chat teks boleh dikirim (sesi berjalan).
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Null = tombol share disembunyikan (profesional / tanpa paket).
  final VoidCallback? onShareTap;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (onShareTap != null)
              IconButton(
                tooltip: 'Bagikan data',
                onPressed: onShareTap,
                icon: const Icon(Icons.add_rounded),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                onChanged: onChanged,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: enabled
                      ? 'Ketik pesan...'
                      : (disabledHint ?? 'Chat aktif saat sesi berjalan'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
