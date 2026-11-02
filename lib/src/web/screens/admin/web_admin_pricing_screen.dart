import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';

import '../../../widgets/friendly_error.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Batas harga layanan yang diterima server (`maxAdminPrice` di backend).
const int kWebMaxServicePrice = 100000000;

/// Pengaturan harga profesional (`/admin/harga`).
///
/// Satu baris = satu profesional dengan tiga harga. Simpan per baris agar
/// kesalahan input tidak membatalkan perubahan baris lain.
class WebAdminPricingScreen extends ConsumerStatefulWidget {
  const WebAdminPricingScreen({super.key});

  @override
  ConsumerState<WebAdminPricingScreen> createState() =>
      _WebAdminPricingScreenState();
}

class _WebAdminPricingScreenState extends ConsumerState<WebAdminPricingScreen> {
  List<AdminPricingItem>? _items;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _accessToken =>
      ref.read(authStateProvider).session?.accessToken ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(apiClientProvider)
          .listAdminPricing(accessToken: _accessToken);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  /// Simpan satu baris. Mengembalikan `true` bila server menerima perubahan.
  Future<bool> _saveRow({
    required AdminPricingItem item,
    required int quickChatPrice,
    required int quickVideoPrice,
    required int packagePrice,
  }) async {
    final confirmed = await showWebConfirmDialog(
      context,
      title: 'Simpan harga ${item.name}',
      message: 'Chat cepat ${formatRupiah(quickChatPrice)}, '
          'video ${formatRupiah(quickVideoPrice)}, '
          'paket ${formatRupiah(packagePrice)}.\n\n'
          'Perubahan langsung berlaku untuk transaksi berikutnya.',
      confirmLabel: 'Simpan',
    );
    if (!confirmed || !mounted) return false;
    try {
      final updated = await ref.read(apiClientProvider).updateAdminPricing(
            accessToken: _accessToken,
            professionalId: item.professionalId,
            quickChatPrice: quickChatPrice,
            quickVideoPrice: quickVideoPrice,
            packagePrice: packagePrice,
          );
      if (!mounted) return false;
      setState(() {
        final current = _items;
        if (current != null) {
          final index = current.indexWhere((AdminPricingItem e) =>
              e.professionalId == updated.professionalId);
          if (index >= 0) {
            _items = <AdminPricingItem>[...current]..[index] = updated;
          }
        }
      });
      _showMessage('Harga ${updated.name} tersimpan.');
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showMessage('Gagal menyimpan harga. ${friendlyErrorMessage(error)}');
      return false;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Harga & Paket',
          subtitle: 'Atur harga chat cepat, video, dan paket per profesional. '
              'Nilai 0 berarti layanan gratis.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(context),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const WebAdminLoading(label: 'Memuat harga...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    final items = _items ?? const <AdminPricingItem>[];
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'Belum ada akun profesional.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF8B8194)),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F4FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: const Row(
                children: <Widget>[
                  _HeaderCell('PROFESIONAL', 230),
                  _HeaderCell('SPESIALISASI', 120),
                  _HeaderCell('CHAT CEPAT', 170),
                  _HeaderCell('VIDEO', 170),
                  _HeaderCell('PAKET', 170),
                  _HeaderCell('TERAKHIR DIUBAH', 160),
                  _HeaderCell('', 140),
                ],
              ),
            ),
            ...items.map(
              (AdminPricingItem item) => _PricingRow(
                key: ValueKey<String>('pricing-row-${item.professionalId}'),
                item: item,
                onSave: (int chat, int video, int package) => _saveRow(
                  item: item,
                  quickChatPrice: chat,
                  quickVideoPrice: video,
                  packagePrice: package,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, this.width);

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Color(0xFF6B6377),
        ),
      ),
    );
  }
}

/// Satu baris harga yang bisa diedit, dengan validasi lokal sebelum simpan.
class _PricingRow extends StatefulWidget {
  const _PricingRow({
    super.key,
    required this.item,
    required this.onSave,
  });

  final AdminPricingItem item;

  /// Dipanggil dengan nilai rupiah utuh (sudah tervalidasi).
  final Future<bool> Function(int quickChat, int quickVideo, int package)
      onSave;

  @override
  State<_PricingRow> createState() => _PricingRowState();
}

class _PricingRowState extends State<_PricingRow> {
  late final TextEditingController _chat;
  late final TextEditingController _video;
  late final TextEditingController _package;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _chat = TextEditingController(text: '${widget.item.quickChatPrice}');
    _video = TextEditingController(text: '${widget.item.quickVideoPrice}');
    _package = TextEditingController(text: '${widget.item.packagePrice}');
  }

  @override
  void didUpdateWidget(_PricingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Server bisa mengembalikan nilai baru setelah simpan; sinkronkan field.
    if (oldWidget.item.quickChatPrice != widget.item.quickChatPrice) {
      _chat.text = '${widget.item.quickChatPrice}';
    }
    if (oldWidget.item.quickVideoPrice != widget.item.quickVideoPrice) {
      _video.text = '${widget.item.quickVideoPrice}';
    }
    if (oldWidget.item.packagePrice != widget.item.packagePrice) {
      _package.text = '${widget.item.packagePrice}';
    }
  }

  @override
  void dispose() {
    _chat.dispose();
    _video.dispose();
    _package.dispose();
    super.dispose();
  }

  /// `null` bila valid, atau pesan error Indonesia.
  String? _validate(TextEditingController controller, String label) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return '$label wajib diisi.';
    final value = int.tryParse(raw);
    if (value == null) return '$label harus berupa angka.';
    if (value < 0) return '$label tidak boleh negatif.';
    if (value > kWebMaxServicePrice) {
      return '$label maksimal ${formatRupiah(kWebMaxServicePrice)}.';
    }
    return null;
  }

  String? get _chatError => _validate(_chat, 'Harga chat');
  String? get _videoError => _validate(_video, 'Harga video');
  String? get _packageError => _validate(_package, 'Harga paket');

  bool get _hasError =>
      _chatError != null || _videoError != null || _packageError != null;

  bool get _dirty {
    final item = widget.item;
    return int.tryParse(_chat.text.trim()) != item.quickChatPrice ||
        int.tryParse(_video.text.trim()) != item.quickVideoPrice ||
        int.tryParse(_package.text.trim()) != item.packagePrice;
  }

  Future<void> _submit() async {
    if (_saving || _hasError) return;
    setState(() => _saving = true);
    final ok = await widget.onSave(
      int.parse(_chat.text.trim()),
      int.parse(_video.text.trim()),
      int.parse(_package.text.trim()),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
  }

  @override
  Widget build(BuildContext context) {
    final chatValue = int.tryParse(_chat.text.trim());
    final videoValue = int.tryParse(_video.text.trim());
    final packageValue = int.tryParse(_package.text.trim());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3EEF7))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.item.name.isEmpty ? '—' : widget.item.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.item.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8B8194),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              widget.item.specialization.isEmpty
                  ? '—'
                  : widget.item.specialization,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          _PriceField(
            fieldKey: const Key('price-chat'),
            controller: _chat,
            errorText: _chatError,
            helper: chatValue == null ? null : formatRupiah(chatValue),
            enabled: !_saving,
            onChanged: () => setState(() {}),
          ),
          _PriceField(
            fieldKey: const Key('price-video'),
            controller: _video,
            errorText: _videoError,
            helper: videoValue == null ? null : formatRupiah(videoValue),
            enabled: !_saving,
            onChanged: () => setState(() {}),
          ),
          _PriceField(
            fieldKey: const Key('price-package'),
            controller: _package,
            errorText: _packageError,
            helper: packageValue == null ? null : formatRupiah(packageValue),
            enabled: !_saving,
            onChanged: () => setState(() {}),
          ),
          SizedBox(
            width: 160,
            child: Text(
              widget.item.updatedAt == null
                  ? '—'
                  : formatWibDateTimeOrDash(widget.item.updatedAt),
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          SizedBox(
            width: 140,
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('price-save'),
                onPressed: _saving || _hasError || !_dirty ? null : _submit,
                // Sengaja teks statis (bukan spinner): dialog konfirmasi
                // berjalan selama status "menyimpan", dan indikator berputar
                // akan terus menjadwalkan frame.
                child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.fieldKey,
    required this.controller,
    required this.errorText,
    required this.helper,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String? errorText;
  final String? helper;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            // Sengaja mengizinkan tanda minus agar pengguna melihat pesan
            // "tidak boleh negatif" (bukan angka yang hilang diam-diam).
            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
          ],
          onChanged: (_) => onChanged(),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            isDense: true,
            prefixText: 'Rp',
            errorText: errorText,
            helperText: helper,
            helperStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }
}
