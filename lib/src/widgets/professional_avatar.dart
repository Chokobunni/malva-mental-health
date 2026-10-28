import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

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
          child: ProfessionalPhoto(
            photoUrl: photoUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            fallback: _gradientFallback(),
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

/// True bila URL mengarah ke gambar SVG (mis. avatar DiceBear default yang
/// di-generate backend saat profesional belum unggah foto). Flutter tidak
/// bisa mendekode SVG lewat Image.network, jadi URL seperti ini wajib
/// dirender lewat flutter_svg — kalau tidak, avatar profesional selalu
/// jatuh ke fallback inisial di sisi pasien.
bool isSvgPhotoUrl(String url) {
  final path = url.toLowerCase().split('?').first;
  return path.endsWith('.svg') || path.endsWith('/svg');
}

/// Foto profil profesional dari URL jaringan.
/// - URL raster (png/jpg/webp): [Image.network] dengan fallback bila gagal.
/// - URL SVG: byte diunduh via HTTP lalu dirender [SvgPicture.memory].
/// [fallback] dipakai saat URL kosong, gambar gagal dimuat, atau masih loading.
class ProfessionalPhoto extends StatefulWidget {
  const ProfessionalPhoto({
    super.key,
    required this.photoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback = const SizedBox.shrink(),
  });

  final String photoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<ProfessionalPhoto> createState() => _ProfessionalPhotoState();
}

class _ProfessionalPhotoState extends State<ProfessionalPhoto> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (isSvgPhotoUrl(widget.photoUrl)) {
      _fetchSvg();
    }
  }

  Future<void> _fetchSvg() async {
    try {
      final res = await http
          .get(Uri.parse(widget.photoUrl))
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        setState(() => _bytes = res.bodyBytes);
      } else {
        setState(() => _failed = true);
      }
    } on Object catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photoUrl.isEmpty || _failed) return widget.fallback;

    if (isSvgPhotoUrl(widget.photoUrl)) {
      final bytes = _bytes;
      if (bytes == null) return widget.fallback;
      return SvgPicture.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      );
    }

    return Image.network(
      widget.photoUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (_, __, ___) => widget.fallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return widget.fallback;
      },
    );
  }
}
