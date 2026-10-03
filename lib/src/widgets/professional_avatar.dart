import 'package:flutter/material.dart';

import '../theme.dart';

// ============================================================
// AVATAR PROFESIONAL — gradien deterministik + inisial.
// Offline-safe (tanpa network image) sehingga selalu tampil rapi.
// ============================================================

class ProfessionalAvatar extends StatelessWidget {
  const ProfessionalAvatar({
    super.key,
    required this.displayName,
    this.radius = 30,
  });

  final String displayName;
  final double radius;

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
