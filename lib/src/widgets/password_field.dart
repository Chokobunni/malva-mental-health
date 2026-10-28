import 'package:flutter/material.dart';

// ============================================================
// PASSWORD FIELD — kolom password bersama dengan tombol intip
// (show/hide) untuk SELURUH aplikasi.
//
// Sebelumnya setiap layar menulis `TextField(obscureText: true)` sendiri
// sehingga pengguna tidak bisa memeriksa apa yang diketik. Widget ini
// menyatukan perilaku tersebut: teks awalnya tersembunyi, lalu bisa
// ditampilkan lewat ikon mata di sisi kanan.
//
// Catatan implementasi:
// - Status tampil/sembunyi disimpan LOKAL di State (setState) dan TIDAK
//   pernah menyentuh controller, sehingga teks yang diketik pengguna
//   tidak hilang saat ikon ditekan.
// - Gaya mengikuti `InputDecorationTheme` global; widget ini tidak
//   mengubah tema aplikasi.
// - `obscureText` hanya boleh muncul di berkas ini (aturan proyek).
// ============================================================

/// Kolom password dengan tombol intip (tampilkan / sembunyikan).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.prefixIcon,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
    this.autofillHints,
    this.errorText,
    this.helperText,
  });

  /// Controller teks password. Tidak dimodifikasi oleh widget ini.
  final TextEditingController controller;

  /// Label yang tampil di atas/ dalam kolom.
  final String labelText;

  /// Placeholder saat kolom kosong.
  final String? hintText;

  /// Ikon di sisi kiri (mis. `Icons.lock_rounded`).
  final Widget? prefixIcon;

  /// Aksi keyboard (next / done) agar alur antar-kolom tetap sama.
  final TextInputAction? textInputAction;

  /// Dipanggil saat pengguna menekan tombol aksi di keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Menonaktifkan kolom (mis. saat proses kirim berlangsung).
  final bool enabled;

  /// Petunjuk autofill untuk pengelola password sistem.
  final Iterable<String>? autofillHints;

  /// Pesan galat inline (ditampilkan di bawah kolom, bukan lewat SnackBar).
  final String? errorText;

  /// Teks bantuan di bawah kolom.
  final String? helperText;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  /// Teks password selalu tersembunyi saat kolom pertama kali tampil.
  bool _obscured = true;

  void _toggleVisibility() {
    setState(() => _obscured = !_obscured);
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = _obscured ? 'Tampilkan password' : 'Sembunyikan password';
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      enabled: widget.enabled,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: Semantics(
          button: true,
          label: tooltip,
          child: IconButton(
            tooltip: tooltip,
            onPressed: widget.enabled ? _toggleVisibility : null,
            icon: Icon(
              _obscured
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
          ),
        ),
      ),
    );
  }
}
