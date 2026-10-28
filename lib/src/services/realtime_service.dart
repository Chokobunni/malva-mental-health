import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Satu event realtime dari server (mis. `professional.profile.updated`).
class RealtimeEvent {
  const RealtimeEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;

  /// Ambil nilai string dari [data] dengan aman.
  String stringValue(String key) => data[key]?.toString() ?? '';
}

/// Klien WebSocket ringan untuk event realtime non-chat.
///
/// Sengaja dipisah dari `ChatService` supaya:
/// 1. koneksi chat (yang terikat satu lawan bicara) tidak terganggu;
/// 2. hub backend mendukung banyak klien per pengguna, jadi keduanya bisa
///    hidup bersamaan tanpa saling menutup.
///
/// Koneksi bersifat best-effort: gagal koneksi tidak boleh mengganggu UI,
/// dan akan dicoba ulang dengan backoff eksponensial.
class RealtimeService {
  RealtimeService({required this.accessToken, required this.baseUrl});

  final String accessToken;
  final String baseUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;
  bool _connected = false;

  final _eventController = StreamController<RealtimeEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Aliran event dari server. Pemakai menyaring sendiri tipe yang dibutuhkan.
  Stream<RealtimeEvent> get events => _eventController.stream;

  /// Status koneksi: `true` saat tersambung, `false` saat terputus.
  Stream<bool> get connection => _connectionController.stream;

  bool get isConnected => _connected;

  /// Mulai menyambung. Aman dipanggil berkali-kali.
  void connect() {
    if (_disposed || _connected) return;
    _reconnectTimer?.cancel();
    try {
      final wsScheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
      final base = baseUrl.replaceFirst(RegExp(r'^https?'), wsScheme);
      final uri = Uri.parse('$base/v1/realtime/ws?access_token=$accessToken');

      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );

      _connected = true;
      _attempt = 0;
      _emitConnection(true);
    } on Object {
      _handleDisconnect();
    }
  }

  void _onData(dynamic raw) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type']?.toString() ?? '';
      if (type.isEmpty) return;
      final dataRaw = decoded['data'];
      final data =
          dataRaw is Map<String, dynamic> ? dataRaw : <String, dynamic>{};
      if (!_eventController.isClosed) {
        _eventController.add(RealtimeEvent(type: type, data: data));
      }
    } on Object {
      // Abaikan pesan yang tidak valid — jangan sampai memutus koneksi.
    }
  }

  void _handleDisconnect() {
    if (_disposed) return;
    final wasConnected = _connected;
    _connected = false;
    if (wasConnected) _emitConnection(false);
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    // Backoff: 2s, 4s, 8s, 16s, lalu tetap 30s.
    final seconds = (1 << _attempt).clamp(2, 30);
    if (_attempt < 5) _attempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), connect);
  }

  void _emitConnection(bool connected) {
    if (_connectionController.isClosed) return;
    _connectionController.add(connected);
  }

  /// Tutup koneksi dan bebaskan semua sumber daya.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } on Object {
      // Diabaikan: koneksi mungkin sudah tertutup.
    }
    _channel = null;
    _connected = false;
    await _eventController.close();
    await _connectionController.close();
  }
}
