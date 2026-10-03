import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';

// ============================================================
// SETTINGS / PROFILE / SECURITY
// ============================================================

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.onLogout, this.session});

  final VoidCallback onLogout;
  final AuthSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          ActionTile(
            icon: Icons.security_rounded,
            title: 'Security',
            subtitle: 'Email dan password',
            color: MalvaColors.seed,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SecurityScreen(session: session)),
            ),
          ),
          const SizedBox(height: 10),
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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController(text: 'Emerie R');
  final _dob = TextEditingController(text: '01/01/2007');

  @override
  void dispose() {
    _name.dispose();
    _dob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionLabel('Name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          const SectionLabel('Date of Birth'),
          TextField(
            controller: _dob,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Date of Birth',
              hintText: 'DD/MM/YYYY',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Perubahan profil tersimpan.')),
              );
              Navigator.pop(context);
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
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
          TextField(
            controller: _currentPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password saat ini',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _newPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password baru (min 8 karakter)',
            ),
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
