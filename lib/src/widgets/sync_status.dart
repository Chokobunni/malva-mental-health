import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data/sync_provider.dart';
import '../theme.dart';

// ============================================================
// SYNC STATUS INDICATOR
// ============================================================

class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider);
    final isSyncing = ref.watch(isSyncingProvider);

    if (isSyncing) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: MalvaColors.amber,
        ),
      );
    }

    if (!isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: MalvaColors.danger,
            ),
          ),
          if (pendingCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$pendingCount',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: MalvaColors.danger,
              ),
            ),
          ],
        ],
      );
    }

    if (pendingCount > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: MalvaColors.amber,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$pendingCount',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: MalvaColors.amber,
            ),
          ),
        ],
      );
    }

    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MalvaColors.mint,
      ),
    );
  }
}

// ============================================================
// OFFLINE BANNER
// ============================================================

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    if (isOnline) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: MalvaColors.amber.withValues(alpha: 0.9),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'Offline - Data akan disinkronkan saat online',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
