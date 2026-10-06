import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';
import 'doctor_form_screen.dart';

/// Panel admin: kelola pengguna, dokter, dan verifikasi kredensial.
/// Hanya bisa dibuka dengan sesi role admin (dijaga juga di server).
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key, this.apiClient, this.session});

  final MalvaApiClient? apiClient;
  final AuthSession? session;

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  String _userQuery = '';

  List<AdminUser> _users = [];
  List<BackendDoctorSearchResult> _doctors = [];
  List<BackendProfessionalCredential> _pending = [];
  String _doctorFilter = '';

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String get _token =>
      widget.session?.accessToken ??
      ref.read(currentSessionProvider)?.accessToken ??
      '';
  String get _selfId =>
      widget.session?.backendUserId ??
      ref.read(currentSessionProvider)?.backendUserId ??
      '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _api.listAdminUsers(accessToken: _token);
      // Admin melihat SEMUA dokter (termasuk pending & nonaktif).
      final doctors = await _api.listAdminDoctors(accessToken: _token);
      final pending = await _api.listPendingCredentials(accessToken: _token);
      if (!mounted) return;
      setState(() {
        _users = users;
        _doctors = doctors;
        _pending = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is MalvaApiException
            ? e.message
            : 'Gagal memuat data admin. Periksa koneksi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Admin'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Pengguna', icon: Icon(Icons.people_rounded)),
            const Tab(
                text: 'Dokter', icon: Icon(Icons.medical_services_rounded)),
            Tab(
              icon: const Icon(Icons.verified_rounded),
              text:
                  'Verifikasi${_pending.isEmpty ? '' : ' (${_pending.length})'}',
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          style: compactFilledButtonStyle,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _UsersTab(
                        users: _users,
                        query: _userQuery,
                        selfId: _selfId,
                        onQuery: (v) => setState(() => _userQuery = v),
                        onEdit: _editUser,
                        onDelete: _deleteUser,
                      ),
                      _DoctorsTab(
                        doctors: _doctors,
                        filter: _doctorFilter,
                        onFilter: (v) => setState(() => _doctorFilter = v),
                        onEdit: _editDoctor,
                        onAdd: () => _editDoctor(null),
                      ),
                      _VerifyTab(
                        pending: _pending,
                        onApprove: (c) => _verify(c, 'approve'),
                        onReject: (c) => _askRejectReason(c),
                      ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _editUser(AdminUser user) async {
    final nameCtl = TextEditingController(text: user.displayName);
    String role = user.role;
    bool disabled = user.disabled;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kelola ${user.email}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Nama tampilan'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    ['patient', 'professional', 'admin'].contains(role)
                        ? role
                        : 'patient',
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'patient', child: Text('Pasien')),
                  DropdownMenuItem(
                      value: 'professional', child: Text('Profesional')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setSheet(() => role = v ?? role),
              ),
              SwitchListTile(
                title: const Text('Nonaktifkan akun'),
                subtitle: const Text('Akun nonaktif tidak bisa login.'),
                value: disabled,
                onChanged: (v) => setSheet(() => disabled = v),
              ),
              if (user.isGoogleLinked)
                const Text('🔗 Login Google tertaut',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: compactFilledButtonStyle,
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
    nameCtl.dispose();
    if (saved != true) return;
    try {
      await _api.updateAdminUser(
        accessToken: _token,
        userId: user.id,
        displayName: nameCtl.text,
        role: role,
        disabled: disabled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengguna diperbarui.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(e is MalvaApiException ? e.message : 'Gagal menyimpan.')),
      );
    }
  }

  Future<void> _deleteUser(AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan akun?'),
        content: Text(
            '${user.email} tidak akan bisa login lagi. Riwayat klinis tetap tersimpan untuk audit.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.danger),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteAdminUser(accessToken: _token, userId: user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akun dinonaktifkan.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                e is MalvaApiException ? e.message : 'Gagal menonaktifkan.')),
      );
    }
  }

  Future<void> _editDoctor(BackendDoctorSearchResult? doctor) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorFormScreen(
          apiClient: _api,
          accessToken: _token,
          userId: doctor?.userId,
          displayName: doctor?.displayName,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _verify(BackendProfessionalCredential cred, String action,
      [String reason = '']) async {
    try {
      await _api.verifyCredential(
        accessToken: _token,
        credentialId: cred.id,
        action: action,
        rejectionReason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(action == 'approve'
                ? 'Dokter disetujui & tampil di direktori.'
                : 'Pengajuan ditolak.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                e is MalvaApiException ? e.message : 'Gagal memverifikasi.')),
      );
    }
  }

  Future<void> _askRejectReason(BackendProfessionalCredential cred) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak pengajuan?'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
              labelText: 'Alasan penolakan', hintText: 'Cth: STR tidak valid'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.danger),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (ok == true) _verify(cred, 'reject', ctl.text);
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({
    required this.users,
    required this.query,
    required this.selfId,
    required this.onQuery,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AdminUser> users;
  final String query;
  final String selfId;
  final ValueChanged<String> onQuery;
  final ValueChanged<AdminUser> onEdit;
  final ValueChanged<AdminUser> onDelete;

  @override
  Widget build(BuildContext context) {
    final filtered = users
        .where((u) =>
            query.isEmpty ||
            u.email.toLowerCase().contains(query.toLowerCase()) ||
            u.displayName.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Cari email / nama',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: onQuery,
        ),
        const SizedBox(height: 8),
        Text('${filtered.length} akun',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final user in filtered)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: user.disabled
                    ? Colors.grey.shade300
                    : MalvaColors.seed.withValues(alpha: 0.15),
                child: Icon(
                  user.role == 'admin'
                      ? Icons.admin_panel_settings_rounded
                      : user.role == 'professional'
                          ? Icons.medical_services_rounded
                          : Icons.person_rounded,
                  color: user.disabled ? Colors.grey : MalvaColors.seed,
                ),
              ),
              title: Text(user.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.email),
                  Row(
                    children: [
                      _RoleChip(role: user.role),
                      if (user.isGoogleLinked) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.link_rounded,
                            size: 14, color: Colors.black54),
                        const Text('Google', style: TextStyle(fontSize: 11)),
                      ],
                      if (user.disabled) ...[
                        const SizedBox(width: 6),
                        const Text('NONAKTIF',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: MalvaColors.danger)),
                      ],
                    ],
                  ),
                ],
              ),
              trailing: user.id == selfId
                  ? const Text('(Anda)',
                      style: TextStyle(fontSize: 12, color: Colors.black54))
                  : PopupMenuButton<String>(
                      onSelected: (v) =>
                          v == 'edit' ? onEdit(user) : onDelete(user),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Kelola')),
                        PopupMenuItem(
                            value: 'delete', child: Text('Nonaktifkan')),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'admin' => MalvaColors.danger,
      'professional' => MalvaColors.mint,
      _ => MalvaColors.seed,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(role,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _DoctorsTab extends StatelessWidget {
  const _DoctorsTab({
    required this.doctors,
    required this.filter,
    required this.onFilter,
    required this.onEdit,
    required this.onAdd,
  });

  final List<BackendDoctorSearchResult> doctors;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<BackendDoctorSearchResult> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final filtered = filter.isEmpty
        ? doctors
        : doctors.where((d) => d.specialization == filter).toList();
    // Filter spesialisasi dibuat dinamis dari data yang ada di database.
    final specializations = doctors
        .map((d) => d.specialization)
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Dokter'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in <String>['', ...specializations])
                ChoiceChip(
                  label: Text(f.isEmpty ? 'Semua' : f),
                  selected: filter == f,
                  onSelected: (_) => onFilter(f),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${filtered.length} dokter',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final d in filtered)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: MalvaColors.mint.withValues(alpha: 0.15),
                  child: const Icon(Icons.medical_services_rounded,
                      color: MalvaColors.mint),
                ),
                title: Text(d.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${d.specialization} • ${d.hospitalName}\nRp${d.priceFrom} • ⭐ ${d.helpfulnessCount} terbantu'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Colors.black26),
                onTap: () => onEdit(d),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _VerifyTab extends StatelessWidget {
  const _VerifyTab({
    required this.pending,
    required this.onApprove,
    required this.onReject,
  });

  final List<BackendProfessionalCredential> pending;
  final ValueChanged<BackendProfessionalCredential> onApprove;
  final ValueChanged<BackendProfessionalCredential> onReject;

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tidak ada pengajuan kredensial menunggu.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final cred in pending)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${cred.specialization} • ${cred.hospitalName}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      'STR: ${cred.strNumber}\nSIPP: ${cred.sippNumber}\n${cred.bio}'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => onReject(cred),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: MalvaColors.danger),
                          child: const Text('Tolak'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onApprove(cred),
                          style: compactFilledButtonStyle,
                          child: const Text('Setujui'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
