import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/mini_summary.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserName,
    required this.otherUserId,
  });

  final String otherUserName;
  final String otherUserId;

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
  StreamSubscription<ChatState>? _stateSub;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription<ChatPresence>? _presenceSub;
  final Map<String, bool> _onlineUsers = {};

  @override
  void initState() {
    super.initState();
    _initChat();
    _loadHistory();
  }

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
  Future<void> _sendShare({
    required String kind,
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    if (_chatState == ChatState.connected && metadata == null) {
      _chatService?.sendMessage(text, kind: kind);
      return;
    }
    await _sendViaRest(text: text, kind: kind, metadata: metadata);
  }

  Future<void> _sendViaRest({
    required String text,
    required String kind,
    Map<String, dynamic>? metadata,
  }) async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final myId = session?.backendUserId ?? session?.identifier;
    if (token == null || token.isEmpty || myId == null) return;
    try {
      final sent = await ref.read(apiClientProvider).sendChatMessage(
            accessToken: token,
            recipientId: widget.otherUserId,
            text: text,
            kind: kind,
            metadata: metadata,
          );
      if (!mounted) return;
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
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengirim. Periksa koneksi ke server Malva.'),
          backgroundColor: MalvaColors.danger,
        ),
      );
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
  Future<void> _shareData(String kind, String label) async {
    final store = ref.read(malvaStoreProvider);
    String text;
    Map<String, dynamic> metadata = {};

    switch (kind) {
      case 'summary':
        final moods = store.moodEntries.take(14).toList(growable: false);
        final avgSleep = moods.isEmpty
            ? 0.0
            : moods.map((e) => e.sleepHours).reduce((a, b) => a + b) /
                moods.length;
        final adherence = store.adherencePercent;
        metadata = {
          'mood_count': moods.length,
          'avg_sleep_hours': double.parse(avgSleep.toStringAsFixed(1)),
          'medication_adherence': adherence,
        };
        text = 'Ringkasan 14 hari: ${moods.length} mood check-in, '
            'tidur rata-rata ${avgSleep.toStringAsFixed(1)} jam, '
            'ketaatan obat $adherence%.';
      case 'assessment':
        final bundle =
            store.screeningBundles.isEmpty ? null : store.screeningBundles.last;
        final result =
            store.assessments.isEmpty ? null : store.assessments.last;
        if (bundle == null && result == null) {
          _toast('Belum ada hasil assessment untuk dibagikan.');
          return;
        }
        if (bundle != null) {
          metadata = {
            'type': 'phq9_gad7',
            'phq9_score': bundle.phq9.score,
            'gad7_score': bundle.gad7.score,
            'level': bundle.overallLevel.label,
            'cf': double.parse(bundle.phq9.certaintyFactor.toStringAsFixed(3)),
            'crisis_flag': bundle.crisisFlag,
          };
          text = 'Hasil assessment terbaru: ${bundle.overallLevel.label} '
              '(PHQ-9 ${bundle.phq9.score}, GAD-7 ${bundle.gad7.score}, '
              'CF ${(bundle.phq9.certaintyFactor * 100).round()}%).';
        } else {
          metadata = {
            'type': result!.type.name,
            'score': result.score,
            'level': result.level.label,
            'cf': double.parse(result.certaintyFactor.toStringAsFixed(3)),
            'crisis_flag': result.crisisFlag,
          };
          text = 'Hasil assessment terbaru: ${result.level.label} '
              '(${result.type.title} ${result.score}/${result.maxScore}, '
              'CF ${(result.certaintyFactor * 100).round()}%).';
        }
      case 'prescription':
        final meds = store.medications;
        if (meds.isEmpty) {
          _toast('Belum ada data obat untuk dibagikan.');
          return;
        }
        metadata = {
          'medications': [
            for (final med in meds)
              {
                'name': med.name,
                'dosage': med.dosage,
                'form': med.form,
                'reminders': med.reminders,
              },
          ],
        };
        text = 'Daftar obat aktif: '
            '${meds.map((m) => '${m.name} ${m.dosage}').join(', ')}.';
      case 'goals':
        final goals = store.goals;
        if (goals.isEmpty) {
          _toast('Belum ada goals untuk dibagikan.');
          return;
        }
        metadata = {
          'goals': [
            for (final goal in goals)
              {
                'title': goal.title,
                'streak_days': goal.streakDays,
                'completed_today': goal.completedToday,
              },
          ],
        };
        text = 'Goals & habits: '
            '${goals.map((g) => g.title).take(5).join(', ')}.';
      case 'diary':
        final diaries = store.diaryEntries;
        if (diaries.isEmpty) {
          _toast('Belum ada diary untuk dibagikan.');
          return;
        }
        final latest = diaries.first;
        metadata = {
          'title': latest.title,
          'mood': latest.mood.label,
          'created_at': latest.createdAt.toIso8601String(),
        };
        text = 'Diary terakhir (${latest.mood.label}): '
            '"${latest.note.isEmpty ? latest.title : latest.note}".';
      default:
        return;
    }
    await _sendShare(kind: kind, text: text, metadata: metadata);
    if (mounted) _toast('$label terkirim ke chat.');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ConnectionStatusChip(state: _chatState),
                if (_onlineUsers.values.any((online) => online)) ...[
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
                  const Text(
                    'Online',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
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
          if (_chatState == ChatState.connecting)
            const LinearProgressIndicator(),
          if (_isLoadingHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Memuat riwayatâ€¦',
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
            enabled: true,
            onChanged: _onInputChanged,
            onSend: _send,
            onShareTap: () => _showShareSheet(context),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: MalvaColors.plum.withValues(alpha: 0.7),
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
                  'PDF â€¢ ketuk untuk buka',
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
                  'Voice note â€¢ 0:00',
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

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
    required this.onShareTap,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onShareTap;

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
            IconButton(
              tooltip: 'Bagikan data',
              onPressed: enabled ? onShareTap : null,
              icon: const Icon(Icons.add_rounded),
            ),
            IconButton(
              tooltip: 'Voice note (segera hadir)',
              onPressed: enabled
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Voice note segera hadir. Pakai teks dulu ya.'),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.mic_rounded),
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
                  hintText: enabled ? 'Ketik pesan...' : 'Menunggu koneksi...',
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
