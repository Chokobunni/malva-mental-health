import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../models.dart';

const prescriptionPurple = Color(0xff923ba5);
const prescriptionGreen = Color(0xff299f88);

/// Binds asynchronous prescription work to the account that opened the page.
class PrescriptionAccountGuard {
  PrescriptionAccountGuard(this.supplied, AuthSession? active)
      : _bound = active != null,
        _opening = supplied ?? active;
  final AuthSession? supplied;
  bool _bound;
  AuthSession? _opening;
  String? owner(AuthSession? value) => value == null
      ? null
      : '${value.role.name}|${value.backendUserId ?? value.identifier}';
  AuthSession? session(AuthSession? active) {
    if (_opening == null && active != null) _opening = active;
    if (active != null) _bound = true;
    if (_bound && owner(active) != owner(_opening)) return null;
    return active ?? supplied;
  }

  bool current(AuthSession? active) => session(active) != null;
}

class PrescriptionPanel extends StatelessWidget {
  const PrescriptionPanel(
      {super.key,
      required this.child,
      this.color = Colors.white,
      this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xffe6e5eb)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x07000000), blurRadius: 8, offset: Offset(0, 3))
          ]),
      child: Material(type: MaterialType.transparency, child: child));
}

class PrescriptionStatus extends StatelessWidget {
  const PrescriptionStatus({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final issued = status == 'issued';
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: issued ? const Color(0xffe3f6f0) : const Color(0xfffff3cf),
            borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(issued ? Icons.check_circle : Icons.schedule,
              size: 16,
              color: issued ? prescriptionGreen : const Color(0xff9c762f)),
          const SizedBox(width: 5),
          Text(issued ? 'Issued' : 'Draft',
              style: TextStyle(
                  color: issued ? prescriptionGreen : const Color(0xff9c762f),
                  fontWeight: FontWeight.w800))
        ]));
  }
}

class PrescriptionQr extends StatelessWidget {
  const PrescriptionQr({super.key, required this.value, this.size = 110});
  final String value;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'QR verifikasi resep',
      image: true,
      child: CustomPaint(
          size: Size.square(size), painter: _PrescriptionQrPainter(value)));
}

class _PrescriptionQrPainter extends CustomPainter {
  _PrescriptionQrPainter(this.value)
      : image = QrImage(QrCode.fromData(
            data: value, errorCorrectLevel: QrErrorCorrectLevel.M));
  final String value;
  final QrImage image;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final unit = size.shortestSide / (image.moduleCount + 8);
    final paint = Paint()
      ..color = const Color(0xff212833)
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (image.isDark(row, col))
          canvas.drawRect(
              Rect.fromLTWH((col + 4) * unit, (row + 4) * unit, unit, unit),
              paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PrescriptionQrPainter old) =>
      old.value != value;
}

Future<bool> confirmPrescriptionDelete(BuildContext context) => showDialog<
        bool>(
    context: context,
    builder: (context) => AlertDialog(
            title: const Text('Hapus resep ini?'),
            content: const Text(
                'Resep akan dihapus dari daftar dan obatnya dihentikan. Riwayat dosis yang sudah dicatat tetap tersimpan.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      minimumSize: const Size(0, 48)),
                  child: const Text('Hapus Resep'))
            ])).then((value) => value ?? false);
