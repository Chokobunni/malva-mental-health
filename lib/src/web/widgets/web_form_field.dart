import 'package:flutter/material.dart';

import '../../theme.dart';

// ============================================================
// KEBIJAKAN PASSWORD WEB — CERMIN DARI SERVER
// ============================================================
//
// Sumber kebenaran: `backend/internal/security/password_policy.go`
// (ValidatePassword + IndonesianMessage). Aturan di bawah WAJIB identik agar
// pengguna tidak pernah melihat "password ditolak" dari server setelah UI
// menyatakan password valid. Bila kebijakan server berubah, ubah juga berkas
// ini (dan sebaliknya).
//
// Perbedaan yang disengaja: checklist ditampilkan SEBELUM submit (bukan hanya
// error setelah submit) supaya pengguna tahu syaratnya sejak awal.

/// Daftar password yang dianggap terlalu umum (sama persis dengan server).
const List<String> kWebCommonPasswords = <String>[
  'password',
  '12345678',
  'qwerty123',
  'letmein',
  'welcome1',
  'admin123',
  'password1',
  '123456789',
  'abc123456',
  'malva1234',
];

/// Satu baris checklist syarat password.
class WebPasswordRequirement {
  const WebPasswordRequirement(this.label, this.satisfied);

  /// Label Bahasa Indonesia yang ditampilkan ke pengguna.
  final String label;

  /// True bila syarat ini sudah terpenuhi.
  final bool satisfied;
}

/// Mengambil bagian lokal email (sebelum `@`), huruf kecil.
String _emailLocalPart(String email) {
  final trimmed = email.trim().toLowerCase();
  final at = trimmed.indexOf('@');
  return at < 0 ? trimmed : trimmed.substring(0, at);
}

/// True bila [password] memuat bagian lokal email (minimal 3 karakter).
///
/// Ambang 3 karakter sama dengan server: bagian lokal yang lebih pendek dari
/// 3 karakter diabaikan agar tidak melarang password yang wajar.
bool _containsEmailLocalPart(String password, String email) {
  final local = _emailLocalPart(email);
  if (local.length < 3) return false;
  return password.toLowerCase().contains(local);
}

/// Mengevaluasi seluruh syarat password (untuk checklist langsung).
///
/// [email] dipakai untuk syarat "tidak memuat email Anda"; bila kosong syarat
/// itu dianggap terpenuhi (tidak ada yang bisa dilanggar).
List<WebPasswordRequirement> evaluateWebPassword(
  String password, {
  String email = '',
}) {
  return <WebPasswordRequirement>[
    WebPasswordRequirement('Minimal 8 karakter', password.length >= 8),
    WebPasswordRequirement('Maksimal 128 karakter', password.length <= 128),
    WebPasswordRequirement(
      'Mengandung huruf besar (A-Z)',
      RegExp(r'[A-Z]').hasMatch(password),
    ),
    WebPasswordRequirement(
      'Mengandung huruf kecil (a-z)',
      RegExp(r'[a-z]').hasMatch(password),
    ),
    WebPasswordRequirement(
      'Mengandung angka (0-9)',
      RegExp(r'[0-9]').hasMatch(password),
    ),
    WebPasswordRequirement(
      'Mengandung simbol (mis. #?!@\$)',
      RegExp(r'[^A-Za-z0-9]').hasMatch(password),
    ),
    WebPasswordRequirement(
      'Tidak memuat alamat email Anda',
      !_containsEmailLocalPart(password, email),
    ),
    WebPasswordRequirement(
      'Bukan password yang umum dipakai',
      !kWebCommonPasswords.contains(password),
    ),
  ];
}

/// Pesan error pertama yang melanggar kebijakan password, atau `null` bila
/// password sudah memenuhi seluruh syarat.
///
/// Urutan pemeriksaan **sama dengan server** (lihat `ValidatePassword`) supaya
/// pesan yang tampil identik dengan yang akan dikembalikan backend.
String? webPasswordError(String password, {String email = ''}) {
  if (password.length < 8) {
    return 'Password minimal 8 karakter.';
  }
  if (password.length > 128) {
    return 'Password maksimal 128 karakter.';
  }
  if (kWebCommonPasswords.contains(password)) {
    return 'Password terlalu umum, gunakan kombinasi yang lebih unik.';
  }
  if (_containsEmailLocalPart(password, email)) {
    return 'Password tidak boleh mengandung alamat email Anda.';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 huruf besar (A-Z).';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 huruf kecil (a-z).';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 angka (0-9).';
  }
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 simbol (mis. #?!@\$).';
  }
  return null;
}

/// Kolom isian teks bergaya web.
///
/// Pembungkus tipis di atas [TextFormField] agar seluruh formulir web punya
/// padding, ikon, dan perilaku Enter yang seragam.
class WebFormField extends StatelessWidget {
  const WebFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.enabled = true,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Kolom password dengan tombol lihat/sembunyikan.
class WebPasswordField extends StatefulWidget {
  const WebPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.enabled = true,
    this.errorText,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool enabled;
  final String? errorText;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<WebPasswordField> createState() => _WebPasswordFieldState();
}

class _WebPasswordFieldState extends State<WebPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return WebFormField(
      controller: widget.controller,
      label: widget.label,
      icon: widget.icon ?? Icons.lock_outline_rounded,
      enabled: widget.enabled,
      errorText: widget.errorText,
      obscureText: _obscured,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: IconButton(
        tooltip: _obscured ? 'Tampilkan password' : 'Sembunyikan password',
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}

/// Checklist syarat password yang diperbarui langsung saat pengguna mengetik.
class WebPasswordChecklist extends StatelessWidget {
  const WebPasswordChecklist({
    super.key,
    required this.password,
    this.email = '',
  });

  final String password;

  /// Email yang sedang diisi; dipakai untuk syarat "tidak memuat email".
  final String email;

  @override
  Widget build(BuildContext context) {
    final requirements = evaluateWebPassword(password, email: email);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEADFF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Syarat password',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: requirements
                .map((WebPasswordRequirement requirement) =>
                    _ChecklistItem(requirement: requirement))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.requirement});

  final WebPasswordRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final satisfied = requirement.satisfied;
    final color = satisfied ? MalvaColors.mint : const Color(0xFF9C93A6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          satisfied
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          requirement.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: satisfied ? FontWeight.w700 : FontWeight.w500,
            color:
                satisfied ? const Color(0xFF1F7A66) : const Color(0xFF6B6377),
          ),
        ),
      ],
    );
  }
}
