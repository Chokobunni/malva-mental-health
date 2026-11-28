import 'package:flutter/material.dart';

import 'malva_components.dart';

class BookingSlotsEmpty extends StatelessWidget {
  const BookingSlotsEmpty({super.key});

  @override
  Widget build(BuildContext context) => SoftCard(
        color: Colors.white,
        child: Column(
          children: [
            Image.asset('assets/reference/calendar-slots-empty.png',
                width: 104, height: 104, excludeFromSemantics: true),
            const SizedBox(height: 12),
            const Text('Tidak ada slot tersedia',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
      );
}
