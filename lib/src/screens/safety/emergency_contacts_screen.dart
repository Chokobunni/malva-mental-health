import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// EMERGENCY CONTACTS MANAGEMENT
// ============================================================

class EmergencyContactsScreen extends ConsumerStatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  ConsumerState<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState
    extends ConsumerState<EmergencyContactsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(safetyProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontak Darurat'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: safety.contacts.length >= 5
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context, ref, null),
              backgroundColor: MalvaColors.seed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(safetyProvider.notifier).load(),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MalvaColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: MalvaColors.amber.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: MalvaColors.amber),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Maksimal 5 kontak. Silent SOS otomatis mengirim pesan + GPS ke semua kontak.',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (safety.isLoading && safety.contacts.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (safety.contacts.isEmpty)
              const EmptyState(
                icon: Icons.contact_emergency_outlined,
                title: 'Belum ada kontak darurat',
                subtitle:
                    'Tambahkan orang terdekat yang bisa dihubungi saat krisis.',
              )
            else
              for (final contact in safety.contacts)
                _ContactCard(
                  contact: contact,
                  onDelete: () => _delete(context, ref, contact),
                ),
            if (safety.error != null) ...[
              const SizedBox(height: 12),
              FriendlyErrorCard(
                error: safety.error!,
                onRetry: () => ref.read(safetyProvider.notifier).load(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BackendEmergencyContact contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus kontak?'),
        content: Text(
            '${contact.contactName} (${contact.contactPhone}) akan dihapus dari daftar darurat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(MalvaColors.danger),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(safetyProvider.notifier).removeContact(contact.id);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    BackendEmergencyContact? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: _ContactForm(existing: existing),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.onDelete});

  final BackendEmergencyContact contact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
              child: Text(
                contact.contactName.isEmpty
                    ? '?'
                    : contact.contactName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: MalvaColors.seed,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.contactName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (contact.isDefault) ...[
                        const SizedBox(width: 6),
                        const StatusPill(
                          label: 'Utama',
                          color: MalvaColors.mint,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${contact.contactPhone}${contact.relationship.isEmpty ? '' : ' • ${contact.relationship}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Panggil',
              onPressed: () => _launch('tel:${contact.contactPhone}', context),
              icon: const Icon(Icons.phone_rounded, color: MalvaColors.seed),
            ),
            IconButton(
              tooltip: 'SMS',
              onPressed: () => _launch('sms:${contact.contactPhone}', context),
              icon:
                  const Icon(Icons.message_rounded, color: MalvaColors.orchid),
            ),
            IconButton(
              tooltip: 'Hapus',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: MalvaColors.danger),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String url, BuildContext context) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak dapat membuka aplikasi telepon/SMS.')),
      );
    }
  }
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({this.existing});

  final BackendEmergencyContact? existing;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _relation;
  bool _isDefault = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.contactName ?? '');
    _phone = TextEditingController(text: widget.existing?.contactPhone ?? '');
    _relation =
        TextEditingController(text: widget.existing?.relationship ?? '');
    _isDefault = widget.existing?.isDefault ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relation.dispose();
    super.dispose();
  }

  String? _validatePhone(String value) {
    final v = value.trim().replaceAll(' ', '').replaceAll('-', '');
    if (v.length < 9 || v.length > 15) {
      return 'Nomor harus 9-15 digit.';
    }
    if (!v.startsWith('0') && !v.startsWith('62')) {
      return 'Gunakan format 08xxxxxxxxxx atau 62xxxxxxxxxx.';
    }
    if (!RegExp(r'^\d+$').hasMatch(v)) {
      return 'Nomor hanya boleh berisi angka.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? 'Tambah Kontak' : 'Ubah Kontak',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama kontak',
            hintText: 'cth: Ibu',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Nomor telepon',
            hintText: 'cth: 08123456789',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _relation,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Hubungan (opsional)',
            hintText: 'cth: Ibu, Kakak, Teman',
          ),
        ),
        SwitchListTile(
          value: _isDefault,
          onChanged: (v) => setState(() => _isDefault = v),
          title: const Text('Jadikan kontak utama',
              style: TextStyle(fontWeight: FontWeight.w700)),
          activeThumbColor: MalvaColors.seed,
          contentPadding: EdgeInsets.zero,
        ),
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(
              color: MalvaColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Menyimpan...' : 'Simpan Kontak'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama kontak harus diisi.');
      return;
    }
    final phoneError = _validatePhone(phone);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(safetyProvider.notifier).addContact(
            name: name,
            phone: phone,
            relationship: _relation.text.trim(),
            isDefault: _isDefault,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kontak darurat tersimpan.')),
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
