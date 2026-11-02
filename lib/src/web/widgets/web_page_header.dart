import 'package:flutter/material.dart';

import '../../theme.dart';

/// Judul halaman web: judul besar, subjudul opsional, dan aksi di kanan.
class WebPageHeader extends StatelessWidget {
  const WebPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitleText = subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: textTheme.headlineMedium),
              if (subtitleText != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(subtitleText, style: textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 16),
          trailing!,
        ],
      ],
    );
  }
}

/// Label kecil di atas sekelompok kartu.
class WebSectionTitle extends StatelessWidget {
  const WebSectionTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: Color(0xFF8B8194),
      ),
    );
  }
}

/// Kartu aksi besar untuk beranda (ikon + judul + deskripsi + panah).
class WebActionCard extends StatefulWidget {
  const WebActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.accent = MalvaColors.seed,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color accent;

  @override
  State<WebActionCard> createState() => _WebActionCardState();
}

class _WebActionCardState extends State<WebActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.45)
                : const Color(0xFFEDE6F1),
          ),
          boxShadow: <BoxShadow>[
            if (_hovered)
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 24),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: MalvaColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF6B6377),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Text(
                        'Buka',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: widget.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: widget.accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu statistik ringkas (dipakai beranda admin).
class WebStatCard extends StatelessWidget {
  const WebStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.note,
    this.accent = MalvaColors.seed,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? note;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final noteText = note;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B6377),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: MalvaColors.ink,
            ),
          ),
          if (noteText != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              noteText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9C93A6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Halaman placeholder untuk fitur yang belum dibangun.
///
/// Sengaja bukan tautan mati: memberi tahu pengguna bahwa halaman ini memang
/// belum tersedia, bukan gagal dimuat.
class WebComingSoonPage extends StatelessWidget {
  const WebComingSoonPage({
    super.key,
    required this.title,
    this.description,
    this.onBackToHome,
  });

  final String title;
  final String? description;
  final VoidCallback? onBackToHome;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final descriptionText = description ??
        'Halaman ini sedang disiapkan dan akan tersedia pada fase berikutnya.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(title: title),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDE6F1)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: MalvaColors.seed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  size: 30,
                  color: MalvaColors.seed,
                ),
              ),
              const SizedBox(height: 18),
              Text('Segera hadir', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  descriptionText,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ),
              if (onBackToHome != null) ...<Widget>[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onBackToHome,
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Kembali ke Beranda'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
