import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../time/wib.dart';
import '../../../widgets/friendly_error.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Riwayat & override pembayaran (`/admin/pembayaran`).
///
/// Alur kerja yang didukung: cari/filter transaksi, lihat detail beserta event
/// gateway dan ledger refund, lalu verifikasi manual saat webhook Midtrans
/// telat atau galat. Setiap override WAJIB menyertakan alasan (3–500 karakter)
/// karena server mencatatnya di audit log.
class WebAdminPaymentsScreen extends ConsumerStatefulWidget {
  const WebAdminPaymentsScreen({super.key});

  @override
  ConsumerState<WebAdminPaymentsScreen> createState() =>
      _WebAdminPaymentsScreenState();
}

class _WebAdminPaymentsScreenState
    extends ConsumerState<WebAdminPaymentsScreen> {
  static const int _limit = 50;

  final TextEditingController _searchController = TextEditingController();
  String _status = '';
  DateTime? _from;
  DateTime? _to;
  int _offset = 0;

  AdminPaymentPage? _page;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _accessToken =>
      ref.read(authStateProvider).session?.accessToken ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiClientProvider).listAdminPayments(
            accessToken: _accessToken,
            query: _searchController.text,
            status: _status,
            from: _from == null ? '' : wibDateKeyFromPicker(_from!),
            to: _to == null ? '' : wibDateKeyFromPicker(_to!),
            limit: _limit,
            offset: _offset,
          );
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    _offset = 0;
    unawaited(_load());
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _status = '';
      _from = null;
      _to = null;
      _offset = 0;
    });
    unawaited(_load());
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = wibNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: isFrom ? 'Tanggal awal (WIB)' : 'Tanggal akhir (WIB)',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _openDetail(AdminPaymentItem item) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _WebPaymentDetailDialog(
        paymentId: item.id,
        accessToken: _accessToken,
        onChanged: () => unawaited(_load()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Pembayaran',
          subtitle: 'Verifikasi manual transaksi Midtrans, telusuri event '
              'gateway, dan catat refund. Semua aksi masuk audit log.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(child: _buildFilters(context)),
        const SizedBox(height: 16),
        if (page != null && !_loading && _error == null)
          WebAdminCard(child: _buildSummary(context, page.summary)),
        const SizedBox(height: 16),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildTable(context, page),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: <Widget>[
        SizedBox(
          width: 280,
          child: TextField(
            key: const Key('web-payments-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applyFilters(),
            decoration: const InputDecoration(
              labelText: 'Cari referensi / nama / email',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: InputDecorator(
            decoration:
                const InputDecoration(labelText: 'Status', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('web-payments-status'),
                value: _status,
                isExpanded: true,
                isDense: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: '', child: Text('Semua status')),
                  DropdownMenuItem<String>(
                      value: 'pending', child: Text('Menunggu')),
                  DropdownMenuItem<String>(value: 'paid', child: Text('Lunas')),
                  DropdownMenuItem<String>(
                      value: 'failed', child: Text('Gagal')),
                  DropdownMenuItem<String>(
                      value: 'refunded', child: Text('Refund')),
                ],
                onChanged: (String? value) =>
                    setState(() => _status = value ?? ''),
              ),
            ),
          ),
        ),
        _DateFilterButton(
          key: const Key('web-payments-from'),
          label: 'Dari',
          value: _from,
          onPick: () => unawaited(_pickDate(isFrom: true)),
          onClear: () => setState(() => _from = null),
        ),
        _DateFilterButton(
          key: const Key('web-payments-to'),
          label: 'Sampai',
          value: _to,
          onPick: () => unawaited(_pickDate(isFrom: false)),
          onClear: () => setState(() => _to = null),
        ),
        FilledButton.icon(
          key: const Key('web-payments-apply'),
          onPressed: _loading ? null : _applyFilters,
          icon: const Icon(Icons.filter_alt_outlined, size: 18),
          label: const Text('Terapkan'),
        ),
        TextButton(
          onPressed: _loading ? null : _resetFilters,
          child: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, AdminPaymentSummary summary) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _SummaryChip(
          label: 'Menunggu',
          value: '${summary.pending}',
          color: MalvaColors.amber,
        ),
        _SummaryChip(
          label: 'Lunas',
          value: '${summary.paid}',
          color: MalvaColors.mint,
        ),
        _SummaryChip(
          label: 'Gagal',
          value: '${summary.failed}',
          color: MalvaColors.danger,
        ),
        _SummaryChip(
          label: 'Refund',
          value: '${summary.refunded}',
          color: MalvaColors.orchid,
        ),
        _SummaryChip(
          label: 'Gross lunas',
          value: formatRupiah(summary.grossPaid),
          color: MalvaColors.plum,
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, AdminPaymentPage? page) {
    if (_loading) return const WebAdminLoading(label: 'Memuat transaksi...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    if (page == null) {
      return const WebAdminLoading(label: 'Memuat transaksi...');
    }
    final items = page.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WebAdminTable(
          minWidth: 1080,
          emptyMessage: 'Tidak ada transaksi pada filter ini.',
          columns: const <WebAdminColumn>[
            WebAdminColumn('REFERENSI', 190),
            WebAdminColumn('PASIEN', 200),
            WebAdminColumn('PROFESIONAL', 170),
            WebAdminColumn('NOMINAL', 130, align: Alignment.centerRight),
            WebAdminColumn('STATUS', 110),
            WebAdminColumn('DIBUAT (WIB)', 160),
            WebAdminColumn('', 100, align: Alignment.centerRight),
          ],
          rowKeyBuilder: (int index) => Key('payment-row-${items[index].id}'),
          rows: items
              .map(
                (AdminPaymentItem item) => <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        item.reference.isEmpty ? '—' : item.reference,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        item.paymentMethod.isEmpty ? '—' : item.paymentMethod,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8B8194),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        item.patientName.isEmpty ? '—' : item.patientName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        item.patientEmail,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8B8194),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    item.professionalName.isEmpty ? '—' : item.professionalName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    formatRupiah(item.grossAmount),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  WebStatusPill.payment(item.status),
                  Text(
                    formatWibDateTimeOrDash(item.createdAt),
                    style: const TextStyle(fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_openDetail(item)),
                    child: const Text('Detail'),
                  ),
                ],
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  items.isEmpty
                      ? 'Tidak ada data'
                      : 'Menampilkan ${_offset + 1}–${_offset + items.length} dari ${page.total}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B6377),
                  ),
                ),
              ),
              TextButton(
                onPressed: _offset == 0 || _loading
                    ? null
                    : () {
                        _offset = (_offset - _limit).clamp(0, 1 << 30);
                        unawaited(_load());
                      },
                child: const Text('Sebelumnya'),
              ),
              TextButton(
                onPressed: _loading || _offset + _limit >= page.total
                    ? null
                    : () {
                        _offset += _limit;
                        unawaited(_load());
                      },
                child: const Text('Berikutnya'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tombol filter tanggal (`Dari` / `Sampai`) dengan tombol hapus.
class _DateFilterButton extends StatelessWidget {
  const _DateFilterButton({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? 'Pilih tanggal' : formatWibDate(value!);
    return SizedBox(
      width: 200,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPick,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            prefixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
            suffixIcon: value == null
                ? null
                : IconButton(
                    tooltip: 'Hapus tanggal',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: onClear,
                  ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: value == null ? const Color(0xFF8B8194) : MalvaColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B6377)),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color:
                  color == MalvaColors.amber ? const Color(0xFF8A5A00) : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog detail pembayaran + aksi override.
class _WebPaymentDetailDialog extends ConsumerStatefulWidget {
  const _WebPaymentDetailDialog({
    required this.paymentId,
    required this.accessToken,
    required this.onChanged,
  });

  final String paymentId;
  final String accessToken;
  final VoidCallback onChanged;

  @override
  ConsumerState<_WebPaymentDetailDialog> createState() =>
      _WebPaymentDetailDialogState();
}

class _WebPaymentDetailDialogState
    extends ConsumerState<_WebPaymentDetailDialog> {
  AdminPaymentDetail? _detail;
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ref.read(apiClientProvider).getAdminPayment(
            accessToken: widget.accessToken,
            paymentId: widget.paymentId,
          );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Dua langkah: alasan (wajib, untuk audit) lalu konfirmasi eksplisit.
  Future<void> _override(String targetStatus) async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final payment = detail.payment;
    final label = paymentStatusLabel(targetStatus);

    final reason = await showWebReasonDialog(
      context,
      title: 'Ubah status menjadi $label',
      message: 'Transaksi ${payment.reference} sebesar '
          '${formatRupiah(payment.grossAmount)} akan diubah menjadi '
          '"$label". Alasan dicatat di audit log dan tidak dapat dihapus.',
      confirmLabel: 'Lanjutkan',
      destructive: targetStatus == 'refunded' || targetStatus == 'failed',
    );
    if (reason == null || !mounted) return;

    final confirmed = await showWebConfirmDialog(
      context,
      title: 'Konfirmasi perubahan status',
      message: 'Status ${payment.reference} akan menjadi "$label".\n\n'
          'Alasan: $reason',
      confirmLabel: 'Ya, ubah status',
      destructive: targetStatus == 'refunded' || targetStatus == 'failed',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(apiClientProvider).overrideAdminPayment(
            accessToken: widget.accessToken,
            paymentId: payment.id,
            status: targetStatus,
            reason: reason,
          );
      if (!mounted) return;
      widget.onChanged();
      await _load();
      if (!mounted) return;
      _showMessage(
        result.changed
            ? 'Status ${result.payment.reference} kini "$label".'
            : 'Status tidak berubah (sudah "$label").',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal mengubah status. ${_friendly(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object error) {
    // Satu sumber pesan ramah dengan mobile.
    return friendlyErrorMessage(error);
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const WebAdminLoading(label: 'Memuat detail...');
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WebAdminError(error: _error!, onRetry: () => unawaited(_load())),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ),
        ],
      );
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    final payment = detail.payment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                payment.reference.isEmpty
                    ? 'Detail pembayaran'
                    : payment.reference,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            WebStatusPill.payment(payment.status),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Tutup',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Dibuat ${formatWibDateTimeOrDash(payment.createdAt)} · '
          'Dibayar ${formatWibDateTimeOrDash(payment.paidAt)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _infoGrid(context, payment),
                const SizedBox(height: 18),
                const WebSectionTitle(text: 'EVENT GATEWAY'),
                const SizedBox(height: 8),
                WebAdminTable(
                  minWidth: 620,
                  emptyMessage: 'Belum ada event gateway untuk transaksi ini.',
                  columns: const <WebAdminColumn>[
                    WebAdminColumn('GATEWAY', 120),
                    WebAdminColumn('EVENT', 170),
                    WebAdminColumn('STATUS', 120),
                    WebAdminColumn('WAKTU (WIB)', 190),
                  ],
                  rows: detail.events
                      .map(
                        (AdminPaymentEvent event) => <Widget>[
                          Text(event.gateway.isEmpty ? '—' : event.gateway,
                              style: const TextStyle(fontSize: 12)),
                          Text(
                            event.eventType.isEmpty ? '—' : event.eventType,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(event.status.isEmpty ? '—' : event.status,
                              style: const TextStyle(fontSize: 12)),
                          Text(formatWibDateTimeOrDash(event.createdAt),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                const WebSectionTitle(text: 'REFUND'),
                const SizedBox(height: 8),
                WebAdminTable(
                  minWidth: 620,
                  emptyMessage: 'Belum ada refund untuk transaksi ini.',
                  columns: const <WebAdminColumn>[
                    WebAdminColumn('NOMINAL', 130,
                        align: Alignment.centerRight),
                    WebAdminColumn('JENIS', 120),
                    WebAdminColumn('STATUS', 120),
                    WebAdminColumn('ALASAN', 200),
                    WebAdminColumn('WAKTU (WIB)', 170),
                  ],
                  rows: detail.refunds
                      .map(
                        (AdminRefundItem refund) => <Widget>[
                          Text(formatRupiah(refund.amount),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          Text(refund.kind.isEmpty ? '—' : refund.kind,
                              style: const TextStyle(fontSize: 12)),
                          Text(refund.status.isEmpty ? '—' : refund.status,
                              style: const TextStyle(fontSize: 12)),
                          Text(refund.reason.isEmpty ? '—' : refund.reason,
                              style: const TextStyle(fontSize: 12)),
                          Text(formatWibDateTimeOrDash(refund.createdAt),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _actionRow(context, payment),
      ],
    );
  }

  Widget _infoGrid(BuildContext context, AdminPaymentItem payment) {
    final rows = <(String, String)>[
      ('Pasien', '${payment.patientName} · ${payment.patientEmail}'),
      ('Profesional', payment.professionalName),
      ('Jenis sesi', sessionTypeLabel(payment.sessionType)),
      ('Jadwal', '${payment.bookingDate} ${payment.slotTime}'.trim()),
      ('Metode bayar', payment.paymentMethod),
      ('Gross', formatRupiah(payment.grossAmount)),
      ('Biaya layanan', formatRupiah(payment.serviceFeeAmount)),
      ('Biaya platform', formatRupiah(payment.platformFeeAmount)),
      ('Net ke profesional', formatRupiah(payment.netAmount)),
      (
        'Status booking',
        payment.bookingStatus.isEmpty ? '—' : payment.bookingStatus
      ),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 10,
      children: rows
          .map(
            ((String, String) row) => SizedBox(
              width: 300,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8B8194),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2.trim().isEmpty ? '—' : row.$2,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _actionRow(BuildContext context, AdminPaymentItem payment) {
    final status = payment.status.toLowerCase();
    final canMarkPaid = status == 'pending' || status == 'failed';
    final canMarkFailed = status == 'pending';
    final canRefund = status == 'paid';
    return Row(
      children: <Widget>[
        if (_busy) ...<Widget>[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
        ],
        const Expanded(
          child: Text(
            'Override manual hanya untuk kasus webhook telat/galat.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
        ),
        if (canMarkFailed)
          OutlinedButton(
            key: const Key('web-payment-mark-failed'),
            onPressed: _busy ? null : () => unawaited(_override('failed')),
            child: const Text('Tandai gagal'),
          ),
        if (canMarkPaid) ...<Widget>[
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('web-payment-mark-paid'),
            onPressed: _busy ? null : () => unawaited(_override('paid')),
            child: const Text('Tandai lunas'),
          ),
        ],
        if (canRefund) ...<Widget>[
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('web-payment-refund'),
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.danger),
            onPressed: _busy ? null : () => unawaited(_override('refunded')),
            child: const Text('Refund'),
          ),
        ],
        if (!canMarkPaid && !canMarkFailed && !canRefund)
          const Text(
            'Tidak ada aksi tersedia untuk status ini.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
      ],
    );
  }
}
