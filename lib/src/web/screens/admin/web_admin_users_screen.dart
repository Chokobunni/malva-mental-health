import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../widgets/friendly_error.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_form_field.dart';
import '../../widgets/web_page_header.dart';

/// Manajemen akun (`/admin/pengguna`).
///
/// Aksi tersedia: ban/unban, ubah peran, reset password (dengan checklist
/// kebijakan server), dan cabut semua sesi. Semua aksi destruktif memakai
/// dialog konfirmasi; reset password & ubah peran tercatat di audit log server.
class WebAdminUsersScreen extends ConsumerStatefulWidget {
  const WebAdminUsersScreen({super.key});

  @override
  ConsumerState<WebAdminUsersScreen> createState() =>
      _WebAdminUsersScreenState();
}

class _WebAdminUsersScreenState extends ConsumerState<WebAdminUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _role = '';
  String _status = '';
  List<AdminUser>? _users;
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
      final users = await ref.read(apiClientProvider).listAdminUsers(
            accessToken: _accessToken,
            query: _searchController.text,
            role: _role,
            status: _status,
          );
      if (!mounted) return;
      setState(() {
        _users = users;
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

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleDisabled(AdminUser user) async {
    final willDisable = !user.disabled;
    final confirmed = await showWebConfirmDialog(
      context,
      title: willDisable ? 'Nonaktifkan akun' : 'Aktifkan kembali akun',
      message: willDisable
          ? 'Akun ${user.email} tidak akan bisa masuk sampai diaktifkan '
              'kembali. Sesi yang sedang berjalan tidak otomatis dicabut — '
              'gunakan "Cabut sesi" bila perlu.'
          : 'Akun ${user.email} akan bisa masuk kembali.',
      confirmLabel: willDisable ? 'Nonaktifkan' : 'Aktifkan',
      destructive: willDisable,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).updateAdminUser(
            accessToken: _accessToken,
            userId: user.id,
            disabled: willDisable,
          );
      if (!mounted) return;
      _showMessage(willDisable
          ? 'Akun ${user.email} dinonaktifkan.'
          : 'Akun ${user.email} diaktifkan kembali.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage(
          'Gagal mengubah status akun. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _revokeSessions(AdminUser user) async {
    final confirmed = await showWebConfirmDialog(
      context,
      title: 'Cabut semua sesi',
      message: 'Semua sesi aktif ${user.email} akan dicabut. Pengguna harus '
          'masuk ulang di semua perangkat.',
      confirmLabel: 'Cabut sesi',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final revoked = await ref.read(apiClientProvider).revokeAdminUserSessions(
            accessToken: _accessToken,
            userId: user.id,
          );
      if (!mounted) return;
      _showMessage('$revoked sesi ${user.email} dicabut.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal mencabut sesi. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _changeRole(AdminUser user) async {
    final role = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _ChangeRoleDialog(user: user),
    );
    if (role == null || role == user.role || !mounted) return;
    final confirmed = await showWebConfirmDialog(
      context,
      title: 'Ubah peran akun',
      message: 'Peran ${user.email} akan diubah dari '
          '"${userRoleLabel(user.role)}" menjadi "${userRoleLabel(role)}". '
          'Perubahan hak akses berlaku segera.',
      confirmLabel: 'Ubah peran',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).updateAdminUser(
            accessToken: _accessToken,
            userId: user.id,
            role: role,
          );
      if (!mounted) return;
      _showMessage('Peran ${user.email} kini ${userRoleLabel(role)}.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal mengubah peran. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _resetPassword(AdminUser user) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _ResetPasswordDialog(
        user: user,
        accessToken: _accessToken,
      ),
    );
    if (done == true && mounted) {
      _showMessage('Password ${user.email} berhasil direset dan semua '
          'sesinya dicabut.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Pengguna',
          subtitle: 'Kelola akses akun pasien, profesional, dan admin. '
              'Tindakan di sini tercatat di audit log.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(child: _buildFilters()),
        const SizedBox(height: 16),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: <Widget>[
        SizedBox(
          width: 280,
          child: TextField(
            key: const Key('web-users-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_load()),
            decoration: const InputDecoration(
              labelText: 'Cari nama / email',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 170,
          child: InputDecorator(
            decoration:
                const InputDecoration(labelText: 'Peran', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('web-users-role'),
                value: _role,
                isExpanded: true,
                isDense: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: '', child: Text('Semua peran')),
                  DropdownMenuItem<String>(
                      value: 'patient', child: Text('Pasien')),
                  DropdownMenuItem<String>(
                      value: 'professional', child: Text('Profesional')),
                  DropdownMenuItem<String>(
                      value: 'admin', child: Text('Admin')),
                ],
                onChanged: (String? value) =>
                    setState(() => _role = value ?? ''),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 170,
          child: InputDecorator(
            decoration:
                const InputDecoration(labelText: 'Status', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('web-users-status'),
                value: _status,
                isExpanded: true,
                isDense: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: '', child: Text('Semua status')),
                  DropdownMenuItem<String>(
                      value: 'active', child: Text('Aktif')),
                  DropdownMenuItem<String>(
                      value: 'disabled', child: Text('Nonaktif')),
                ],
                onChanged: (String? value) =>
                    setState(() => _status = value ?? ''),
              ),
            ),
          ),
        ),
        FilledButton.icon(
          key: const Key('web-users-apply'),
          onPressed: _loading ? null : () => unawaited(_load()),
          icon: const Icon(Icons.filter_alt_outlined, size: 18),
          label: const Text('Terapkan'),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : () {
                  _searchController.clear();
                  setState(() {
                    _role = '';
                    _status = '';
                  });
                  unawaited(_load());
                },
          child: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const WebAdminLoading(label: 'Memuat pengguna...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    final users = _users ?? const <AdminUser>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WebAdminTable(
          minWidth: 1180,
          emptyMessage: 'Tidak ada pengguna pada filter ini.',
          columns: const <WebAdminColumn>[
            WebAdminColumn('NAMA', 200),
            WebAdminColumn('EMAIL', 230),
            WebAdminColumn('PERAN', 120),
            WebAdminColumn('STATUS', 110),
            WebAdminColumn('AKSI', 520, align: Alignment.centerRight),
          ],
          rowKeyBuilder: (int index) => Key('user-row-${users[index].id}'),
          rows: users
              .map(
                (AdminUser user) => <Widget>[
                  Text(
                    user.displayName.isEmpty ? '—' : user.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    user.email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    userRoleLabel(user.role),
                    style: const TextStyle(fontSize: 12),
                  ),
                  WebStatusPill(
                    label: user.disabled ? 'Nonaktif' : 'Aktif',
                    color:
                        user.disabled ? MalvaColors.danger : MalvaColors.mint,
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => unawaited(_toggleDisabled(user)),
                        child: Text(user.disabled ? 'Aktifkan' : 'Nonaktifkan'),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_changeRole(user)),
                        child: const Text('Ubah peran'),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_resetPassword(user)),
                        child: const Text('Reset password'),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_revokeSessions(user)),
                        child: const Text('Cabut sesi'),
                      ),
                    ],
                  ),
                ],
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${users.length} akun ditampilkan (maksimal 200 per permintaan).',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
          ),
        ),
      ],
    );
  }
}

/// Dialog ubah peran: hanya mengembalikan peran yang dipilih.
class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({required this.user});

  final AdminUser user;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late String _role = widget.user.role;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ubah peran',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.user.email),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('web-user-role-select'),
              initialValue: _role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Peran baru'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                    value: 'patient', child: Text('Pasien')),
                DropdownMenuItem<String>(
                    value: 'professional', child: Text('Profesional')),
                DropdownMenuItem<String>(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (String? value) =>
                  setState(() => _role = value ?? _role),
            ),
            const SizedBox(height: 10),
            const Text(
              'Peran menentukan hak akses. Pastikan perubahan ini disetujui.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('web-user-role-confirm'),
          onPressed: () => Navigator.of(context).pop(_role),
          child: const Text('Pilih'),
        ),
      ],
    );
  }
}

/// Dialog reset password dengan checklist kebijakan server.
class _ResetPasswordDialog extends ConsumerStatefulWidget {
  const _ResetPasswordDialog({
    required this.user,
    required this.accessToken,
  });

  final AdminUser user;
  final String accessToken;

  @override
  ConsumerState<_ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final policyError =
        webPasswordError(_password.text, email: widget.user.email);
    if (policyError != null) {
      setState(() => _error = policyError);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Konfirmasi password tidak sama.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).resetAdminUserPassword(
            accessToken: widget.accessToken,
            userId: widget.user.id,
            newPassword: _password.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Reset password',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Password baru untuk ${widget.user.email}. Semua sesi aktif '
                'pengguna akan dicabut setelah password diganti.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              WebPasswordField(
                key: const Key('web-reset-password'),
                controller: _password,
                label: 'Password baru',
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              WebPasswordChecklist(
                password: _password.text,
                email: widget.user.email,
              ),
              const SizedBox(height: 12),
              WebPasswordField(
                key: const Key('web-reset-confirm'),
                controller: _confirm,
                label: 'Konfirmasi password',
                icon: Icons.lock_reset_outlined,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => unawaited(_submit()),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  key: const Key('web-reset-error'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: MalvaColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: MalvaColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('web-reset-submit'),
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Reset password'),
        ),
      ],
    );
  }
}
