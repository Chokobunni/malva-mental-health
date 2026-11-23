import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';
import '../theme.dart';
import '../widgets/account_avatar.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/password_field.dart';
import 'google_account_screen.dart';

// ============================================================
// SETTINGS / PROFILE / SECURITY
// ============================================================

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.onLogout, this.session});

  final VoidCallback onLogout;
  final AuthSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = session ?? ref.watch(currentSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionLabel('Support & About'),
          ActionTile(
            icon: Icons.help_outline_rounded,
            title: 'Help & Support',
            subtitle: 'Pusat bantuan dan FAQ',
            onTap: () => _soon(context),
          ),
          const SizedBox(height: 10),
          ActionTile(
            icon: Icons.description_outlined,
            title: 'Terms and Policies',
            subtitle: 'Syarat, ketentuan, dan privasi',
            onTap: () => _soon(context),
          ),
          const SizedBox(height: 10),
          ActionTile(
            icon: Icons.report_problem_outlined,
            title: 'Report a problem',
            subtitle: 'Laporkan bug atau masalah',
            color: MalvaColors.amber,
            onTap: () => _soon(context),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Account'),
          if (active?.role != UserRole.patient) ...[
            ActionTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Atur notifikasi aplikasi',
              color: MalvaColors.orchid,
              onTap: () => _soon(context),
            ),
            const SizedBox(height: 10),
            ActionTile(
              icon: Icons.edit_rounded,
              title: 'Edit profile',
              subtitle: 'Nama dan tanggal lahir',
              color: MalvaColors.mint,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
            const SizedBox(height: 10),
          ],
          ActionTile(
            icon: Icons.security_rounded,
            title: 'Security',
            subtitle: 'Email dan password',
            color: MalvaColors.seed,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SecurityScreen(session: active)),
            ),
          ),
          const SizedBox(height: 10),
          // Kelola akun Google (pasien & profesional) — hubungkan Gmail,
          // dan untuk profesional aktifkan Google Meet.
          if (active != null) ...[
            _GoogleAccountTile(session: active),
            const SizedBox(height: 10),
          ],
          ActionTile(
            icon: Icons.logout_rounded,
            title: 'Log out',
            subtitle: 'Keluar dari akun',
            color: MalvaColors.danger,
            onTap: onLogout,
          ),
          const SizedBox(height: 22),
          const SectionLabel('Actions'),
          const Text(
            'By continuing, you agree to our Terms & Privacy Policy',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Segera hadir.')),
    );
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _dob = TextEditingController();
  int _generation = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _avatarDraft;

  @override
  void initState() {
    super.initState();
    _loadProfile(ref.read(currentSessionProvider));
  }

  bool _ownsRequest(AuthSession session, int generation) =>
      mounted &&
      generation == _generation &&
      ref.read(currentSessionProvider)?.backendUserId ==
          session.backendUserId &&
      ref.read(currentSessionProvider)?.identifier == session.identifier;

  Future<void> _loadProfile(AuthSession? session) async {
    final generation = ++_generation;
    _name.text = session?.displayName ?? '';
    _dob.clear();
    _avatarDraft = null;
    _error = null;
    _saving = false;
    _loading = true;
    final token = session?.accessToken;
    if (session == null || token == null || token.isEmpty) {
      _loading = false;
      return;
    }
    try {
      final profile = await ref
          .read(apiClientProvider)
          .fetchUserProfile(accessToken: token);
      if (!_ownsRequest(session, generation)) return;
      if (profile.id != session.backendUserId) {
        throw const AuthFailure('Profil tidak sesuai dengan akun aktif.');
      }
      _name.text = profile.displayName;
      final birthDate = profile.birthDateTime;
      _dob.text = birthDate == null ? '' : formatWibDate(birthDate);
    } on Object catch (error) {
      if (_ownsRequest(session, generation)) {
        _error = friendlyErrorMessage(error);
      }
    } finally {
      if (_ownsRequest(session, generation)) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (session == null || token == null || token.isEmpty) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama harus diisi.');
      return;
    }
    final rawDob = _dob.text.trim();
    String? dob;
    if (rawDob.isNotEmpty) {
      final parts = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(rawDob);
      final date = parts == null
          ? null
          : parseWibStored('${parts[3]}-${parts[2]}-${parts[1]}');
      if (date == null ||
          formatWibDate(date) != rawDob ||
          date.isAfter(wibNow())) {
        setState(
            () => _error = 'Tanggal lahir tidak valid. Gunakan DD/MM/YYYY.');
        return;
      }
      dob = wibDateKey(date);
    }
    final generation = _generation;
    final draft = _avatarDraft;
    final avatarStore = ref.read(secureStoreProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await ref.read(apiClientProvider).updateMe(
          accessToken: token, displayName: name, dateOfBirth: dob ?? '');
      if (!_ownsRequest(session, generation)) return;
      if (profile.id != session.backendUserId) {
        throw const AuthFailure('Profil tidak sesuai dengan akun aktif.');
      }
      if (draft != null) {
        await avatarStore.write(profileAvatarKey(profile.id), draft);
        if (!_ownsRequest(session, generation)) return;
        ref.invalidate(patientAvatarProvider(profile.id));
      }
      final current = ref.read(currentSessionProvider)!;
      final updated = AuthSession(
          role: current.role,
          identifier: current.identifier,
          displayName: profile.displayName,
          backendUserId: current.backendUserId,
          backendSynced: current.backendSynced,
          accessToken: current.accessToken,
          refreshToken: current.refreshToken);
      ref.read(authStateProvider.notifier).setSession(updated);
      final store = ref.read(malvaStoreProvider.notifier);
      if (ref.read(malvaStoreProvider).patient.id == current.backendUserId) {
        store.setPatientIdentity(name: profile.displayName);
      }
      await store.persistSession(updated);
      if (!_ownsRequest(session, generation)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perubahan profil tersimpan.')),
      );
      Navigator.pop(context);
    } on Object catch (error) {
      if (_ownsRequest(session, generation))
        setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (_ownsRequest(session, generation)) setState(() => _saving = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final raw = _dob.text.split('/');
    final current = raw.length == 3
        ? parseWibStored('${raw[2]}-${raw[1]}-${raw[0]}')
        : null;
    final now = wibNow();
    final generation = _generation;
    final result = await showDatePicker(
      context: context,
      initialDate:
          current != null && current.year >= 1900 && !current.isAfter(now)
              ? DateTime(current.year, current.month, current.day)
              : DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (mounted && generation == _generation && result != null) {
      _dob.text =
          formatWibDate(wibFromParts(result.year, result.month, result.day));
    }
  }

  Future<void> _chooseAvatar(AuthSession session) async {
    final generation = _generation;
    final current = session.backendUserId;
    if (current == null) return;
    final initial =
        _avatarDraft ?? ref.read(patientAvatarProvider(current)).valueOrNull;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _AvatarPicker(session: session, initial: initial),
    );
    if (chosen != null && _ownsRequest(session, generation)) {
      setState(() => _avatarDraft = chosen);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    ref.listen<AuthSession?>(currentSessionProvider, (previous, next) {
      if (previous?.backendUserId != next?.backendUserId ||
          previous?.identifier != next?.identifier) {
        _loadProfile(next);
      }
    });
    final patient = session?.role == UserRole.patient;
    final disabled = _loading || _saving;
    return Scaffold(
      backgroundColor: carePageColor,
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (patient) ...[
            const SizedBox(height: 10),
            Center(
                child: AccountAvatar(
                    session: session, avatar: _avatarDraft, size: 112)),
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                onPressed: disabled || session?.backendUserId == null
                    ? null
                    : () => _chooseAvatar(session!),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Change avatar'),
              ),
            ),
            const SizedBox(height: 28),
          ],
          SoftCard(
            color: Colors.white,
            outline: careCardBorder,
            radius: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Name'),
                TextField(
                  controller: _name,
                  enabled: !disabled,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 18),
                const SectionLabel('Date of Birth'),
                TextField(
                  controller: _dob,
                  enabled: !disabled,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: 'Date of Birth',
                    hintText: 'DD/MM/YYYY',
                    suffixIcon: IconButton(
                      tooltip: 'Pilih tanggal lahir',
                      onPressed: disabled ? null : _pickBirthDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: MalvaColors.danger)),
              ),
            FilledButton(
              onPressed: disabled || session?.accessToken?.isNotEmpty != true
                  ? null
                  : _saveProfile,
              child: Text(_saving ? 'Menyimpan...' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatefulWidget {
  const _AvatarPicker({required this.session, this.initial});

  final AuthSession session;
  final String? initial;

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  late String selected = widget.initial ?? profileAvatarAssets.first;
  bool picking = false;
  String? error;

  Future<void> _upload() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 78,
      );
      if (file == null || !mounted) return;
      if (await file.length() > 192 * 1024) {
        if (mounted) setState(() => error = 'Ukuran foto masih terlalu besar.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => selected = base64Encode(bytes));
    } on Object catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      ...profileAvatarAssets,
      if (!profileAvatarAssets.contains(selected)) selected,
    ];
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Change avatar'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (i, option) in options.indexed)
                    Semantics(
                      selected: selected == option,
                      button: true,
                      label: 'Avatar ${i + 1}',
                      child: InkWell(
                        onTap: picking
                            ? null
                            : () => setState(() => selected = option),
                        customBorder: const CircleBorder(),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected == option
                                  ? MalvaColors.seed
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: AccountAvatar(
                              session: widget.session,
                              avatar: option,
                              size: 52),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: picking ? null : _upload,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Upload photo'),
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: MalvaColors.danger)),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: picking ? null : () => Navigator.pop(context, selected),
          child: const Text('Use avatar'),
        ),
      ],
    );
  }
}

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key, this.session});

  final AuthSession? session;

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _email = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final email = widget.session?.identifier ?? '';
    if (email.contains('@')) _email.text = email;
  }

  @override
  void dispose() {
    _email.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasBackend = widget.session?.accessToken?.isNotEmpty == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionLabel('Email'),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'melpeters@gmail.com',
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Ubah Password'),
          PasswordField(
            controller: _currentPassword,
            labelText: 'Password saat ini',
          ),
          const SizedBox(height: 10),
          PasswordField(
            controller: _newPassword,
            labelText: 'Password baru (min 8 karakter)',
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: (!hasBackend || _isSaving) ? null : _changePassword,
            child: Text(_isSaving ? 'Menyimpan...' : 'Save changes'),
          ),
          if (!hasBackend) ...[
            const SizedBox(height: 8),
            const Text(
              'Login backend diperlukan untuk mengubah password.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final apiClient = ref.read(apiClientProvider);
    final accessToken = widget.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;
    if (_newPassword.text.length < 8) {
      setState(() => _error = 'Password baru minimal 8 karakter.');
      return;
    }
    if (_currentPassword.text.isEmpty) {
      setState(() => _error = 'Isi password saat ini.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await apiClient.changePassword(
        accessToken: accessToken,
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password diubah. Sesi lain telah dinonaktifkan.'),
        ),
      );
      Navigator.pop(context);
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// Tile "Akun Google" untuk kedua role. Subtitle dinamis: email Gmail bila
/// sudah tertaut, atau ajakan menghubungkan bila belum. Membuka
/// [GoogleAccountScreen] dan menyegarkan status setelah layar ditutup.
class _GoogleAccountTile extends ConsumerStatefulWidget {
  const _GoogleAccountTile({required this.session});

  final AuthSession session;

  @override
  ConsumerState<_GoogleAccountTile> createState() => _GoogleAccountTileState();
}

class _GoogleAccountTileState extends ConsumerState<_GoogleAccountTile> {
  BackendGoogleIdentity? _identity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  Future<void> _loadStatus() async {
    final accessToken = widget.session.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      final identity = await ref
          .read(apiClientProvider)
          .fetchGoogleIdentity(accessToken: accessToken);
      if (!mounted) return;
      setState(() => _identity = identity);
    } on Object {
      // Best-effort: subtitle jatuh ke default bila status gagal dimuat.
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    final linked = identity?.linked ?? false;
    final String subtitle;
    if (linked) {
      subtitle = (identity?.email.isNotEmpty ?? false)
          ? identity!.email
          : 'Gmail tertaut';
    } else {
      subtitle = 'Hubungkan Gmail Anda';
    }
    return ActionTile(
      icon: Icons.alternate_email_rounded,
      title: 'Akun Google',
      subtitle: subtitle,
      color: MalvaColors.seed,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoogleAccountScreen(
              session: widget.session,
              apiClient: ref.read(apiClientProvider),
              showMeet: widget.session.role == UserRole.professional,
            ),
          ),
        );
        // Segarkan subtitle setelah kembali dari layar Akun Google.
        if (mounted) await _loadStatus();
      },
    );
  }
}
