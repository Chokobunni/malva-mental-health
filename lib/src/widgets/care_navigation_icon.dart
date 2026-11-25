import 'package:flutter/material.dart';

class CareNavigationIcon extends StatelessWidget {
  const CareNavigationIcon({
    super.key,
    required this.asset,
    this.selected = false,
  });

  final String asset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/care/nav-$asset${selected ? '-selected' : ''}.png',
      width: selected ? 44 : 38,
      height: selected ? 44 : 38,
      color: selected ? null : const Color(0xff98a4b4),
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
