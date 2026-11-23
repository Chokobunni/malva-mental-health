import 'package:flutter/material.dart';

import '../theme.dart';
import '../models.dart';
import 'account_avatar.dart';
import 'malva_components.dart';

const carePageColor = Color(0xfff8f2fc);
const careSoftShadow = [
  BoxShadow(color: Color(0x1654206f), blurRadius: 12, offset: Offset(0, 4))
];
const careCardBorder = BorderSide(color: Color(0xffe5d4ed));
const careHeaderDecoration = BoxDecoration(
  gradient: LinearGradient(
    colors: [Color(0xFF54206F), Color(0xFF8A3AA2), Color(0xFFC97BCC)],
    stops: [0, .45, 1],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),
  borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
);

class CareHeaderNotification extends StatelessWidget {
  const CareHeaderNotification({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: 'Notifikasi',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .16),
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.notifications_outlined, size: 19),
      );
}

class CarePageHeader extends StatelessWidget {
  const CarePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.session,
    required this.onNotifications,
    required this.onProfile,
  });

  final String title, subtitle;
  final AuthSession? session;
  final VoidCallback onNotifications, onProfile;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: careHeaderDecoration,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(21, 8, 16, 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Image.asset('assets/checkin/flower-white.png',
                    width: 26, height: 30),
                const Spacer(),
                CareHeaderNotification(onPressed: onNotifications),
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'Profil',
                  onPressed: onProfile,
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                  ),
                  padding: const EdgeInsets.all(2),
                  icon: AccountAvatar(session: session),
                ),
              ]),
              const SizedBox(height: 13),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .84),
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class CareIllustratedCard extends StatelessWidget {
  const CareIllustratedCard({
    super.key,
    required this.asset,
    required this.title,
    this.subtitle,
    this.horizontal = false,
    this.imageHeight,
    this.action,
  });

  final String asset, title;
  final String? subtitle;
  final bool horizontal;
  final double? imageHeight;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Text(
      title,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        color: horizontal ? MalvaColors.plum : MalvaColors.ink,
        fontSize: horizontal ? 16 : 19,
        fontWeight: FontWeight.w900,
      ),
    );
    final description = subtitle == null
        ? null
        : Text(
            subtitle!,
            textAlign: horizontal ? TextAlign.start : TextAlign.center,
            style: const TextStyle(color: Color(0xff535964), fontSize: 13),
          );
    final image = Image.asset(
      asset.startsWith('assets/') ? asset : 'assets/care/$asset.png',
      height: imageHeight ?? (horizontal ? 72 : 126),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    return SoftCard(
      color: Colors.white,
      outline: careCardBorder,
      radius: 16,
      padding:
          EdgeInsets.symmetric(horizontal: 16, vertical: horizontal ? 10 : 23),
      child: horizontal
          ? Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    heading,
                    if (description != null) ...[
                      const SizedBox(height: 7),
                      description
                    ],
                  ])),
              const SizedBox(width: 8),
              SizedBox(width: 105, child: image),
            ])
          : SizedBox(
              width: double.infinity,
              child: Column(children: [
                image,
                const SizedBox(height: 15),
                heading,
                if (description != null) ...[
                  const SizedBox(height: 7),
                  description
                ],
                if (action != null) ...[
                  const SizedBox(height: 20),
                  action!,
                ],
              ])),
    );
  }
}
