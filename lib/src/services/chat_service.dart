import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models.dart';

class ChatService {
  ChatService({
    required this.userId,
    required this.accessToken,
    required this.baseUrl,
    this.senderName = '',
  });

  final String userId;
  final String accessToken;
  final String baseUrl;
  final String senderName;

  WebSocketChannel? _channel;
  ChatState _state = ChatState.disconnected;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _typingDebounceTimer;
  bool _disposed = false;

  final _pendingMessages = <Map<String, dynamic>>[];

  final _stateController = StreamController<ChatState>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _presenceController = StreamController<ChatPresence>.broadcast();

  Stream<ChatState> get stateStream => _stateController.stream;
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<bool> get typingStream => _typingController.stream;
  Stream<ChatPresence> get presenceStream => _presenceController.stream;

  ChatState get currentState => _state;

  void connect() {
    if (_disposed) return;
    _updateState(ChatState.connecting);

    try {
      final wsScheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
      final base = baseUrl.replaceFirst(RegExp(r'^https?'), wsScheme);
      final uri = Uri.parse('$base/v1/realtime/ws?access_token=$accessToken');

      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      _updateState(ChatState.connected);
      _reconnectAttempt = 0;
      _startPing();
      _flushPendingMessages();
    } on Object catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      final type = decoded['type']?.toString() ?? '';
      final eventData = decoded['data'];

      switch (type) {
        case 'chat_message':
          if (eventData is Map<String, dynamic>) {
            final msg = ChatMessage.fromJson(
              eventData,
              currentUserId: userId,
            );
            _messageController.add(msg);
          }
        case 'typing_indicator':
          if (eventData is Map<String, dynamic>) {
            final senderId = eventData['sender_id']?.toString() ?? '';
            final isTyping = eventData['typing'] == true;
            if (senderId != userId) {
              _typingController.add(isTyping);
            }
          }
        case 'realtime.connected':
          break;
        case 'presence':
          if (eventData is Map<String, dynamic>) {
            final presence = ChatPresence(
              userId: eventData['user_id']?.toString() ?? '',
              isOnline: eventData['online'] == true,
            );
            _presenceController.add(presence);
          }
          break;
        default:
          break;
      }
    } on Object {
      // ignore malformed messages
    }
  }

  void _onError(Object error) {
    _updateState(ChatState.disconnected);
    _stopPing();
    _scheduleReconnect();
  }

  void _onDone() {
    _updateState(ChatState.disconnected);
    _stopPing();
    _scheduleReconnect();
  }

  void _updateState(ChatState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_channel != null && _state == ChatState.connected) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } on Object {
          // connection likely dead
        }
      }
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    final delay = Duration(
      seconds: (1 << _reconnectAttempt).clamp(1, 60),
    );
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, connect);
  }

  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final event = {
      'type': 'chat_message',
      'data': {
        'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
        'sender_id': userId,
        'sender_name': senderName,
        'text': trimmed,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    if (_state == ChatState.connected && _channel != null) {
      _channel!.sink.add(jsonEncode(event));
    } else {
      _pendingMessages.add(event);
    }
  }

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    final toSend = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();
    for (final event in toSend) {
      if (_channel != null && _state == ChatState.connected) {
        _channel!.sink.add(jsonEncode(event));
      } else {
        _pendingMessages.add(event);
      }
    }
  }

  void startTyping() {
    _typingDebounceTimer?.cancel();
    _sendTyping(true);
  }

  void stopTyping() {
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
      _sendTyping(false);
    });
  }

  void _sendTyping(bool isTyping) {
    if (_state != ChatState.connected || _channel == null) return;
    final event = {
      'type': 'typing_indicator',
      'data': {
        'sender_id': userId,
        'typing': isTyping,
      },
    };
    _channel!.sink.add(jsonEncode(event));
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopPing();
    _typingDebounceTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _updateState(ChatState.disconnected);
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _stateController.close();
    _messageController.close();
    _typingController.close();
    _presenceController.close();
  }
}
