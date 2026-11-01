import '../contracts/ports.dart';

/// [Dialer] web — STUB fase 1 (`canDialTel == false`).
///
/// Browser tidak punya penangan `tel:` yang andal (desktop). Fallback yang
/// benar (sheet berisi nomor + tombol salin + tautan `wa.me`, lalu
/// `DialOutcome.fallbackShown`) dibangun di T03 bersama UI Safety. Untuk T01
/// [call] hanya melaporkan bahwa jalur fallback yang dipakai — tidak ada klaim
/// palsu "sudah menelepon".
class BrowserDialer implements Dialer {
  const BrowserDialer();

  @override
  bool get canDialTel => false;

  @override
  Future<DialOutcome> call(String phoneNumber, {String? displayName}) async =>
      DialOutcome.fallbackShown;
}
