import 'package:url_launcher/url_launcher.dart';

import '../contracts/ports.dart';

/// [Dialer] mobile/desktop: buka aplikasi telepon lewat skema `tel:`.
class UrlLauncherDialer implements Dialer {
  const UrlLauncherDialer();

  @override
  bool get canDialTel => true;

  @override
  Future<DialOutcome> call(String phoneNumber, {String? displayName}) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      final opened = await launchUrl(uri);
      return opened ? DialOutcome.opened : DialOutcome.failed;
    } on Object {
      return DialOutcome.failed;
    }
  }
}
