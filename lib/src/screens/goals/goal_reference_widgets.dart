import 'package:flutter/material.dart';

const goalPurple = Color(0xFF9853A4);
const goalInk = Color(0xFF252E39);
const goalMuted = Color(0xFF95A0AC);
const goalPaper = Color(0xFFFAFAFD);
const goalTint = Color(0xFFF7F0FA);
const goalLine = Color(0xFFEAE8ED);

const goalGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF5B216F), Color(0xFF7B2E90), Color(0xFFD961DE)],
  stops: [0, .45, 1],
);

class GoalSurface extends StatelessWidget {
  const GoalSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.color = Colors.white,
      this.border = goalLine,
      this.radius = 16});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color, border;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 2))
            ]),
        child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            child: child),
      );
}

class GoalPill extends StatelessWidget {
  const GoalPill(this.label,
      {super.key,
      this.icon,
      this.color = goalPurple,
      this.background = goalTint,
      this.verticalPadding = 4,
      this.fontSize = 11.5});
  final String label;
  final IconData? icon;
  final Color color, background;
  final double fontSize, verticalPadding;
  @override
  Widget build(BuildContext context) => Container(
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: verticalPadding),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize, color: color),
            const SizedBox(width: 5)
          ],
          Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      color: color,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

class GoalButton extends StatelessWidget {
  const GoalButton(this.label,
      {super.key,
      required this.onPressed,
      this.icon = Icons.add,
      this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool primary;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: primary
                ? const [
                    BoxShadow(
                        color: Color(0x339853A4),
                        blurRadius: 12,
                        offset: Offset(0, 8))
                  ]
                : []),
        child: FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: primary ? goalPurple : goalTint,
                foregroundColor: primary ? Colors.white : goalPurple,
                disabledBackgroundColor: goalTint,
                minimumSize: Size.fromHeight(primary ? 56 : 42),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(primary ? 16 : 12)),
                textStyle: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: primary ? 15 : 12.5,
                    fontWeight: FontWeight.w700)),
            icon: Icon(icon, size: primary ? 21 : 18),
            label: Text(label, textAlign: TextAlign.center)),
      );
}

String goalMethodLabel(String method) => switch (method) {
      'numeric' => 'Dengan Nilai',
      'checklist' => 'Sub-tugas',
      _ => 'Ya / Tidak',
    };
IconData goalMethodIcon(String method) => switch (method) {
      'numeric' => Icons.tag_rounded,
      'checklist' => Icons.checklist_rounded,
      _ => Icons.check_circle,
    };
