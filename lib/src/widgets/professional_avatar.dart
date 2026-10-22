import 'package:flutter/material.dart';

import '../theme.dart';

// ============================================================
// AVATAR PROFESIONAL — foto dari URL bila tersedia, fallback ke
// gradien deterministik + inisial. Foto diambil dari photo_intro_url
// yang disimpan di professional_credentials (DiceBear atau URL lain).
// ============================================================

class ProfessionalAvatar extends StatelessWidget {
  const ProfessionalAvatar({
    super.key,
    required this.displayName,
    this.radius = 30,
    this.photoUrl,
  });

  final String displayName;
  final double radius;

  /// URL foto profil profesional. Bila kosong/null, pakai gradien + inisial.
  final String? photoUrl;

  static const _gradients = [
    [MalvaColors.plum, MalvaColors.orchid],
    [MalvaColors.seed, MalvaColors.orchid],
    [MalvaColors.mint, MalvaColors.seed],
    [MalvaColors.orchid, MalvaColors.pink],
    [MalvaColors.amber, MalvaColors.orchid],
  ];

  String get _initials {
    final cleaned = displayName
        .replaceAll(RegExp(r'^(dr\.?|dokter)\s+', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Jika ada URL foto, tampilkan gambar jaringan dengan fallback ke gradien.
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Image.network(
            photoUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradientFallback(),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return _gradientFallback();
            },
          ),
        ),
      );
    }
    return _gradientFallback();
  }

  Widget _gradientFallback() {
    final hash = displayName.hashCode.abs();
    final gradient = _gradients[hash % _gradients.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: radius * 0.7,
          ),
        ),
      ),
    );
  }
}
