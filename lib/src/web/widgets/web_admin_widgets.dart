import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../web_theme.dart';

/// Kartu putih standar untuk panel dashboard admin.
class WebAdminCard extends StatelessWidget {
  const WebAdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WebSpacing.card),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: child,
    );
  }
}

/// Label status berwarna (pembayaran, kredensial, akun).
class WebStatusPill extends StatelessWidget {
  const WebStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  /// Warna otomatis untuk status pembayaran.
  factory WebStatusPill.payment(String status) {
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      'paid' => MalvaColors.mint,
      'pending' => MalvaColors.amber,
      'failed' => MalvaColors.danger,
      'refunded' => MalvaColors.orchid,
      _ => const Color(0xFF8B8194),
    };
    return WebStatusPill(
      label: _paymentLabel(normalized),
      color: color,
    );
  }

  final String label;
  final Color color;

  static String _paymentLabel(String status) => switch (status) {
        'paid' => 'Lunas',
        'pending' => 'Menunggu',
        'failed' => 'Gagal',
        'refunded' => 'Refund',
        'cancelled' => 'Dibatalkan',
        _ => status.isEmpty ? '—' : status,
      };

  @override
  Widget build(BuildContext context) {
    final dark = color == MalvaColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: dark ? const Color(0xFF8A5A00) : color,
        ),
      ),
    );
  }
}

/// Satu kolom tabel admin.
class WebAdminColumn {
  const WebAdminColumn(this.label, this.width,
      {this.align = Alignment.centerLeft});

  final String label;
  final double width;
  final Alignment align;
}

/// Tabel admin dengan header tetap dan gulir horizontal untuk layar sempit.
class WebAdminTable extends StatelessWidget {
  const WebAdminTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
    this.minWidth = 960,
    this.rowKeyBuilder,
  });

  final List<WebAdminColumn> columns;

  /// Setiap baris berisi widget dengan jumlah = [columns].
  final List<List<Widget>> rows;
  final String emptyMessage;
  final double minWidth;

  /// Opsional: kunci per baris (dipakai widget test / animasi).
  final Key? Function(int index)? rowKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final totalWidth = columns.fold<double>(
      0,
      (double sum, WebAdminColumn column) => sum + column.width,
    );
    final tableWidth = totalWidth < minWidth ? minWidth : totalWidth;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final needsScroll = constraints.maxWidth < tableWidth;
        final table = SizedBox(
          width: tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _WebTableHeader(columns: columns),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8B8194),
                    ),
                  ),
                )
              else
                ...List<Widget>.generate(rows.length, (int index) {
                  return Container(
                    key: rowKeyBuilder?.call(index),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF3EEF7)),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < columns.length; i++)
                          SizedBox(
                            width: columns[i].width - 24,
                            child: Align(
                              alignment: columns[i].align,
                              child: i < rows[index].length
                                  ? rows[index][i]
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
        if (!needsScroll) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        );
      },
    );
  }
}

class _WebTableHeader extends StatelessWidget {
  const _WebTableHeader({required this.columns});

  final List<WebAdminColumn> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F4FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Row(
        children: <Widget>[
          for (final WebAdminColumn column in columns)
            SizedBox(
              width: column.width - 24,
              child: Align(
                alignment: column.align,
                child: Text(
                  column.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF6B6377),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kotak status memuat untuk satu bagian dashboard.
class WebAdminLoading extends StatelessWidget {
  const WebAdminLoading({super.key, this.label = 'Memuat data...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: <Widget>[
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B6377)),
          ),
        ],
      ),
    );
  }
}

/// Kotak error ramah + tombol coba lagi (tidak pernah menampilkan exception
/// mentah; memakai satu sumber pesan yang sama dengan mobile).
class WebAdminError extends StatelessWidget {
  const WebAdminError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.cloud_off_rounded,
            color: MalvaColors.danger,
            size: 26,
          ),
          const SizedBox(height: 10),
          Text(
            friendlyErrorMessage(error),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MalvaColors.danger,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}

/// Dialog konfirmasi aksi (dipakai semua aksi destruktif admin).
Future<bool> showWebConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Lanjutkan',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, style: const TextStyle(height: 1.5)),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: MalvaColors.danger)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Dialog wajib alasan (3–500 karakter, sama dengan validasi server).
///
/// Mengembalikan teks alasan yang sudah di-trim, atau `null` bila dibatalkan.
Future<String?> showWebReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Simpan',
  bool destructive = false,
  int minLength = 3,
  int maxLength = 500,
}) async {
  // Nilai dikumpulkan lewat onChanged (tanpa TextEditingController) agar tidak
  // ada controller yang di-dispose saat animasi tutup dialog masih berjalan.
  var reason = '';
  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          final trimmed = reason.trim();
          final valid = trimmed.length >= minLength;
          // Dialog kustom (bukan AlertDialog) agar lebar tegas: AlertDialog
          // memakai IntrinsicWidth, dan TextField multi-baris di dalamnya
          // menghasilkan intrinsic height tak terbatas.
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox(
              width: 480,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(message, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 14),
                    // Tinggi dibatasi eksplisit: di dalam Column (main axis
                    // tanpa batas) InputDecorator multi-baris akan mengembang
                    // memenuhi tinggi tak terbatas dan memicu overflow.
                    SizedBox(
                      height: 132,
                      child: TextFormField(
                        key: const Key('web-reason-field'),
                        autofocus: true,
                        maxLength: maxLength,
                        maxLines: 3,
                        onChanged: (String value) {
                          reason = value;
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Alasan',
                          hintText:
                              'mis. verifikasi manual setelah webhook telat',
                          helperText:
                              'Minimal $minLength karakter, wajib untuk audit.',
                          errorText: trimmed.isEmpty || valid
                              ? null
                              : 'Alasan minimal $minLength karakter.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(null),
                          child: const Text('Batal'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('web-reason-confirm'),
                          style: destructive
                              ? FilledButton.styleFrom(
                                  backgroundColor: MalvaColors.danger)
                              : null,
                          onPressed: valid
                              ? () => Navigator.of(dialogContext).pop(trimmed)
                              : null,
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  return result;
}
