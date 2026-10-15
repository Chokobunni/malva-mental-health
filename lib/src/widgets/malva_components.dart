import 'package:flutter/material.dart';

import '../theme.dart';

class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [MalvaColors.plum, MalvaColors.orchid, MalvaColors.pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            leading ??
                const Icon(Icons.local_florist_rounded,
                    color: Colors.white, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.action, this.icon, this.accent});

  final String text;
  final Widget? action;

  /// Ikon opsional di kiri label. Bila `null`, tampilan persis seperti
  /// sebelumnya sehingga puluhan pemakaian lama tidak berubah.
  final IconData? icon;

  /// Warna ikon + batang aksen. Default [MalvaColors.seed].
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? MalvaColors.seed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: MalvaColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
    this.accent,
    this.tone,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  /// Garis aksen 4px di sisi kiri kartu. `null` (default) = tidak ada garis,
  /// tampilan kartu persis seperti sebelumnya.
  final Color? accent;

  /// Warna latar kartu. `null` (default) = tetap memakai warna tema.
  /// Dipakai lewat [color] yang menang bila keduanya diisi.
  final Color? tone;

  /// Radius sudut kartu. Default 18 = nilai tema saat ini.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final radiusBorder = BorderRadius.circular(radius);

    // Padding isi kartu selalu diterapkan; garis aksen dibungkus paling luar
    // (di dalam Card) agar menempel di tepi kiri kartu, bukan di dalam padding.
    Widget body = Padding(padding: padding, child: child);
    if (accent != null) {
      // BoxDecoration memberi padding sebesar lebar border ke anaknya,
      // jadi tidak ada teks yang tertimpa garis aksen.
      body = Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent!, width: 4)),
        ),
        child: body,
      );
    }

    final card = Card(
      color: color ?? tone,
      // Hanya perlu memotong saat ada aksen agar garis mengikuti sudut
      // membulat; tanpa aksen tetap Clip.none supaya tampilan lama identik.
      clipBehavior: accent != null ? Clip.antiAlias : Clip.none,
      shape: RoundedRectangleBorder(borderRadius: radiusBorder),
      child: body,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: radiusBorder,
      onTap: onTap,
      child: card,
    );
  }
}

/// Avatar bulat berisi inisial nama.
///
/// Menghindari `CircleAvatar` ikon generik: tiap orang punya huruf yang
/// berbeda, dan warnanya stabil untuk nama yang sama sehingga kartu
/// daftar orang langsung terbaca sebagai entitas, bukan ikon seragam.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    this.radius = 18,
    this.color,
    this.fontSize,
  });

  /// Nama sumber inisial. Kosong/whitespace → `?`.
  final String name;

  /// Jari-jari lingkaran avatar.
  final double radius;

  /// Warna aksen eksplisit. `null` = dipilih deterministik dari [name].
  final Color? color;

  /// Ukuran huruf inisial. `null` = dihitung dari [radius].
  final double? fontSize;

  /// Palet tetap: urutan tidak boleh diubah agar warna tetap stabil.
  static const List<Color> _palette = <Color>[
    MalvaColors.seed,
    MalvaColors.orchid,
    MalvaColors.plum,
    MalvaColors.mint,
    MalvaColors.amber,
    MalvaColors.pink,
  ];

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  /// Warna deterministik dari nama. Sengaja TIDAK memakai `String.hashCode`
  /// karena nilainya tidak dijamin stabil antar-run; jumlah `codeUnits`
  /// selalu memberi hasil yang sama untuk nama yang sama.
  Color get _resolvedColor {
    if (color != null) return color!;
    var sum = 0;
    for (final unit in name.codeUnits) {
      sum += unit;
    }
    return _palette[sum % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final tint = _resolvedColor;
    return CircleAvatar(
      radius: radius,
      backgroundColor: tint.withValues(alpha: 0.16),
      child: Text(
        _initial,
        style: TextStyle(
          color: tint,
          fontWeight: FontWeight.w900,
          fontSize: fontSize ?? radius * 0.8,
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = MalvaColors.seed,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = MalvaColors.seed,
    this.maxSubtitleLines,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  /// Batas baris subtitle (null = tanpa batas).
  final int? maxSubtitleLines;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: maxSubtitleLines,
                  overflow:
                      maxSubtitleLines != null ? TextOverflow.ellipsis : null,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class ProgressStrip extends StatelessWidget {
  const ProgressStrip({
    super.key,
    required this.value,
    this.color = MalvaColors.seed,
  });

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0).toDouble(),
        minHeight: 9,
        color: color,
        backgroundColor: Colors.black.withValues(alpha: 0.12),
      ),
    );
  }
}

/// Style FilledButton ringkas untuk Row / dialog actions.
/// Theme global memakai minimumSize tak-hingga (full-width) yang akan
/// melahap seluruh lebar Row dan menjepit teks lain — jangan dipakai
/// di dalam Row tanpa style ini.
final ButtonStyle compactFilledButtonStyle = FilledButton.styleFrom(
  minimumSize: Size.zero,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
);

/// Kartu yang bisa dilipat (expand/collapse): header selalu terlihat dan
/// bisa di-tap untuk membuka/menutup, sedangkan isi detail disembunyikan
/// secara default. Dipakai untuk daftar screening & jawaban worksheet agar
/// kartu tidak menumpuk memperlihatkan semua detail sekaligus.
class CollapsibleCard extends StatefulWidget {
  const CollapsibleCard({
    super.key,
    required this.header,
    required this.child,
    this.body,
    this.initiallyExpanded = false,
    this.color,
    this.padding = const EdgeInsets.all(16),
    this.semanticLabel,
    this.accent,
    this.tone,
  });

  /// Header ringkas yang selalu terlihat dan menjadi area tap.
  final Widget header;

  /// Isi detail yang hanya muncul saat kartu dibuka.
  final Widget child;

  /// Isi yang selalu terlihat namun tidak ikut terlipat dan tidak
  /// menjadi area tap (mis. kartu hasil skor assessment).
  final Widget? body;

  /// Status awal (default tertutup).
  final bool initiallyExpanded;

  final Color? color;
  final EdgeInsetsGeometry padding;

  /// Label aksesibilitas untuk pembaca layar (opsional).
  final String? semanticLabel;

  /// Garis aksen kiri, diteruskan ke [SoftCard]. `null` = tanpa garis.
  final Color? accent;

  /// Warna latar kartu, diteruskan ke [SoftCard]. `null` = warna tema.
  final Color? tone;

  @override
  State<CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<CollapsibleCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return SoftCard(
      color: widget.color,
      accent: widget.accent,
      tone: widget.tone,
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: widget.semanticLabel,
            child: Tooltip(
              message: _expanded ? 'Tutup detail' : 'Lihat detail',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: widget.header),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.body != null) ...[
            const SizedBox(height: 10),
            widget.body!,
          ],
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: widget.child,
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        children: [
          Icon(icon, size: 48, color: MalvaColors.seed),
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
