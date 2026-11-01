import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../providers/auth_providers.dart';
import '../services/google_auth_service.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

/// Kartu pengelolaan tautan akun Google untuk pasien maupun profesional.
///
/// Tanggung jawab:
/// - Menampilkan status tautan (`GET /v1/auth/google-identity`).
/// - Menautkan Gmail (`POST /v1/auth/bind-google`).
/// - Untuk profesional dengan [showMeet]: mengaktifkan Google Meet dengan
///   meminta authorization code Calendar lalu menukarnya ke server.
///
/// [idTokenProvider] dan [calendarCodeProvider] dapat di-inject agar bisa
/// diuji tanpa memanggil GoogleSignIn sungguhan. Default-nya memakai
/// [GoogleAuthService].
class GoogleAccountCard extends ConsumerStatefulWidget {
  const GoogleAccountCard({
    super.key,
    required this.session,
    this.showMeet = false,
    this.idTokenProvider,
    this.calendarCodeProvider,
    this.calendarCodeProviderFresh,
  });

  final AuthSession session;

  /// true untuk profesional: tampilkan bagian Google Meet.
  final bool showMeet;

  /// Sumber ID token Google (default [GoogleAuthService.signInIdToken]).
  final Future<String?> Function()? idTokenProvider;

  /// Sumber authorization code Calendar (default
  /// [GoogleAuthService.signInWithCalendarScope]).
  final Future<String?> Function()? calendarCodeProvider;

  /// Sumber authorization code Calendar untuk percobaan ULANG (memaksa
  /// otorisasi baru). Default memakai
  /// [GoogleAuthService.signInWithCalendarScope] dengan `freshAuthorization:
  /// true`. Disuntikkan agar bisa diuji tanpa memanggil GoogleSignIn asli.
  final Future<String?> Function()? calendarCodeProviderFresh;

  @override
  ConsumerState<GoogleAccountCard> createState() => _GoogleAccountCardState();
}

class _GoogleAccountCardState extends ConsumerState<GoogleAccountCard> {
  bool _loading = true;
  String? _loadError;
  BackendGoogleIdentity? _identity;

  // Proses sedang berjalan (bind / aktifkan Meet). Tombol dinonaktifkan.
  bool _busy = false;

  // Status Google Meet (hanya profesional).
  bool _meetLoading = false;
  bool _serverConfigured = true;
  bool _calendarConnected = false;

  /// true bila percobaan aktivasi Meet sebelumnya gagal. Selama true, percobaan
  /// berikutnya WAJIB meminta otorisasi baru (freshAuthorization) agar Play
  /// Services tidak mengembalikan otorisasi lama yang kodenya sudah terpakai.
  bool _meetRetry = false;

  /// Alasan mesin dari `GET /v1/professionals/{id}/meet-status`:
  /// `ready`, `not_linked`, `no_calendar_scope`, `token_expired`,
  /// `token_hampir_kedaluwarsa`, atau `server_not_configured`. Kosong bila
  /// endpoint tidak tersedia — UI lalu jatuh ke `GET /v1/google/status`.
  String _meetReason = '';

  /// Umur grant izin Google (hari) — 0 bila tidak ada token.
  int _refreshTokenAgeDays = 0;

  /// Sisa hari sebelum izin Google dianggap kedaluwarsa — -1 bila tidak
  /// diketahui / peringatan perpanjangan dinonaktifkan server.
  int _refreshTokenExpiresInDays = -1;

  Future<String?> Function() get _idTokenProvider =>
      widget.idTokenProvider ?? GoogleAuthService.signInIdToken;

  Future<String?> Function() get _calendarCodeProvider =>
      widget.calendarCodeProvider ?? GoogleAuthService.signInWithCalendarScope;

  /// Sumber authorization code untuk percobaan ULANG. Default memaksa
  /// otorisasi baru lewat `freshAuthorization: true`.
  Future<String?> Function() get _calendarCodeProviderFresh =>
      widget.calendarCodeProviderFresh ??
      () => GoogleAuthService.signInWithCalendarScope(freshAuthorization: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = widget.session.accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Sesi tidak valid. Silakan login ulang.';
      });
      return;
    }
    try {
      final identity = await ref
          .read(apiClientProvider)
          .fetchGoogleIdentity(accessToken: token);
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _loading = false;
        _loadError = null;
      });
      if (widget.showMeet && widget.session.role == UserRole.professional) {
        await _loadMeetStatus();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error is MalvaApiException
            ? error.message
            : 'Gagal memuat status Akun Google. Coba lagi nanti.';
      });
    }
  }

  Future<void> _loadMeetStatus() async {
    final token = widget.session.accessToken;
    if (token == null || token.isEmpty) return;
    if (mounted) setState(() => _meetLoading = true);
    // Sumber utama: status Meet milik profesional ini. `reason` memberi tahu
    // APA yang kurang (belum tertaut / belum ada izin / token kedaluwarsa /
    // server belum dikonfigurasi) sehingga pesan bisa spesifik.
    var reason = '';
    var ageDays = 0;
    var expiresInDays = -1;
    try {
      final professionalId = widget.session.backendUserId ?? '';
      if (professionalId.isNotEmpty) {
        final status = await ref.read(apiClientProvider).professionalMeetStatus(
            accessToken: token, professionalId: professionalId);
        reason = status.reason;
        ageDays = status.refreshTokenAgeDays;
        expiresInDays = status.refreshTokenExpiresInDays;
      }
    } on Object {
      // Endpoint status opsional: jatuh ke GET /v1/google/status di bawah.
    }
    try {
      final status =
          await ref.read(apiClientProvider).googleStatus(accessToken: token);
      if (!mounted) return;
      setState(() {
        _meetReason = reason;
        _refreshTokenAgeDays = ageDays;
        _refreshTokenExpiresInDays = expiresInDays;
        _serverConfigured = reason.isEmpty
            ? status.serverConfigured
            : reason != 'server_not_configured';
        _calendarConnected =
            reason.isEmpty ? status.connected : reason == 'ready';
        _meetLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _meetLoading = false);
    }
  }

  Future<void> _bind() async {
    if (_busy) return;
    final token = widget.session.accessToken;
    if (token == null || token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final idToken = await _idTokenProvider();
      // Pengguna membatalkan dialog Google — bukan error.
      if (idToken == null || idToken.isEmpty) return;
      if (!mounted) return;
      final identity = await ref
          .read(apiClientProvider)
          .bindGoogleIdentity(accessToken: token, idToken: idToken);
      if (!mounted) return;
      setState(() => _identity = identity);
      _showSnack('Gmail berhasil dihubungkan.');
      if (widget.showMeet && widget.session.role == UserRole.professional) {
        await _loadMeetStatus();
      }
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      _showSnack(_bindErrorMessage(error));
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableMeet() async {
    if (_busy) return;
    final token = widget.session.accessToken;
    if (token == null || token.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Percobaan ulang (setelah satu kegagalan) memaksa otorisasi baru agar
      // Google tidak mengembalikan otorisasi lama yang kodenya sudah terpakai.
      final code = _meetRetry
          ? await _calendarCodeProviderFresh()
          : await _calendarCodeProvider();
      if (code == null || code.isEmpty) return;
      if (!mounted) return;
      await ref.read(apiClientProvider).exchangeGoogleToken(
            accessToken: token,
            authorizationCode: code,
          );
      if (!mounted) return;
      _meetRetry = false;
      await _loadMeetStatus();
      if (!mounted) return;
      _showSnack('Google Meet diaktifkan.');
    } on Object catch (error) {
      if (!mounted) return;
      // Satu kegagalan sudah cukup: percobaan berikutnya harus meminta
      // otorisasi baru, bukan mengulang kode yang mungkin sudah terpakai.
      _meetRetry = true;
      // Pesan `access_denied` panjang dan berisi langkah perbaikan: tampilkan
      // utuh di dialog (bukan snackbar yang memotong) dengan aksi "Coba lagi".
      final message =
          error is MalvaApiException ? error.message : error.toString();
      await _showMeetErrorDialog(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dialog kegagalan aktivasi Meet. Pesan ditampilkan APA ADANYA (tidak
  /// dipotong `toString()`) — termasuk kode Google mentah bila ada — dengan
  /// aksi "Coba lagi" (ulang alur otorisasi), "Cabut akses Google" (buka
  /// halaman izin Google), dan "Tutup".
  ///
  /// Untuk kegagalan `access_denied`/`Test users`, pesan diperkaya dengan
  /// Gmail tertaut + instruksi tepat menambahkan akun sebagai Test user OAuth
  /// consent screen (penyebab paling umum 403 saat aplikasi masih mode Testing).
  Future<void> _showMeetErrorDialog(String message) async {
    final displayMessage = _augmentMeetErrorMessage(message);
    final action = await showDialog<_MeetErrorAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Google Calendar gagal diaktifkan'),
        content: SingleChildScrollView(child: Text(displayMessage)),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_MeetErrorAction.revoke),
            child: const Text('Cabut akses Google'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_MeetErrorAction.close),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_MeetErrorAction.retry),
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _MeetErrorAction.retry:
        await _enableMeet();
      case _MeetErrorAction.revoke:
        await _openGooglePermissions();
      case _MeetErrorAction.close:
      case null:
        break;
    }
  }

  /// Menambahkan baris bantuan khusus untuk kegagalan `access_denied` /
  /// `Test users` (Google menolak karena Gmail belum terdaftar sebagai Test
  /// user pada OAuth consent screen). Pesan untuk kegagalan LAIN tidak diubah.
  String _augmentMeetErrorMessage(String message) {
    final lower = message.toLowerCase();
    final isAccessDenied = lower.contains('access_denied') ||
        lower.contains('test users') ||
        lower.contains('test user');
    if (!isAccessDenied) return message;

    final email = _identity?.email ?? '';
    final gmail = email.isEmpty ? 'Gmail tertaut Anda' : email;
    return '$message\n\n'
        'Gmail yang tertaut: $gmail\n'
        'Minta admin menambahkan $gmail ke OAuth consent screen → Audience → '
        'Test users (project malva-7084e), lalu tekan Coba lagi.';
  }

  /// Membuka halaman izin Google agar pengguna bisa mencabut akses Malva lalu
  /// menautkan ulang dengan bersih — menghindari `invalid_grant` berulang.
  Future<void> _openGooglePermissions() async {
    final uri = Uri.parse('https://myaccount.google.com/permissions');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } on Object {
      // Abaikan: pengguna tetap bisa membuka tautan ini secara manual.
    }
  }

  /// Melepas tautan Gmail. Menampilkan dialog konfirmasi (dengan field password
  /// akun OPSIONAL) lebih dulu. Bila akun ber-password → kirim `current_password`;
  /// bila dikosongkan (akun Google-only) server membalas `perlu_password`, lalu
  /// tampilkan dialog kedua untuk menetapkan password baru.
  Future<void> _unbind() async {
    if (_busy) return;
    final token = widget.session.accessToken;
    if (token == null || token.isEmpty) return;
    final currentPassword = await _confirmUnbind();
    // null = dibatalkan; string kosong = lanjut tanpa password akun.
    if (currentPassword == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final identity = await ref.read(apiClientProvider).unbindGoogleIdentity(
            accessToken: token,
            currentPassword: currentPassword,
          );
      if (!mounted) return;
      _applyUnlinked(identity);
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'perlu_password') {
        // Akun Google-only belum punya password terpakai — minta password
        // baru agar akun tidak mati setelah Gmail dilepas.
        final newPassword = await _askNewPassword();
        if (newPassword == null || newPassword.isEmpty || !mounted) return;
        await _unbindWithNewPassword(token, newPassword);
        return;
      }
      _showSnack(_unbindErrorMessage(error));
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dialog konfirmasi "Lepas Gmail?" dengan field password akun opsional.
  /// Mengembalikan: null bila dibatalkan; selain itu password akun (boleh
  /// kosong) yang akan dikirim sebagai `current_password`.
  Future<String?> _confirmUnbind() {
    var password = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lepas Gmail?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Setelah dilepas, Anda tidak bisa masuk dengan Google ini dan '
              'Google Meet (bila aktif) akan nonaktif. Email & password akun '
              'tetap bisa dipakai.',
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              onChanged: (v) => password = v,
              decoration: const InputDecoration(
                labelText: 'Password akun (opsional)',
                helperText: 'Kosongkan bila Anda selalu masuk dengan Google.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(password),
            child: const Text('Lepas'),
          ),
        ],
      ),
    );
  }

  /// Unbind dengan menyertakan password baru (jalur akun Google-only).
  Future<void> _unbindWithNewPassword(String token, String newPassword) async {
    try {
      final identity = await ref.read(apiClientProvider).unbindGoogleIdentity(
            accessToken: token,
            newPassword: newPassword,
          );
      if (!mounted) return;
      _applyUnlinked(identity);
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      _showSnack(_unbindErrorMessage(error));
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    }
  }

  /// Terapkan hasil unbind: perbarui kartu, segarkan Meet, beri snackbar.
  void _applyUnlinked(BackendGoogleIdentity identity) {
    setState(() => _identity = identity);
    if (widget.showMeet && widget.session.role == UserRole.professional) {
      _loadMeetStatus();
    }
    _showSnack('Gmail berhasil dilepas.');
  }

  /// Dialog penetapan password baru (minimal 8 karakter). Mengembalikan
  /// password baru atau null bila dibatalkan.
  Future<String?> _askNewPassword() async {
    var value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tetapkan password baru'),
        content: TextField(
          obscureText: true,
          onChanged: (v) => value = v,
          decoration: const InputDecoration(
            labelText: 'Password baru',
            helperText: 'Minimal 8 karakter.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().length < 8) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Simpan & Lepas'),
          ),
        ],
      ),
    );
    return result;
  }

  /// Memetakan kode mesin server ke pesan Indonesia yang actionable.
  String _bindErrorMessage(MalvaApiException error) {
    switch (error.code) {
      case 'google_sudah_tertaut':
        return 'Gmail ini sudah terhubung ke akun Malva lain. '
            'Satu Gmail hanya boleh untuk satu akun.';
      case 'email_sudah_dipakai':
        return 'Email Gmail ini sudah dipakai akun Malva lain. '
            'Masuk ke akun tersebut lalu hubungkan Gmail dari sana.';
      case 'akun_sudah_taut_google_lain':
        return 'Akun ini sudah terhubung ke Gmail lain. '
            'Lepas Gmail tersebut dulu untuk menggantinya.';
      default:
        return error.message;
    }
  }

  /// Memetakan kode mesin endpoint unbind ke pesan Indonesia.
  String _unbindErrorMessage(MalvaApiException error) {
    switch (error.code) {
      case 'perlu_password':
        return 'Tetapkan password baru dulu agar akun tetap bisa dipakai '
            'setelah Gmail dilepas.';
      case 'password_salah':
        return 'Password saat ini salah.';
      case 'google_belum_tertaut':
        return 'Akun ini belum terhubung ke Gmail.';
      default:
        return error.message;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SoftCard(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Memuat status Akun Google...')),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return SoftCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: MalvaColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(_loadError!)),
          ],
        ),
      );
    }

    final identity = _identity;
    final linked = identity?.linked ?? false;
    final isProfessional = widget.session.role == UserRole.professional;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0x1F1B5E20),
                child: Icon(Icons.alternate_email_rounded,
                    color: MalvaColors.seed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  linked ? 'Gmail tertaut' : 'Hubungkan Gmail',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (linked)
                const StatusPill(label: 'Terhubung', color: MalvaColors.mint),
            ],
          ),
          const SizedBox(height: 12),
          if (linked)
            ..._linkedContent(context, identity!)
          else
            ..._unlinkedContent(isProfessional),
          if (isProfessional && widget.showMeet) ...[
            const Divider(height: 28),
            ..._meetContent(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _unlinkedContent(bool isProfessional) {
    final explanation = isProfessional
        ? 'Hubungkan Gmail untuk mengaktifkan Google Meet. '
            'Data STR/SIP tidak berubah.'
        : 'Masuk lebih cepat dengan Google. '
            'Email & password lama tetap bisa dipakai.';
    return [
      Text(
        explanation,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 6),
      Text(
        'Menghubungkan Gmail TIDAK mengubah email login akun Anda — email & '
        'password yang sekarang tetap dipakai untuk masuk.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _bind,
        icon: _busy
            ? const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.link_rounded),
        label: Text(_busy ? 'Menghubungkan...' : 'Hubungkan Gmail'),
      ),
      const SizedBox(height: 10),
      Text(
        "Penting: jangan menekan 'Login Google' sebelum Gmail dihubungkan di "
        'sini — itu akan membuat akun Malva baru.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.black54),
      ),
    ];
  }

  List<Widget> _linkedContent(
      BuildContext context, BackendGoogleIdentity identity) {
    final dateLabel = _formatDate(identity.linkedAt);
    return [
      Text(
        identity.email.isEmpty ? 'Email tidak tersedia' : identity.email,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      if (dateLabel.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'Terhubung sejak $dateLabel',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.black54),
        ),
      ],
      const SizedBox(height: 10),
      Text(
        'Gmail ini tidak bisa dipakai akun Malva lain. '
        'Satu Gmail hanya untuk satu akun.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 6),
      Text(
        'Melepas Gmail TIDAK menghapus akun Anda. Email & password login '
        'tetap bisa dipakai untuk masuk seperti biasa.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _unbind,
        icon: const Icon(Icons.link_off_rounded),
        label: const Text('Lepas Gmail'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
      ),
    ];
  }

  /// Isi bagian Google Meet. Tiga keadaan dibedakan tegas:
  ///   (a) siap → "Google Meet aktif";
  ///   (b) Gmail tertaut tetapi izin Calendar belum ada / kedaluwarsa →
  ///       penjelasan sesuai `reason` + tombol "Hubungkan Google Calendar";
  ///   (c) server belum dikonfigurasi → pesan admin, tanpa tombol.
  List<Widget> _meetContent(BuildContext context) {
    if (_meetLoading) {
      return const [
        Row(
          children: [
            SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Expanded(child: Text('Memeriksa status Google Meet...')),
          ],
        ),
      ];
    }
    if (!_serverConfigured) {
      return [
        Text(
          'Admin belum mengaktifkan konfigurasi Google, sehingga Google Meet '
          'belum bisa dipakai. Hubungi admin bila perlu.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: MalvaColors.amber),
        ),
      ];
    }
    if (_calendarConnected) {
      return const [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: MalvaColors.mint),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Google Meet aktif',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ];
    }
    // (b) Gmail tertaut, izin Calendar belum ada atau perlu diperbarui.
    final expiring = _meetReason == 'token_hampir_kedaluwarsa';
    final explanation = switch (_meetReason) {
      'token_hampir_kedaluwarsa' =>
        'Izin Google Calendar akan berakhir ${_expiringPhrase()} karena '
            'aplikasi masih dalam mode Testing. Perbarui sekarang agar link '
            'Meet sesi video tetap dibuat otomatis.',
      'token_expired' =>
        'Izin Google Calendar kedaluwarsa (token tidak lagi berlaku). '
            'Hubungkan ulang agar link Meet bisa dibuat otomatis. '
            'Sesi pasien tetap terjadwal; link dibuat setelah ini aktif.',
      'no_calendar_scope' =>
        'Gmail sudah tertaut, tetapi izin Google Calendar belum diberikan. '
            'Hubungkan Google Calendar agar link Meet dibuat otomatis untuk '
            'sesi video.',
      'not_linked' =>
        'Hubungkan Gmail di atas lebih dulu, lalu aktifkan Google Calendar.',
      _ => 'Aktifkan Google Meet agar sesi video otomatis membuat tautan Meet. '
          'Selama belum aktif, sesi video pasien tetap terjadwal dengan '
          'status "menunggu link".',
    };
    // Perpanjangan = consent BARU: paksa fresh authorization (lewat
    // _renewPermission -> _meetRetry) agar Google benar-benar menerbitkan
    // refresh token baru, bukan memakai otorisasi lama yang masih tersimpan.
    final onPressed =
        _busy ? null : (expiring ? _renewPermission : _enableMeet);
    final buttonLabel = _busy
        ? 'Memproses...'
        : (expiring ? 'Perbarui izin sekarang' : 'Hubungkan Google Calendar');
    return [
      Text(
        explanation,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: onPressed,
        icon: _busy
            ? const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(expiring ? Icons.refresh_rounded : Icons.videocam_rounded),
        label: Text(buttonLabel),
      ),
    ];
  }

  /// Frasa sisa waktu izin untuk teks "akan berakhir ...". Memakai sisa hari
  /// dari server bila tersedia; bila tidak, jatuh ke umur grant.
  String _expiringPhrase() {
    final days = _refreshTokenExpiresInDays;
    if (days >= 0) {
      return 'dalam $days hari';
    }
    if (_refreshTokenAgeDays > 0) {
      return 'dalam waktu dekat (sudah $_refreshTokenAgeDays hari)';
    }
    return 'dalam waktu dekat';
  }

  /// Perpanjang izin Google Calendar. Menandai `_meetRetry = true` supaya
  /// [_enableMeet] memakai otorisasi BARU (fresh consent), lalu menjalankan
  /// alur aktivasi Meet yang sudah ada.
  Future<void> _renewPermission() async {
    _meetRetry = true;
    await _enableMeet();
  }

  /// Format tanggal ringkas Indonesia: `dd MMM yyyy` (mis. 05 Okt 2026).
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final day = local.day.toString().padLeft(2, '0');
    return '$day ${months[local.month - 1]} ${local.year}';
  }
}

/// Aksi yang dipilih pengguna pada dialog kegagalan aktivasi Google Meet.
enum _MeetErrorAction { retry, revoke, close }
