import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../professional_role.dart';
import '../providers/providers.dart';
import '../services/chat_service.dart';
import '../services/malva_api_client.dart';
import '../services/weekly_summary_service.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/friendly_error.dart';
import '../widgets/mini_summary.dart';
import '../widgets/professional_avatar.dart';
import '../widgets/account_avatar.dart';
import '../widgets/therapy_library.dart';
import '../widgets/shared_record_detail.dart';
import '../widgets/clinical_profile_cards.dart'
    show clinicalMedicationAdherence;
import '../time/wib.dart';
import '../services/server_clock.dart';
import '../platform/platform_providers.dart';
import 'chat/professional_chat_tools.dart';
import 'chat/clinical_chat_card.dart';
import 'chat/chat_shared_record_card.dart';
import 'chat/session_cancellation_card.dart';
import 'chat/session_follow_up_card.dart';
import 'assessment_screen.dart';
import 'booking/doctor_profile_screen.dart';
import 'portal/shared_patient_data_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserName,
    required this.otherUserId,
    this.otherUserPhotoUrl = '',
    this.otherUserAvatar,
  });

  final String otherUserName;
  final String otherUserId;

  /// URL foto lawan bicara (profesional). Kosong = pakai gradien + inisial.
  final String otherUserPhotoUrl;
  final String? otherUserAvatar;

  /// Label pemisah tanggal pesan (`Hari ini HH:mm` / `dd/MM/yyyy HH:mm`).
  ///
  /// Waktu pesan dari server berbentuk UTC, jadi WAJIB diubah ke waktu lokal
  /// lebih dulu: tanpa itu jamnya mundur 7 jam (WIB) dan pesan malam hari
  /// tampil sebagai "kemarin".
  static String formatMessageDate(DateTime d) {
    return formatWibBubbleDate(d);
  }

  /// Jam kecil di bawah setiap gelembung pesan (`HH:mm`, WIB).
  static String formatMessageTime(DateTime d) {
    return formatWibBubbleTime(d);
  }

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _historyLimit = 100;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showLatestButton = false;
  final _messages = <ChatMessage>[];
  final _deletedMessageIds = <String>{};
  final _pendingMessageDeletes = <String>{};
  final _chatRevision = ValueNotifier<int>(0);
  int _historyRequest = 0;
  String? _olderHistoryCursor;
  bool _loadingOlderHistory = false;
  ChatService? _chatService;
  ChatState _chatState = ChatState.disconnected;
  bool _otherTyping = false;
  bool _isLoadingHistory = false;
  bool _sharingData = false;
  bool _noticeDismissed = false;
  BackendChatAccess _access = const BackendChatAccess();
  bool _accessLoaded = false;
  Timer? _accessPoll;
  Timer? _accessExpiry;
  int _accessRequest = 0;
  late final String _owner;
  bool _ownerChanged = false;
  Future<void>? _accessLoading;
  bool _liveExpired = false;
  StreamSubscription<ChatState>? _stateSub;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<String>? _messageDeletedSub;
  StreamSubscription<String>? _diaryAccessSub;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription<ChatPresence>? _presenceSub;
  final Map<String, bool> _onlineUsers = {};
  late final StateController<String?> _activePeer;

  /// Foto lawan bicara; diisi dari parameter atau diambil dari server.
  String _photoUrl = '';
  String? _patientAvatar;
  int _avatarRequest = 0;
  String _professionalPhotoUrl = '';
  String _professionalRole = 'Profesional';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateLatestButton);
    _owner = _ownerKey(ref.read(currentSessionProvider));
    _startAccessPoll();
    // Tandai percakapan ini sebagai aktif agar notifikasi chat untuk peer yang
    // sama ditekan (pesannya sudah tampil di layar).
    _activePeer = ref.read(activeChatPeerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activePeer.state = widget.otherUserId;
    });
    _photoUrl = widget.otherUserPhotoUrl;
    _patientAvatar = widget.otherUserAvatar;
    _initChat();
    _loadHistory();
    _loadAccess();
    // Best effort: lengkapi foto profesional bila pemanggil tidak membawanya.
    unawaited(_loadProfessionalPhoto());
    unawaited(_loadPatientAvatar());
  }

  Future<void> _loadPatientAvatar() async {
    final request = ++_avatarRequest;
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (session?.role != UserRole.professional ||
        token == null ||
        token.isEmpty) return;
    try {
      final avatar = await ref.read(apiClientProvider).fetchPatientAvatar(
          accessToken: token, patientId: widget.otherUserId);
      if (mounted && _ownerMatches && request == _avatarRequest) {
        setState(() => _patientAvatar = avatar);
      }
    } on Object {
      // Keep the identity fallback when the private avatar cannot be read.
    }
  }

  /// Ambil foto profesional dari server (GET /v1/doctors/{userId}).
  ///
  /// Tidak memblokir UI: bila gagal, avatar tetap tampil dengan gradien +
  /// inisial. Dijalankan sekali saat layar dibuka.
  Future<void> _loadProfessionalPhoto() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final api = ref.read(apiClientProvider);
      final credential = session?.role == UserRole.patient
          ? (await api.getDoctorProfile(
                  accessToken: token, userId: widget.otherUserId))
              .credential
          : await api.getMyCredentials(accessToken: token);
      if (!mounted || !_ownerMatches || credential == null) return;
      setState(() {
        _professionalRole = professionalRoleLabel(credential.specialization);
        _professionalPhotoUrl = credential.photoIntroUrl;
        if (_isPatient && _professionalPhotoUrl.isNotEmpty) {
          _photoUrl = _professionalPhotoUrl;
        }
      });
    } on Object {
      // Abaikan: foto hanya pelengkap tampilan.
    }
  }

  /// Muat izin chat: teks hanya saat sesi berjalan; share data milik
  /// pasien butuh paket aktif; profesional membahas saat sesi.
  Future<void> _loadAccess() => _accessLoading ??=
      _refreshAccess().whenComplete(() => _accessLoading = null);

  Future<void> _refreshAccess() async {
    if (!_ownerMatches) return;
    final request = ++_accessRequest;
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final myId = session?.backendUserId ?? session?.identifier;
    if (token == null || token.isEmpty || myId == null || myId.isEmpty) {
      return;
    }
    final isPatient = session?.role == UserRole.patient;
    try {
      final access = await ref.read(apiClientProvider).chatPermission(
            accessToken: token,
            patientId: isPatient ? myId : widget.otherUserId,
            professionalId: isPatient ? widget.otherUserId : myId,
          );
      if (!mounted || !_ownerMatches || request != _accessRequest) return;
      setState(() {
        _access = access;
        _accessLoaded = true;
        _liveExpired = false;
      });
      _accessExpiry?.cancel();
      final end = access.sessionEndsAt;
      if (access.inSession && end != null) {
        final remaining = end.difference(ServerClock.now());
        if (remaining <= Duration.zero) {
          _expireAccess();
        } else {
          _accessExpiry = Timer(remaining, _expireAccess);
        }
      }
    } on Object {
      if (mounted && _ownerMatches && request == _accessRequest) {
        setState(() {
          _access = const BackendChatAccess(
              reason: 'Izin sesi belum dapat diperiksa. Mencoba kembali.');
          _accessLoaded = true;
        });
      }
    }
  }

  String _ownerKey(AuthSession? session) =>
      '${session?.role.name}:${session?.backendUserId ?? session?.identifier ?? ''}';

  bool get _ownerMatches =>
      !_ownerChanged && _owner == _ownerKey(ref.read(currentSessionProvider));

  void _startAccessPoll() {
    _accessPoll?.cancel();
    _accessPoll =
        Timer.periodic(const Duration(seconds: 5), (_) => _loadAccess());
  }

  void _expireAccess() {
    if (!mounted || !_ownerMatches) return;
    setState(() => _liveExpired = true);
    _chatService?.stopTyping();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ownerMatches) return;
    if (state == AppLifecycleState.resumed) {
      if (_chatService == null) {
        _initChat();
      } else {
        _chatService!.connect();
      }
      unawaited(_loadPatientAvatar());
      _startAccessPoll();
      _expireAccess();
      unawaited(_loadAccess());
      unawaited(_loadHistory());
    } else {
      _accessPoll?.cancel();
      _chatService?.disconnect();
      setState(() {
        _onlineUsers.clear();
        _otherTyping = false;
        _chatState = ChatState.disconnected;
      });
    }
  }

  bool get _isPatient =>
      ref.read(currentSessionProvider)?.role == UserRole.patient;

  bool get _canSendText =>
      _ownerMatches &&
      !_liveExpired &&
      _access.canSendText &&
      (_access.sessionEndsAt == null ||
          ServerClock.now().isBefore(_access.sessionEndsAt!));

  bool get _liveSession =>
      _ownerMatches &&
      _access.inSession &&
      !_liveExpired &&
      (_access.sessionEndsAt == null ||
          ServerClock.now().isBefore(_access.sessionEndsAt!));

  bool get _canShare =>
      _ownerMatches &&
      _isPatient &&
      _access.canShare &&
      (_access.hasActivePackage || _liveSession);

  bool get _canUseProfessionalTools =>
      !_isPatient &&
      _canSendText &&
      _access.inSession &&
      _access.sessionId.isNotEmpty;

  /// Percakapan "mati": tidak sedang dalam sesi, tidak punya paket aktif, tidak
  /// ada sesi berikutnya, dan tidak bisa berbagi data. Untuk pasien, ini berarti
  /// belum ada hubungan aktif dengan profesional — jangan tampilkan composer
  /// nonaktif dengan kalimat kriptik; tampilkan ajakan menjadwalkan sesi.
  bool get _isDeadConversation =>
      _accessLoaded &&
      !_liveSession &&
      !_access.hasActivePackage &&
      _access.nextSessionAt == null &&
      !_access.canShare;

  /// Muat riwayat chat dari server (GET /v1/messages) agar percakapan
  /// sebelumnya tidak hilang saat layar dibuka ulang.
  Future<bool> _loadHistory({bool older = false}) async {
    if (!_ownerMatches) return false;
    final cursor = older ? _olderHistoryCursor : null;
    if (older && (cursor == null || _loadingOlderHistory)) return false;
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    final myId = session?.backendUserId ?? session?.identifier;
    if (token == null || token.isEmpty || myId == null || myId.isEmpty)
      return false;
    final isPatient = session?.role == UserRole.patient;
    final patientId = isPatient ? myId : widget.otherUserId;
    final professionalId = isPatient ? widget.otherUserId : myId;
    final request = ++_historyRequest;
    final beforeLoad = _messages.map((message) => message.id).toSet();
    setState(() {
      _isLoadingHistory = beforeLoad.isEmpty;
      _loadingOlderHistory = older;
    });
    try {
      final history = await ref.read(apiClientProvider).listMessages(
            accessToken: token,
            patientId: patientId,
            professionalId: professionalId,
            limit: _historyLimit,
            before: cursor,
          );
      if (!mounted || !_ownerMatches || request != _historyRequest)
        return false;
      // Server mengembalikan terbaru dulu; tampilkan lama -> baru.
      final received = history.map((message) => message.id).toSet();
      final disappeared = older ? <String>{} : beforeLoad.difference(received);
      final oldest = history.length == _historyLimit ? history.last : null;
      final cutoff = oldest?.createdDateTime;
      setState(() {
        // A row older than a full window can return if newer rows are deleted.
        for (final message in _messages) {
          if (!disappeared.contains(message.id)) continue;
          if (oldest == null ||
              (cutoff != null &&
                  (message.timestamp.isAfter(cutoff) ||
                      (message.timestamp.isAtSameMomentAs(cutoff) &&
                          message.id.compareTo(oldest.id) > 0)))) {
            _deletedMessageIds.add(message.id);
          }
        }
        _messages.removeWhere((message) => disappeared.contains(message.id));
        for (final msg in history.reversed) {
          if (_hasMessage(msg.id)) continue;
          _messages.add(
            ChatMessage(
              id: msg.id,
              senderId: msg.senderId,
              senderName: msg.senderName,
              text: msg.text,
              timestamp: msg.createdDateTime ?? wibNow(),
              isMine: msg.senderId == myId,
              kind: msg.kind,
              metadata: msg.metadata,
            ),
          );
        }
        _messages.sort((first, second) {
          final order = first.timestamp.compareTo(second.timestamp);
          return order == 0 ? first.id.compareTo(second.id) : order;
        });
        _olderHistoryCursor = oldest?.id;
        _isLoadingHistory = false;
        _loadingOlderHistory = false;
      });
      if (disappeared.isNotEmpty) _chatRevision.value++;
      if (beforeLoad.isNotEmpty && !isPatient) {
        for (final id
            in _messages.map(chatDiaryReference).whereType<String>().toSet()) {
          ref.invalidate(chatDiaryEntryProvider(id));
        }
      }
      if (beforeLoad.isEmpty) _scrollToBottom(animated: false);
      return true;
    } on Object {
      if (mounted && _ownerMatches && request == _historyRequest) {
        setState(() {
          _isLoadingHistory = false;
          _loadingOlderHistory = false;
        });
        if (older) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Riwayat gagal dimuat. Coba lagi.')),
          );
        }
      }
      return false;
    }
  }

  bool _hasMessage(String id) =>
      _deletedMessageIds.contains(id) ||
      _messages.any((message) => message.id == id);

  void _removeMessage(String id) {
    if (!mounted || !_ownerMatches || !_deletedMessageIds.add(id)) return;
    setState(() => _messages.removeWhere((message) => message.id == id));
    _chatRevision.value++;
  }

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    if (!_ownerMatches ||
        !message.isMine ||
        !_messages.contains(message) ||
        !_pendingMessageDeletes.add(message.id)) return;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => _ownedOverlay(Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 420),
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 27,
                  backgroundColor: Color(0xFFFCE6E6),
                  foregroundColor: Color(0xFFA41919),
                  child: Icon(Icons.delete_outline_rounded, size: 29),
                ),
                const SizedBox(height: 10),
                const Text('Hapus pesan ini?',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                const Text(
                  'Pesan ini akan dihapus dari riwayat chat semua peserta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 22),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      Expanded(
                        flex: 4,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            foregroundColor: const Color(0xFF292731),
                            side: const BorderSide(color: Color(0xFF292731)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11)),
                          ),
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('Batal'),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            backgroundColor: const Color(0xFFC81C1C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11)),
                          ),
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Hapus untuk semua',
                              textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
      );
      if (confirmed != true ||
          !mounted ||
          !_ownerMatches ||
          _deletedMessageIds.contains(message.id)) return;
      final token = ref.read(currentSessionProvider)?.accessToken;
      if (token == null || token.isEmpty) return;
      await ref.read(apiClientProvider).deleteChatMessage(
            accessToken: token,
            messageId: message.id,
          );
      _removeMessage(message.id);
    } on Object catch (error) {
      if (mounted &&
          _ownerMatches &&
          !_deletedMessageIds.contains(message.id)) {
        _toast('Gagal menghapus pesan: ${friendlyErrorMessage(error)}');
      }
    } finally {
      _pendingMessageDeletes.remove(message.id);
    }
  }

  bool get _atLatest =>
      !_scrollController.hasClients ||
      _scrollController.position.pixels <=
          _scrollController.position.minScrollExtent + 24;

  void _updateLatestButton() {
    final show = !_atLatest;
    if (_showLatestButton != show && mounted) {
      setState(() => _showLatestButton = show);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.minScrollExtent;
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
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _initChat([AuthSession? refreshedSession]) {
    _disposeChat();
    final session = refreshedSession ?? ref.read(currentSessionProvider);
    final apiClient = ref.read(apiClientProvider);
    if (session?.accessToken == null || session!.accessToken!.isEmpty) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

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
      if (mounted && _ownerMatches) {
        setState(() {
          _chatState = state;
          if (state != ChatState.connected) _onlineUsers.clear();
        });
        if (state == ChatState.connected) {
          unawaited(_loadAccess());
          unawaited(_loadHistory());
        }
      }
    });

    _messageSub = _chatService!.messageStream.listen((msg) {
      if (!mounted || !_ownerMatches) return;
      // Hindari duplikat (mis. share dikirim via REST + echo WS).
      if (_hasMessage(msg.id)) return;
      final follow = msg.isMine || _atLatest;
      setState(() => _messages.add(msg));
      if (follow) _scrollToBottom();
    });

    _messageDeletedSub =
        _chatService!.messageDeletedStream.listen(_removeMessage);
    _diaryAccessSub = _chatService!.diaryAccessChangedStream.listen((id) {
      if (mounted && _ownerMatches) ref.invalidate(chatDiaryEntryProvider(id));
    });

    _typingSub = _chatService!.typingStream.listen((isTyping) {
      if (mounted && _ownerMatches) {
        setState(() => _otherTyping = isTyping);
      }
    });

    _presenceSub = _chatService!.presenceStream.listen((presence) {
      if (mounted && _ownerMatches) {
        setState(() => _onlineUsers[presence.userId] = presence.isOnline);
      }
    });

    _chatService!.connect();
  }

  void _disposeChat() {
    _stateSub?.cancel();
    _messageSub?.cancel();
    _messageDeletedSub?.cancel();
    _diaryAccessSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _chatService?.dispose();
    _chatService = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessRequest++;
    _accessPoll?.cancel();
    _accessExpiry?.cancel();
    // Lepas penanda hanya bila masih menunjuk peer ini (bisa saja layar lain
    // sudah membuka percakapan berbeda).
    Future.microtask(() {
      if (_activePeer.mounted && _activePeer.state == widget.otherUserId) {
        _activePeer.state = null;
      }
    });
    _inputController.dispose();
    _scrollController.dispose();
    _chatRevision.dispose();
    _disposeChat();
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
      if (mounted && _ownerMatches) {
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
      if (!mounted || !_ownerMatches) return true;
      setState(() {
        if (!_hasMessage(sent.id)) {
          _messages.add(
            ChatMessage(
              id: sent.id,
              senderId: sent.senderId,
              senderName: sent.senderName,
              text: sent.text,
              timestamp: sent.createdDateTime ?? wibNow(),
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
      if (!mounted || !_ownerMatches) return false;
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
    if (!_canSendText) return;
    if (value.trim().isNotEmpty) {
      _chatService?.startTyping();
    } else {
      _chatService?.stopTyping();
    }
  }

  void _appendClinicalMessage(BackendChatMessage sent) {
    if (!mounted || !_ownerMatches || _hasMessage(sent.id)) return;
    final session = ref.read(currentSessionProvider);
    setState(() => _messages.add(ChatMessage(
        id: sent.id,
        senderId: sent.senderId,
        senderName: sent.senderName,
        text: sent.text,
        timestamp: sent.createdDateTime ?? ServerClock.now(),
        isMine:
            sent.senderId == (session?.backendUserId ?? session?.identifier),
        kind: sent.kind,
        metadata: sent.metadata)));
    _scrollToBottom();
  }

  Future<void> _openProfessionalTools({bool openFiles = false}) async {
    await _loadAccess();
    if (!mounted) return;
    if (!_canUseProfessionalTools) {
      _toast('Lampiran dan alat klinis tersedia saat sesi berjalan.');
      return;
    }
    final session = ref.read(currentSessionProvider)!;
    final api = ref.read(apiClientProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
          maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * .94),
      builder: (_) => ProfessionalChatTools(
        apiClient: api,
        session: session,
        patientId: widget.otherUserId,
        sessionId: _access.sessionId,
        sessionEndsAt: _access.sessionEndsAt,
        onMessage: _appendClinicalMessage,
        openFiles: openFiles,
      ),
    );
    if (mounted) unawaited(_loadAccess());
  }

  Future<void> _openClinicalCard(ChatMessage message) async {
    if (!_ownerMatches) return;
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (session == null || token == null) return;
    final api = ref.read(apiClientProvider);
    final meta = message.metadata ?? const <String, dynamic>{};
    if (message.kind == 'attachment') {
      try {
        final id = meta['attachment_id']?.toString() ?? '';
        final bytes =
            await api.fetchChatAttachment(accessToken: token, attachmentId: id);
        if (!mounted || !_ownerMatches) return;
        final mime = meta['mime']?.toString() ?? 'application/octet-stream';
        final filename = meta['filename']?.toString() ?? 'lampiran';
        if (mime.startsWith('image/')) {
          await showDialog<void>(
              context: context,
              builder: (ctx) =>
                  Dialog(child: Consumer(builder: (ctx, dialogRef, _) {
                    dialogRef.watch(currentSessionProvider);
                    if (!_ownerMatches)
                      return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Sesi akun telah berubah.'));
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: InteractiveViewer(
                              child: Image.memory(bytes,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Text(
                                      'Gambar belum dapat ditampilkan.')))),
                      TextButton.icon(
                          onPressed: () {
                            if (_ownerMatches)
                              ref.read(fileExporterProvider).saveBytes(
                                  filename: filename,
                                  bytes: bytes,
                                  mimeType: mime);
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Simpan / bagikan')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Tutup')),
                    ]);
                  })));
        } else {
          await ref
              .read(fileExporterProvider)
              .saveBytes(filename: filename, bytes: bytes, mimeType: mime);
        }
      } on Object catch (error) {
        if (mounted && _ownerMatches)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(friendlyErrorMessage(error))));
      }
      return;
    }
    final assessment = message.kind == 'assessment_request';
    final therapy = message.kind == 'therapy_request';
    if (!assessment && !therapy) {
      await _openSharedRecord(message);
      return;
    }
    if (!_isPatient) {
      if (assessment) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => SharedPatientDataScreen(
                    session: session,
                    apiClient: api,
                    initialAssessmentPatientId: widget.otherUserId,
                  )),
        );
      }
      return;
    }

    await _loadAccess();
    if (!mounted || !_ownerMatches) return;
    if (!_canSendText || meta['session_id'] != _access.sessionId) {
      _toast(assessment
          ? 'Sesi permintaan asesmen sudah berakhir.'
          : 'Sesi permintaan terapi sudah berakhir.');
      return;
    }
    final moduleId = meta['module_id']?.toString() ?? '';
    if (assessment && moduleId == 'screening') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => AssessmentScreen(session: session, apiClient: api)),
      );
      return;
    }
    final module = findTherapyModuleById(moduleId);
    if (module != null && module.isAssessment == assessment) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => TherapyDetailScreen(module: module)),
      );
    }
  }

  void _showShareSheet(BuildContext context) {
    if (_sharingData) return;
    if (!_canShare) {
      _toast('Berbagi data tersedia selama sesi atau paket aktif.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
                  'Riwayat Asesmen',
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
                  Icons.assignment_turned_in_rounded,
                  'Riwayat Terapi',
                  'worksheet',
                  MalvaColors.plum
                ),
                (
                  Icons.flag_rounded,
                  'Target & Kebiasaan',
                  'goals',
                  MalvaColors.amber
                ),
                (Icons.edit_note_rounded, 'Jurnal', 'diary', MalvaColors.plum),
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
        )),
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
    if (_sharingData || !_canShare) return;
    setState(() => _sharingData = true);
    try {
      await _shareDataImpl(kind, label);
    } on Object catch (error) {
      if (mounted)
        _toast('Gagal membagikan data: ${friendlyErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _sharingData = false);
    }
  }

  Future<void> _shareDataImpl(String kind, String label) async {
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
      case 'worksheet':
        await _shareTherapy(token: token, api: api);
        return;
      case 'summary':
        // Ringkasan 7 hari diambil dari SERVER, bukan dari store yang belum
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
        );
        if (metrics == null) {
          text = 'Ringkasan 7 hari belum tersedia '
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
        text = 'Ringkasan 7 hari: ${parts.join(', ')}.';
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
        final medicationSnapshot = await _collectMedications(
          token: token,
          api: api,
          fallback: store,
        );
        final meds =
            medicationSnapshot['medications'] as List<Map<String, dynamic>>;
        if (meds.isEmpty) {
          _toast('Belum ada data obat untuk dibagikan.');
          return;
        }
        metadata = medicationSnapshot;
        text = 'Daftar obat aktif: '
            '${meds.map((m) => '${m['name']} ${m['dosage']}').join(', ')}.';
      case 'goals':
        final goals = await _collectGoals(
          token: token,
          api: api,
          fallback: store,
        );
        if (goals.isEmpty) {
          _toast('Belum ada target untuk dibagikan.');
          return;
        }
        metadata = {'goals': goals};
        text = 'Target & Kebiasaan: '
            '${goals.take(5).map((goal) => goal['title']).join(', ')}.';
      case 'diary':
        final diaries = await _collectDiaries(
          token: token,
          api: api,
        );
        if (diaries.isEmpty) {
          _toast('Belum ada jurnal untuk dibagikan.');
          return;
        }
        if (!mounted || !_ownerMatches) return;
        final diary = await _pickCandidate(diaries, title: 'Pilih jurnal');
        if (diary == null || !mounted || !_canShare) return;
        final currentToken = ref.read(currentSessionProvider)?.accessToken;
        if (currentToken == null || currentToken.isEmpty) return;
        await api.updateDiaryAccess(
            accessToken: currentToken,
            diaryId: diary.metadata['diary_id'] as String,
            professionalId: widget.otherUserId,
            grant: true);
        if (!mounted || !_ownerMatches) return;
        final sent = await _sendShare(
            kind: 'diary', text: diary.text, metadata: diary.metadata);
        if (mounted && _ownerMatches) {
          _toast(sent
              ? 'Jurnal terkirim ke chat.'
              : 'Akses jurnal diberikan, tetapi pesan belum terkirim.');
        }
        return;
      default:
        return;
    }
    final sent = await _sendShare(kind: kind, text: text, metadata: metadata);
    if (sent && mounted) _toast('$label terkirim ke chat.');
  }

  Future<void> _shareTherapy({
    required String token,
    required MalvaApiClient api,
  }) async {
    List<BackendTherapySubmission> records;
    try {
      records = (await api.listTherapySubmissions(accessToken: token))
          .where(isTherapyRecordSubmission)
          .toList(growable: false);
    } on Object catch (error) {
      if (mounted && _ownerMatches) {
        _toast('Gagal memuat riwayat Terapi: ${friendlyErrorMessage(error)}');
      }
      return;
    }
    if (!mounted || !_ownerMatches) return;
    if (records.isEmpty) {
      _toast('Belum ada riwayat Terapi untuk dibagikan.');
      return;
    }
    final chosen = await _pickCandidate([
      for (final record in records)
        _ShareCandidate(
          title: record.title.trim().isEmpty ? 'Riwayat Terapi' : record.title,
          subtitle: _dateLabel(record.createdDateTime),
          text: record.summary,
          icon: Icons.assignment_turned_in_rounded,
          metadata: {'submission_id': record.id},
        ),
    ], title: 'Pilih riwayat Terapi');
    if (!mounted ||
        chosen == null ||
        !_canShare ||
        ref.read(currentSessionProvider)?.accessToken != token) return;
    await _shareSavedSubmission(
      token: token,
      api: api,
      submissionId: chosen.metadata['submission_id'] as String,
      kind: 'worksheet',
      label: 'Riwayat Terapi',
    );
  }

  Future<void> _shareSavedSubmission({
    required String token,
    required MalvaApiClient api,
    required String submissionId,
    required String kind,
    required String label,
  }) async {
    if (!_ownerMatches ||
        !_canShare ||
        ref.read(currentSessionProvider)?.accessToken != token) return;
    await api.shareTherapySubmission(
      accessToken: token,
      submissionId: submissionId,
      professionalId: widget.otherUserId,
    );
    if (!mounted || !_ownerMatches) return;
    // Endpoint share menyimpan pesan chat; mengirim pesan lagi membuat duplikat.
    final refreshed = await _loadHistory();
    if (!mounted || !_ownerMatches) return;
    final visible = refreshed &&
        _messages.any((message) =>
            message.kind == kind &&
            message.metadata?['submission_id'] == submissionId);
    _toast(visible
        ? '$label dibagikan ke profesional.'
        : '$label dibagikan, tetapi pesan chat belum terkonfirmasi. Muat ulang percakapan.');
  }

  Future<void> _openSharedTherapy(ChatMessage message) async {
    final submissionId = message.metadata?['submission_id']?.toString() ?? '';
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (submissionId.isEmpty || token == null || token.isEmpty) return;
    try {
      final record = await ref.read(apiClientProvider).getTherapySubmission(
            accessToken: token,
            submissionId: submissionId,
          );
      if (!mounted || !_ownerMatches) return;
      if (isTherapyRecordSubmission(record)) {
        await showTherapyRecordDetail(context, record);
        return;
      }
      await _showSharedDetail(message,
          detail: TherapySubmissionView(
            moduleId: record.moduleId,
            title: record.title,
            answers: record.answers,
            summary: record.summary,
          ));
    } on Object catch (error) {
      if (mounted && _ownerMatches) {
        final label = message.kind == 'assessment' ? 'assessment' : 'therapy';
        _toast('Gagal membuka $label record: ${friendlyErrorMessage(error)}');
      }
    }
  }

  Future<void> _openSharedRecord(ChatMessage message) async {
    if (!_ownerMatches) return;
    final meta = message.metadata ?? const <String, dynamic>{};
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    final submissionId = meta['submission_id']?.toString() ?? '';
    if (submissionId.isNotEmpty &&
        (message.kind == 'worksheet' || message.kind == 'assessment')) {
      await _openSharedTherapy(message);
      return;
    }
    if (meta['answers'] is Map && meta['module_id'] != null) {
      final moduleId = meta['module_id'].toString();
      final answers = Map<String, dynamic>.from(meta['answers'] as Map);
      final title = meta['title']?.toString() ?? 'Record dibagikan';
      final summary = meta['summary']?.toString() ?? message.text;
      if (findTherapyModuleById(moduleId)?.isAssessment != true) {
        await showTherapySubmissionDetail(
          context,
          moduleId: moduleId,
          title: title,
          answers: answers,
          summary: summary,
          createdAt: parseWibStored(meta['created_at']?.toString()) ??
              message.timestamp,
        );
        return;
      }
      await _showSharedDetail(message,
          detail: TherapySubmissionView(
            moduleId: moduleId,
            title: title,
            answers: answers,
            summary: summary,
          ));
      return;
    }
    final screeningId = meta['screening_id']?.toString() ?? '';
    if (screeningId.isNotEmpty) {
      try {
        final screening = await ref.read(apiClientProvider).getScreeningDetail(
              accessToken: token,
              screeningId: screeningId,
              patientId: _isPatient
                  ? (ref.read(currentSessionProvider)?.backendUserId ?? '')
                  : widget.otherUserId,
            );
        if (!mounted || !_ownerMatches) return;
        await _showSharedDetail(message, screening: screening);
        return;
      } on Object {
        // A shared snapshot remains readable when current category consent is absent.
      }
    }
    if (!mounted || !_ownerMatches) return;
    await _showSharedDetail(message);
  }

  Future<void> _showDiaryDetail(ChatMessage message) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (sheet) => _ownedOverlay(ValueListenableBuilder<int>(
          valueListenable: _chatRevision,
          builder: (context, revision, _) {
            if (!mounted || !_messages.any((entry) => entry.id == message.id)) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Detail jurnal sudah tidak tersedia.'));
            }
            return SafeArea(
                top: false,
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(sheet).height * .78),
                    child: ChatDiaryDetail(message: message)));
          },
        )),
      );

  Widget _guardAssessmentDetail(String id, Widget detail) =>
      _ownedOverlay(ValueListenableBuilder<int>(
        valueListenable: _chatRevision,
        child: detail,
        builder: (context, _, child) =>
            mounted && _messages.any((message) => message.id == id)
                ? child!
                : const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Detail asesmen sudah tidak tersedia.')),
      ));

  Future<void> _showSharedDetail(ChatMessage message,
          {Widget? detail, BackendScreeningSession? screening}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ownedOverlay(SafeArea(
            child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .85),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: screening != null
                  ? SharedRecordDetail.screening(screening: screening)
                  : SharedRecordDetail(
                      message: message,
                      detail: detail,
                      showClinicalAudit: true)),
        ))),
      );

  /// Bagikan assessment record: screening PHQ-9/GAD-7 dan worksheet
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
    if (!mounted || !_ownerMatches) return;
    if (candidates.isEmpty) {
      _toast('Belum ada riwayat Asesmen untuk dibagikan.');
      return;
    }
    var chosen = candidates.first;
    if (candidates.length > 1) {
      final picked = await _pickCandidate(candidates);
      if (picked == null) return; // pasien membatalkan
      chosen = picked;
    }
    final submissionId = chosen.metadata['submission_id']?.toString() ?? '';
    if (submissionId.isNotEmpty) {
      await _shareSavedSubmission(
          token: token,
          api: api,
          submissionId: submissionId,
          kind: 'assessment',
          label: label);
      return;
    }
    final sent = await _sendShare(
      kind: 'assessment',
      text: chosen.text,
      metadata: chosen.metadata,
    );
    if (sent && mounted) _toast('$label terkirim ke chat.');
  }

  /// Kandidat assessment record: screening server + worksheet DASS/WHO-5.
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
        if (screening.phq9.score < 0 || screening.gad7.score < 0) continue;
        final text = 'Hasil skrining: PHQ-9 '
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
            'phq9_max_score': screening.phq9.maxScore,
            'gad7_max_score': screening.gad7.maxScore,
            'phq9_level': screening.phq9.level,
            'gad7_level': screening.gad7.level,
            if (screening.phq9.hasCertaintyFactor)
              'phq9_cf': screening.phq9.certaintyFactor,
            if (screening.gad7.hasCertaintyFactor)
              'gad7_cf': screening.gad7.certaintyFactor,
            'crisis_flag': screening.crisisFlag,
            'summary': text,
            'shared_at': wibIso(screening.createdAt ?? wibNow()),
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
            'shared_at': wibIso(sub.createdDateTime ?? wibNow()),
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
      final phqLevel = AssessmentEngine.levelFromScore(
          AssessmentType.phq9, bundle?.phq9.score,
          maxScore: bundle?.phq9.maxScore);
      final gadLevel = AssessmentEngine.levelFromScore(
          AssessmentType.gad7, bundle?.gad7.score,
          maxScore: bundle?.gad7.maxScore);
      if (bundle != null && phqLevel != null && gadLevel != null) {
        final overall = bundle.crisisFlag
            ? RiskLevel.crisis
            : phqLevel.index > gadLevel.index
                ? phqLevel
                : gadLevel;
        final text = 'Hasil skrining: PHQ-9 ${bundle.phq9.score} '
            '(${phqLevel.label}), GAD-7 ${bundle.gad7.score} '
            '(${gadLevel.label}).';
        out.add(_ShareCandidate(
          title: 'PHQ-9 & GAD-7 — ${overall.label}',
          subtitle: _dateLabel(bundle.createdAt),
          text: text,
          icon: Icons.fact_check_rounded,
          metadata: {
            'source': 'screening',
            'phq9_score': bundle.phq9.score,
            'gad7_score': bundle.gad7.score,
            if (bundle.phq9.hasCertaintyFactor)
              'phq9_cf': bundle.phq9.certaintyFactor,
            if (bundle.gad7.hasCertaintyFactor)
              'gad7_cf': bundle.gad7.certaintyFactor,
            'overall_level': overall.label,
            'crisis_flag': bundle.crisisFlag,
            'summary': text,
            'shared_at': wibIso(bundle.createdAt),
          },
        ));
      }
      final result = store.assessments.isEmpty ? null : store.assessments.last;
      final resultLevel = result == null
          ? null
          : AssessmentEngine.levelFromScore(result.type, result.score,
              maxScore: result.maxScore);
      if (result != null && resultLevel != null) {
        final text = 'Hasil ${result.type.title}: '
            '${result.score}/${result.maxScore} (${resultLevel.label}).';
        out.add(_ShareCandidate(
          title: result.type.title,
          subtitle: _dateLabel(result.createdAt),
          text: text,
          icon: Icons.assignment_turned_in_rounded,
          metadata: {
            'source': 'screening',
            'module_id': result.type.name,
            result.type.name: {
              'score': result.score,
              'max_score': result.maxScore,
              'level': resultLevel.label,
              if (result.hasCertaintyFactor) 'cf': result.certaintyFactor,
            },
            'crisis_flag': result.crisisFlag,
            'summary': text,
            'shared_at': wibIso(result.createdAt),
          },
        ));
      }
    }
    return out;
  }

  /// Bottom sheet pemilihan assessment record (dipanggil bila kandidat > 1).
  Future<_ShareCandidate?> _pickCandidate(List<_ShareCandidate> candidates,
      {String title = 'Pilih riwayat Asesmen'}) {
    if (!_ownerMatches) return Future.value(null);
    return showModalBottomSheet<_ShareCandidate>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => _ownedOverlay(SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17)),
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
      )),
    );
  }

  Widget _ownedOverlay(Widget child) =>
      Consumer(builder: (context, overlayRef, _) {
        final current = overlayRef.watch(currentSessionProvider);
        return !_ownerChanged && _owner == _ownerKey(current)
            ? child
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Sesi akun telah berubah.'));
      });

  /// Daftar obat: server dulu, fallback store lokal.
  Future<Map<String, dynamic>> _collectMedications({
    required String token,
    required MalvaApiClient api,
    required MalvaStoreState fallback,
  }) async {
    try {
      final medications = await api.listMedications(accessToken: token);
      int? adherence;
      try {
        final logs = await api.listMedicationLogs(accessToken: token, limit: 0);
        adherence = clinicalMedicationAdherence(medications, logs);
      } on Object {/* An unavailable history is not zero adherence. */}
      return {
        'medications': [
          for (final med in medications)
            sharedMedicationSnapshot(med.toMedication(),
                reminderTime: med.reminderTime,
                relationToMeal: med.relationToMeal)
        ],
        if (adherence != null) 'medication_adherence': adherence,
      };
    } on Object {
      return {
        'medications': [
          for (final med in fallback.medications) sharedMedicationSnapshot(med)
        ]
      };
    }
  }

  /// Daftar goals aktif: server dulu, fallback store lokal.
  Future<List<Map<String, dynamic>>> _collectGoals({
    required String token,
    required MalvaApiClient api,
    required MalvaStoreState fallback,
  }) async {
    try {
      final on = ServerClock.now();
      final backendGoals =
          await api.listGoals(accessToken: token, on: wibDateKey(on));
      return [
        for (final goal in backendGoals)
          if (goal.isActive)
            {
              'title': goal.title,
              'category': goal.category,
              'last_logged_on': goal.lastLoggedOn,
              'target_per_week': goal.effectiveWeeklyTarget(on),
              'done_this_week': goal.doneThisWeek,
              'is_active': goal.isActive,
              if (goal.doneToday != null) 'done_today': goal.doneToday,
              'today_value': goal.todayValue,
              'streak_days': goal.streakDays,
              if (goal.details case final details?) ...{
                'method': details.method,
                'daily_target': details.target,
                'unit': details.unit,
                'schedule_label': details.scheduleLabel,
                if (details.weeklyTarget == 0) 'flexible_weekly_target': true,
                if (details.note.trim().isNotEmpty) 'activity': details.note,
                if (details.method == 'checklist')
                  'steps': [
                    for (final step in details.steps)
                      {
                        'label': step.label,
                        'done': goal.todayCompletedStepIds.contains(step.id)
                      },
                  ],
              },
            },
      ];
    } on Object {
      // Fallback di bawah.
    }
    return [
      for (final goal in fallback.goals)
        {
          'title': goal.title,
          'done_today': goal.completedToday,
          'is_active': true,
        },
    ];
  }

  /// Izin dibagikan untuk ID diary tersimpan, termasuk catatan lama.
  Future<List<_ShareCandidate>> _collectDiaries({
    required String token,
    required MalvaApiClient api,
  }) async {
    final entries = await api.listDiaryEntries(accessToken: token, limit: 0);
    return [
      for (final entry in entries)
        _ShareCandidate(
          title: entry.title.trim().isEmpty ? 'Jurnal' : entry.title.trim(),
          subtitle: _dateLabel(entry.occurredAt),
          text: 'Jurnal dibagikan',
          icon: Icons.edit_note_rounded,
          metadata: {'diary_id': entry.id},
        ),
    ];
  }

  /// Label tanggal ringkas untuk subjudul pilihan (mis. "7/9/2026").
  static String _dateLabel(DateTime? date) {
    if (date == null) return 'Tanggal tidak tercatat';
    return formatWibDate(date);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    ref.listen(authStateProvider, (previous, next) {
      if (_ownerChanged) return;
      if (_ownerKey(next.session) == _owner) {
        if (previous?.session?.accessToken != next.session?.accessToken) {
          setState(() {
            _onlineUsers.clear();
            _otherTyping = false;
            _chatState = ChatState.disconnected;
          });
          _initChat(next.session);
        }
        return;
      }
      setState(() => _ownerChanged = true);
      _accessRequest++;
      _accessPoll?.cancel();
      _accessExpiry?.cancel();
      _disposeChat();
      _messages.clear();
      _inputController.clear();
      _chatRevision.value++;
    });
    if (!_ownerMatches)
      return Scaffold(
          appBar: AppBar(title: const Text('Percakapan')),
          body: const Center(
              child: Text(
                  'Sesi akun telah berubah. Buka kembali percakapan dari akun aktif.')));
    final otherOnline = _onlineUsers[widget.otherUserId];
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        toolbarHeight: 72,
        // AppBar global bertema transparan + teks putih; di layar chat latar
        // terang membuat nama profesional putih tidak terbaca. Jadi warna
        // di-set eksplisit di sini (ungu Malva) dan teksnya tetap putih.
        backgroundColor: MalvaColors.seed,
        flexibleSpace: Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF55216C), Color(0xFFA43CA5)]))),
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
            if (_isPatient)
              ProfessionalAvatar(
                displayName: widget.otherUserName,
                photoUrl: _photoUrl,
                radius: 18,
                borderRadius: BorderRadius.circular(11),
              )
            else
              PatientAvatar(
                displayName: widget.otherUserName,
                avatar: _patientAvatar,
                radius: 18,
                borderRadius: BorderRadius.circular(11),
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
                      fontFamily: 'Roboto',
                    ),
                  ),
                  if (_isPatient)
                    Text(_professionalRole,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'Roboto')),
                  _ConnectionStatusChip(
                      state: _chatState,
                      peerOnline: otherOnline,
                      reconnecting: _chatService != null),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .42),
              child: MiniSummaryButton(
                  iconOnly: true,
                  patientId: _isPatient ? null : widget.otherUserId)),
          _TypingIndicator(isTyping: _otherTyping),
        ],
      ),
      body: Column(
        children: [
          if (_accessLoaded &&
              !_noticeDismissed &&
              !_liveSession &&
              !(_isDeadConversation && _isPatient))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              color: const Color(0xFFFFF9EB),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                    padding: EdgeInsets.only(top: 5, right: 9),
                    child: Icon(Icons.info_outline_rounded,
                        size: 18, color: Color(0xFFD6A34B))),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          _liveExpired
                              ? 'Sesi berakhir. Riwayat chat tetap tersedia.'
                              : _isPatient && _access.hasActivePackage
                                  ? 'Di Luar Jam Sesi: Kamu tetap dapat memperbarui data jurnal, target, dan lembar kerja. Chat interaktif aktif saat sesi konseling berlangsung.'
                                  : _access.reason.isEmpty
                                      ? 'Chat teks aktif saat sesi berjalan.'
                                      : _access.reason,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: Color(0xFF8E6F46)),
                        ))),
                IconButton(
                    tooltip: 'Tutup informasi sesi',
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => setState(() => _noticeDismissed = true),
                    icon: const Icon(Icons.close,
                        size: 15, color: Color(0xFFB8A28D))),
              ]),
            ),
          if (_accessLoaded && _liveSession)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: MalvaColors.mint.withValues(alpha: 0.15),
              child: Text(
                _isPatient
                    ? 'Sesi berjalan — kamu & profesional bisa chat di sini.'
                    : 'Sesi berjalan — kamu & pasien bisa chat di sini.',
                textAlign: TextAlign.center,
                style: const TextStyle(
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
                : Stack(children: [
                    ListView.builder(
                      reverse: true,
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: _messages.length +
                          (_olderHistoryCursor == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return Center(
                              child: TextButton(
                            onPressed: _loadingOlderHistory
                                ? null
                                : () => _loadHistory(older: true),
                            child: Text(_loadingOlderHistory
                                ? 'Memuat riwayat…'
                                : 'Muat pesan sebelumnya'),
                          ));
                        }
                        index = _messages.length - 1 - index;
                        final msg = _messages[index];
                        final onDelete = msg.isMine && msg.id.isNotEmpty
                            ? () => _confirmDeleteMessage(msg)
                            : null;
                        final showTimestamp = index == 0 ||
                            formatWibDate(_messages[index - 1].timestamp) !=
                                formatWibDate(msg.timestamp);
                        return Column(
                          key: ValueKey(msg.id),
                          children: [
                            if (showTimestamp)
                              _TimestampLabel(date: msg.timestamp),
                            const SizedBox(height: 6),
                            if (msg.kind == 'session_cancellation')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SessionCancellationCard(message: msg),
                              )
                            else if (msg.kind == 'session_follow_up')
                              Align(
                                alignment: msg.isMine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.sizeOf(context).width *
                                              .88),
                                  child: SessionFollowUpCard(
                                    message: msg,
                                    onBook: _isPatient
                                        ? () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      DoctorProfileScreen(
                                                        doctorUserId:
                                                            widget.otherUserId,
                                                        doctorName: widget
                                                            .otherUserName,
                                                      )),
                                            )
                                        : null,
                                  ),
                                ),
                              )
                            else if (const [
                                  'summary',
                                  'progress',
                                  'goals',
                                  'habits',
                                  'assessment',
                                  'screening',
                                  'prescription',
                                  'medication',
                                  'diary'
                                ].contains(msg.kind) ||
                                msg.kind == 'worksheet')
                              Align(
                                  alignment: msg.isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.sizeOf(context).width *
                                                  (const ['goals', 'habits']
                                                          .contains(msg.kind)
                                                      ? .86
                                                      : const [
                                                          'medication',
                                                          'prescription',
                                                          'diary',
                                                          'assessment',
                                                          'screening',
                                                          'worksheet'
                                                        ].contains(msg.kind)
                                                          ? .90
                                                          : .70)),
                                      child: _ChatMessageActions(
                                        onDelete: onDelete,
                                        child: ChatSharedRecordCard(
                                            key: ValueKey(msg.id),
                                            message: msg,
                                            guardDetail: (detail) =>
                                                _guardAssessmentDetail(
                                                    msg.id, detail),
                                            onOpenRecord: msg.kind ==
                                                    'worksheet'
                                                ? () => _openSharedRecord(msg)
                                                : null,
                                            onOpenDiary: msg.kind == 'diary'
                                                ? () => _showDiaryDetail(msg)
                                                : null),
                                      )))
                            else if (const [
                                  'assessment_request',
                                  'therapy_request',
                                  'session_summary',
                                  'attachment'
                                ].contains(msg.kind) ||
                                (msg.kind == 'goals' &&
                                    msg.metadata?['session_id'] != null &&
                                    msg.senderId ==
                                        (_isPatient
                                            ? widget.otherUserId
                                            : (ref
                                                    .read(
                                                        currentSessionProvider)
                                                    ?.backendUserId ??
                                                ref
                                                    .read(
                                                        currentSessionProvider)
                                                    ?.identifier))))
                              Align(
                                  alignment: msg.isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              (const [
                                                'session_summary',
                                                'assessment_request',
                                                'therapy_request'
                                              ].contains(msg.kind)
                                                  ? .95
                                                  : .85)),
                                      child: _ChatMessageActions(
                                        onDelete: onDelete,
                                        child: ClinicalChatCard(
                                            message: msg,
                                            isPatient: _isPatient,
                                            onAction: () =>
                                                _openClinicalCard(msg)),
                                      )))
                            else
                              _ChatBubble(
                                message: msg,
                                onDelete: onDelete,
                                isProfessional: _isPatient != msg.isMine,
                                senderPhotoUrl:
                                    _professionalPhotoUrl.isEmpty && _isPatient
                                        ? _photoUrl
                                        : _professionalPhotoUrl,
                                senderPatientAvatar: _patientAvatar,
                                senderRole: _isPatient != msg.isMine
                                    ? _professionalRole
                                    : 'Pasien',
                                onOpenRecord: msg.kind == 'worksheet'
                                    ? () => _openSharedRecord(msg)
                                    : null,
                              ),
                          ],
                        );
                      },
                    ),
                    if (_showLatestButton)
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          tooltip: 'Ke pesan terbaru',
                          onPressed: _scrollToBottom,
                          child: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ),
                  ]),
          ),
          if (_accessLoaded && _isDeadConversation && _isPatient)
            _BookSessionCta(
              doctorName: widget.otherUserName,
              onBook: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorProfileScreen(
                    doctorUserId: widget.otherUserId,
                    doctorName: widget.otherUserName,
                  ),
                ),
              ),
            )
          else
            _ChatInput(
              controller: _inputController,
              enabled: _canSendText,
              onChanged: _onInputChanged,
              onSend: _send,
              onShareTap: _isPatient
                  ? () => _showShareSheet(context)
                  : _ownerMatches
                      ? _openProfessionalTools
                      : null,
              onAttachTap: !_isPatient && _ownerMatches
                  ? () => _openProfessionalTools(openFiles: true)
                  : null,
              disabledHint: _liveExpired
                  ? 'Sesi berakhir. Riwayat chat tetap tersedia.'
                  : _isPatient && _canShare
                      ? 'Di luar sesi: kamu bisa mengirim data (jurnal, target, '
                          'asesmen, dll). Chat aktif saat sesi berjalan.'
                      : _accessLoaded
                          ? (_access.reason.isEmpty ? null : _access.reason)
                          : null,
            ),
        ],
      ),
    );
  }
}

class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip(
      {required this.state,
      required this.peerOnline,
      required this.reconnecting});

  final ChatState state;
  final bool? peerOnline;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ChatState.connecting => ('Menyambungkan...', MalvaColors.amber),
      ChatState.connected => switch (peerOnline) {
          true => ('Online', MalvaColors.mint),
          false => ('Offline', const Color(0xFFC8B6CF)),
          null => ('Status belum diketahui', const Color(0xFFC8B6CF)),
        },
      ChatState.disconnected => (
          reconnecting ? 'Menghubungkan ulang...' : 'Tidak tersambung',
          MalvaColors.amber
        ),
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
        Flexible(
            child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
          ),
        )),
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
            if (state == ChatState.connected)
              Image.asset('assets/reference/chat-empty.png',
                  width: 156, excludeFromSemantics: true)
            else
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
    final day = toWib(date);
    const weekdays = [
      'SENIN',
      'SELASA',
      'RABU',
      'KAMIS',
      'JUMAT',
      'SABTU',
      'MINGGU'
    ];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MEI',
      'JUN',
      'JUL',
      'AGU',
      'SEP',
      'OKT',
      'NOV',
      'DES'
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
              color: const Color(0xFFE7EDF3),
              borderRadius: BorderRadius.circular(24)),
          child: Text(
            '${weekdays[day.weekday - 1]}, ${day.day} ${months[day.month - 1]} ${day.year}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black38,
                fontWeight: FontWeight.w700,
                fontSize: 10),
          )),
    );
  }
}

class _ChatMessageActions extends StatelessWidget {
  const _ChatMessageActions({required this.onDelete, required this.child});

  final VoidCallback? onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delete = onDelete;
    if (delete == null) return child;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Hapus untuk semua'): delete,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: delete,
        onSecondaryTap: delete,
        child: child,
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble(
      {required this.message,
      this.onOpenRecord,
      this.onDelete,
      this.isProfessional = false,
      this.senderPhotoUrl = '',
      this.senderPatientAvatar,
      this.senderRole = 'Profesional'});

  final ChatMessage message;
  final VoidCallback? onOpenRecord;
  final VoidCallback? onDelete;
  final bool isProfessional;
  final String senderPhotoUrl;
  final String? senderPatientAvatar;
  final String senderRole;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final outgoingText = isMine && message.kind == 'text';
    final showIdentity = !outgoingText && (isProfessional || !isMine);
    const outgoingMeta = Color(0xffefdcf4);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        margin: const EdgeInsets.only(bottom: 4),
        padding: outgoingText
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: outgoingText
              ? null
              : showIdentity
                  ? Colors.white
                  : const Color(0xFFF1E6FA),
          gradient: outgoingText
              ? const LinearGradient(
                  colors: [Color(0xff532173), Color(0xff7d2997)])
              : null,
          border: Border.all(color: const Color(0xFFECE4F5)),
          borderRadius: outgoingText
              ? const BorderRadius.only(
                  topLeft: Radius.circular(17),
                  topRight: Radius.circular(2),
                  bottomLeft: Radius.circular(17),
                  bottomRight: Radius.circular(17))
              : BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 3))
          ],
        ),
        child: _ChatMessageActions(
          onDelete: onDelete,
          child: InkWell(
            onTap: onOpenRecord,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showIdentity)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(children: [
                        if (isProfessional)
                          ProfessionalAvatar(
                              displayName: message.senderName,
                              photoUrl: senderPhotoUrl,
                              radius: 14,
                              borderRadius: BorderRadius.circular(14))
                        else
                          PatientAvatar(
                              displayName: message.senderName,
                              avatar: senderPatientAvatar,
                              radius: 14,
                              borderRadius: BorderRadius.circular(8)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(message.senderName,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: MalvaColors.ink))),
                        const SizedBox(width: 6),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: const Color(0xFFF5EBFF),
                                borderRadius: BorderRadius.circular(5)),
                            child: Text(senderRole,
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: MalvaColors.seed))),
                      ])),
                if (message.kind == 'file') ...[
                  _FileBubble(message: message, isMine: false),
                  const SizedBox(height: 6),
                ] else if (message.kind == 'voice') ...[
                  _VoiceBubble(message: message, isMine: false),
                  const SizedBox(height: 6),
                ] else if (message.kind != 'text') ...[
                  _SharedCardBubble(message: message, isMine: false),
                  const SizedBox(height: 6),
                ],
                Text(
                  message.text,
                  style: TextStyle(
                    color: outgoingText ? Colors.white : MalvaColors.ink,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                    alignment: Alignment.centerRight,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(ChatScreen.formatMessageTime(message.timestamp),
                          style: TextStyle(
                              fontSize: 10,
                              color: outgoingText
                                  ? outgoingMeta
                                  : Colors.black38)),
                      if (outgoingText && message.id.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_rounded,
                            size: 13,
                            color: outgoingMeta,
                            semanticLabel: 'Terkirim'),
                      ],
                    ])),
              ],
            ),
          ),
        ),
      ),
    );
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
      'diary' => (Icons.edit_note_rounded, 'Jurnal'),
      'goals' => (Icons.flag_rounded, 'Target & Kebiasaan'),
      'habits' => (Icons.flag_rounded, 'Target & Kebiasaan'),
      'summary' => (Icons.auto_awesome_rounded, 'Ringkasan'),
      'assessment' => (Icons.fact_check_rounded, 'Asesmen'),
      'screening' => (Icons.fact_check_rounded, 'Skrining'),
      'worksheet' => (Icons.assignment_turned_in_rounded, 'Riwayat Terapi'),
      'prescription' => (Icons.medication_rounded, 'Obat & Resep'),
      'medication' => (Icons.medication_rounded, 'Obat & Resep'),
      'progress' => (Icons.show_chart_rounded, 'Progres'),
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
    this.onAttachTap,
    this.disabledHint,
  });

  final TextEditingController controller;

  /// True = chat teks boleh dikirim (sesi berjalan).
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Null = tombol share disembunyikan (profesional / tanpa paket).
  final VoidCallback? onShareTap;
  final VoidCallback? onAttachTap;
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
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onShareTap != null)
              IconButton(
                tooltip: 'Bagikan data',
                onPressed: onShareTap,
                style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9)),
                icon: const Icon(Icons.add_rounded),
              ),
            if (onAttachTap != null)
              IconButton(
                tooltip: 'Lampirkan berkas',
                onPressed: onAttachTap,
                icon: const Icon(Icons.attach_file),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                onChanged: onChanged,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                minLines: enabled ? 1 : 3,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: enabled
                      ? 'Ketik pesan...'
                      : (disabledHint ?? 'Chat aktif saat sesi berjalan'),
                  hintMaxLines: 4,
                  hintStyle: const TextStyle(
                      fontSize: 12, height: 1.5, color: Color(0xFF9CA8B7)),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                  disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF8D40DB),
                  disabledBackgroundColor: const Color(0xFF8D40DB),
                  disabledForegroundColor: Colors.white70),
              onPressed: enabled ? onSend : null,
              icon: const Icon(CupertinoIcons.paperplane, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// CTA untuk percakapan yang belum punya sesi aktif: ajak pasien menjadwalkan
/// sesi dengan profesional ini, alih-alih menampilkan composer nonaktif dengan
/// kalimat kriptik.
class _BookSessionCta extends StatelessWidget {
  const _BookSessionCta({required this.doctorName, required this.onBook});

  final String doctorName;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MalvaColors.seed.withValues(alpha: 0.06),
        border: Border(
          top: BorderSide(color: MalvaColors.seed.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Belum ada sesi terjadwal dengan $doctorName.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          const Text(
            'Jadwalkan sesi untuk mulai berkonsultasi dan mengobrol di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onBook,
            icon: const Icon(Icons.event_available_rounded),
            label: const Text('Jadwalkan Sesi'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}
