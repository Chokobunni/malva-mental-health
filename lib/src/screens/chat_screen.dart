import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/chat_service.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.session,
    this.apiClient,
    required this.otherUserName,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String otherUserName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  ChatService? _chatService;
  ChatState _chatState = ChatState.disconnected;
  bool _otherTyping = false;
  StreamSubscription<ChatState>? _stateSub;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<bool>? _typingSub;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  void _initChat() {
    final session = widget.session;
    if (session?.accessToken == null || session!.accessToken!.isEmpty) return;
    if (widget.apiClient == null) return;

    final apiClient = widget.apiClient;
    if (apiClient == null) return;
    final baseUri = apiClient.baseUri;
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final baseUrl = '$wsScheme://${baseUri.host}${baseUri.port == 80 || baseUri.port == 443 ? '' : ':${baseUri.port}'}';

    _chatService = ChatService(
      userId: session.backendUserId ?? session.identifier,
      accessToken: session.accessToken!,
      baseUrl: baseUrl,
    );

    _stateSub = _chatService!.stateStream.listen((state) {
      if (mounted) setState(() => _chatState = state);
    });

    _messageSub = _chatService!.messageStream.listen((msg) {
      if (!mounted) return;
      setState(() => _messages.add(msg));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });

    _typingSub = _chatService!.typingStream.listen((isTyping) {
      if (mounted) setState(() => _otherTyping = isTyping);
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
    _chatService?.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _chatState != ChatState.connected) return;
    _chatService?.sendMessage(text);
    _inputController.clear();
    _chatService?.stopTyping();
  }

  void _onInputChanged(String value) {
    if (value.trim().isNotEmpty) {
      _chatService?.startTyping();
    } else {
      _chatService?.stopTyping();
    }
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
            _ConnectionStatusChip(state: _chatState),
          ],
        ),
        actions: [
          _TypingIndicator(isTyping: _otherTyping),
        ],
      ),
      body: Column(
        children: [
          if (_chatState == ChatState.connecting)
            const LinearProgressIndicator(),
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
                          _messages[index - 1].timestamp
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
            enabled: _chatState == ChatState.connected,
            onChanged: _onInputChanged,
            onSend: _send,
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
            Icon(icon, size: 56, color: MalvaColors.seed.withValues(alpha: 0.5)),
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

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

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
                      : 'Menunggu koneksi...',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
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
