import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

// ============================================================
// NOTIFICATIONS — daftar notifikasi + tandai baca
// ============================================================

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<BackendNotification> _items = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login diperlukan untuk melihat notifikasi.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await apiClient.listNotifications(accessToken: accessToken);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat notifikasi: $e';
        _isLoading = false;
      });
    }
  }

  int get _unreadCount => _items.where((n) => !n.isRead).length;

  Future<void> _markOneRead(BackendNotification notification) async {
    if (notification.isRead) return;
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final updated = await apiClient.markNotificationRead(
        accessToken: accessToken,
        notificationId: notification.id,
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final n in _items)
            if (n.id == updated.id) updated else n,
        ];
      });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menandai: $e')),
      );
    }
  }

  Future<void> _markAllRead() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      await apiClient.markAllNotificationsRead(accessToken: accessToken);
      _load();
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: MalvaColors.danger),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _unreadCount > 0 ? 'Notifikasi ($_unreadCount)' : 'Notifikasi'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Tandai semua',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              SoftCard(
                child: Column(
                  children: [
                    Text(_error!,
                        style: const TextStyle(
                            color: MalvaColors.danger,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              )
            else if (_items.isEmpty)
              const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Belum ada notifikasi',
                subtitle:
                    'Update screening, chat, dan reminder akan muncul di sini.',
              )
            else
              for (final item in _items) ...[
                _NotificationCard(
                  item: item,
                  onTap: () => _markOneRead(item),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final BackendNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.type) {
      'crisis_alert' => (Icons.warning_amber_rounded, MalvaColors.danger),
      'chat_message' => (Icons.chat_bubble_rounded, MalvaColors.orchid),
      'follow_up' => (Icons.mark_email_unread_rounded, MalvaColors.seed),
      'medication' => (Icons.medication_rounded, MalvaColors.mint),
      'screening' => (Icons.fact_check_rounded, MalvaColors.amber),
      _ => (Icons.notifications_rounded, MalvaColors.seed),
    };
    return SoftCard(
      onTap: item.isRead ? null : onTap,
      color: item.isRead ? null : MalvaColors.seed.withValues(alpha: 0.05),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title.isEmpty ? item.type : item.title,
                        style: TextStyle(
                          fontWeight:
                              item.isRead ? FontWeight.w700 : FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!item.isRead)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: MalvaColors.danger,
                        ),
                      ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 4),
                Text(
                  _dateLabel(item.createdAt),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime? date) {
    if (date == null) return '';
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $h:$m';
  }
}
