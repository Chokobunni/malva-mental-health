import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'professional_avatar.dart';

const profileAvatarAssets = [
  'assets/reference/avatar-1.png',
  'assets/reference/avatar-2.png',
  'assets/reference/avatar-3.png',
  'assets/reference/avatar-4.png',
  'assets/reference/avatar-5.png',
];
const defaultProfileAvatar = 'default';

String profileAvatarKey(String userId) => 'profile.avatar.$userId';

final patientAvatarProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  return ref.watch(secureStoreProvider).read(profileAvatarKey(userId));
});

final _professionalPhotoProvider = FutureProvider.autoDispose
    .family<String?, (MalvaApiClient, String)>((ref, request) async {
  ref.watch(professionalProfileRevisionProvider);
  final (api, token) = request;
  return (await api.getMyCredentials(accessToken: token))?.photoIntroUrl;
});

class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({
    super.key,
    this.session,
    this.apiClient,
    this.avatar,
    this.size = 36,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String? avatar;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = session ?? ref.watch(currentSessionProvider);
    final userId = current?.backendUserId;
    final token = current?.accessToken;
    final professional = current?.role == UserRole.professional;
    final neutralAvatar = ColoredBox(
      color: const Color(0xffecd7f4),
      child: Center(
        child: Icon(Icons.person_rounded,
            color: MalvaColors.plum, size: size * .61),
      ),
    );
    final fallback = professional
        ? ColoredBox(
            color: const Color(0xfff3e9f8),
            child: Center(
              child: Icon(Icons.person_outline,
                  color: MalvaColors.seed, size: size * .61),
            ),
          )
        : Image.asset(profileAvatarAssets.first, fit: BoxFit.cover);

    Widget picture = fallback;
    if (professional && token != null && token.isNotEmpty) {
      final api = apiClient ?? ref.watch(apiClientProvider);
      final url = api == null
          ? null
          : ref.watch(_professionalPhotoProvider((api, token))).valueOrNull;
      if (url != null && url.isNotEmpty) {
        picture = ProfessionalPhoto(
          key: ValueKey(url),
          photoUrl: url,
          fallback: fallback,
          width: size,
          height: size,
        );
      }
    } else if (!professional) {
      final selected = avatar ??
          (userId == null
              ? null
              : ref.watch(patientAvatarProvider(userId)).valueOrNull);
      if (selected == defaultProfileAvatar) {
        picture = neutralAvatar;
      } else if (selected != null && profileAvatarAssets.contains(selected)) {
        picture = Image.asset(selected, fit: BoxFit.cover);
      } else if (selected != null) {
        try {
          picture = Image.memory(
            base64Decode(selected),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          );
        } on FormatException {
          picture = fallback;
        }
      }
    }
    return SizedBox.square(dimension: size, child: ClipOval(child: picture));
  }
}
