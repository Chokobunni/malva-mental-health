import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../platform/platform_providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../care_package_screen.dart';
import 'payment_success_screen.dart';

// ============================================================
// PAYMENT — break-down + metode.
//
// Dua mode:
//   * simulation (dev/test): pembayaran dikonfirmasi langsung lewat
//     `POST /v1/payments/mark-paid` dan tercatat di DB.
//   * gateway (Midtrans): metode dipilih di halaman Midtrans. Klien membuka
//     `redirect_url`, TIDAK memanggil mark-paid (server membalas 410), lalu
//     memantau status lewat `GET /v1/payments/{reference}` sampai lunas.
// ============================================================

class PaymentScreen extends ConsumerStatefulWidget {
  static PaymentScreen forReturn(
      {required String reference,
      required AuthSession session,
      required MalvaApiClient apiClient}) {
    final previous = _PaymentScreenState
        ._active[_PaymentScreenState._ownerKey(session, reference)];
    return PaymentScreen(
      key: ValueKey('${session.backendUserId}:$reference'),
      reference: reference,
      booking: previous?._packageBooking ?? previous?.widget.booking,
      package: previous?.widget.package ?? previous?._restoredPackage,
      doctorName: previous?.widget.doctorName ?? 'Profesional',
      session: session,
      apiClient: apiClient,
    );
  }

  const PaymentScreen({
    super.key,
    this.booking,
    this.package,
    this.reference,
    this.doctorName = 'Profesional',
    this.session,
    this.apiClient,
  }) : assert(booking != null || package != null || reference != null,
            'booking, package atau reference wajib diisi');

  /// Quick consult (sesi satu kali).
  final BackendBooking? booking;

  /// Pembelian paket continuous (4 sesi). Payment paket masih lewat
  /// booking pending milik paket — dibuat server saat createCarePackage?
  /// Tidak: paket dibayar lewat booking tersendiri di bawah ini.
  final BackendCarePackage? package;

  /// Return from the gateway only resumes authenticated server verification.
  final String? reference;
  final String doctorName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  bool get isPackage => package != null;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with WidgetsBindingObserver {
  static final Map<String, _PaymentScreenState> _active = {};
  static String _ownerKey(AuthSession? session, String reference) =>
      '${session?.backendUserId}:${session?.identifier}:$reference';
  BackendCarePackage? _restoredPackage;
  String _method = 'qris';
  bool _isPaying = false;
  bool _checkingStatus = false;
  bool _navigated = false;
  bool _embeddedPaymentPage = false;
  static const _paymentBrowser = MethodChannel('malva/payment');
  BackendBooking? _packageBooking;
  String? _error;

  /// Mode pembayaran dari server (`''` = belum diketahui). Saat `gateway`,
  /// metode dipilih di halaman Midtrans sehingga grid metode lokal
  /// disembunyikan (metode di bawah tidak dipakai gateway).
  String _mode = '';

  /// Keadaan menunggu pembayaran gateway.
  bool _waiting = false;
  String _pendingReference = '';
  String _pendingRedirectUrl = '';
  String _waitingNote = '';
  Timer? _pollTimer;
  int _pollElapsedSeconds = 0;

  /// Polling tiap 3 detik; setelah 5 menit turun menjadi tiap 15 detik.
  static const Duration _pollInterval = Duration(seconds: 3);
  static const int _pollMaxSeconds = 300;

  /// Semua e-wallet utama Indonesia.
  static const _wallets = [
    ('gopay', 'GoPay', Icons.account_balance_wallet_rounded),
    ('ovo', 'OVO', Icons.wallet_rounded),
    ('dana', 'DANA', Icons.payments_rounded),
    ('shopeepay', 'ShopeePay', Icons.shopping_bag_rounded),
    ('linkaja', 'LinkAja', Icons.link_rounded),
    ('isaku', 'i.Saku', Icons.credit_score_rounded),
    ('jenius', 'Jenius', Icons.bolt_rounded),
    ('sakuku', 'Sakuku', Icons.paypal_rounded),
  ];

  static const _banks = [
    ('bca_va', 'BCA Virtual Account', Icons.account_balance_rounded),
    ('mandiri_va', 'Mandiri VA', Icons.account_balance_rounded),
    ('bni_va', 'BNI VA', Icons.account_balance_rounded),
    ('bri_va', 'BRI VA', Icons.account_balance_rounded),
    ('permata_va', 'Permata VA', Icons.account_balance_rounded),
    ('cimb_va', 'CIMB Niaga VA', Icons.account_balance_rounded),
    ('cc', 'Credit Card', Icons.credit_card_rounded),
    ('qris', 'QRIS', Icons.qr_code_2_rounded),
  ];

  int get _consultationPrice {
    if (widget.isPackage) return widget.package!.price;
    return widget.booking!.price;
  }

  /// Biaya layanan flat (sama dengan server: 2000).
  static const int _serviceFee = 2000;
  int get _total => _consultationPrice + _serviceFee;

  String get _itemLabel {
    if (widget.isPackage) {
      return 'Paket Continuous (4 sesi / 6 minggu) • ${widget.doctorName}';
    }
    return 'Konsultasi (30 mnt) • ${widget.doctorName}';
  }

  /// True bila metode pembayaran dipilih di halaman gateway (Midtrans).
  bool get _isGatewayMode => _mode == 'gateway';

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);

  String get _doctorUserId {
    if (widget.isPackage) return widget.package!.professionalId;
    return widget.booking?.professionalId ??
        _packageBooking?.professionalId ??
        _restoredPackage?.professionalId ??
        '';
  }

  @override
  void initState() {
    super.initState();
    _packageBooking = widget.booking;
    // Lifecycle observer: Android bisa membekukan timer saat aplikasi di
    // belakang, jadi status juga dicek ulang saat aplikasi kembali ke depan.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPaymentConfig());
    if (widget.reference != null) {
      _waiting = true;
      _pendingReference = widget.reference!;
      _claimReference();
      _mode = 'gateway';
      _waitingNote = 'Memeriksa status pembayaran melalui server Malva.';
      _startPolling();
      unawaited(_checkPaymentStatus());
    }
  }

  @override
  void dispose() {
    // Batalkan polling SEBELUM widget dibuang: timer yang hidup akan memanggil
    // setState pada state yang sudah mati.
    _pollTimer?.cancel();
    final key = _ownerKey(widget.session, _pendingReference);
    if (identical(_active[key], this)) _active.remove(key);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waiting) {
      unawaited(_checkPaymentStatus(silent: true));
    }
  }

  /// Mengambil mode pembayaran dari server. Kegagalan TIDAK memblokir
  /// pembayaran: mode dibiarkan tidak diketahui dan keputusan akhir diambil
  /// dari ada/tidaknya `redirect_url` pada respons createPayment.
  Future<void> _loadPaymentConfig() async {
    try {
      final config = await _api.getPaymentConfig();
      if (!mounted) return;
      setState(() {
        _mode = config.mode;
      });
    } on Object {
      // Diabaikan dengan sengaja (lihat doc comment).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (widget.reference == null) ...[
            const SectionLabel('Payment Detail'),
            SoftCard(
              child: Column(
                children: [
                  _Line(
                      label: _itemLabel,
                      value: 'Rp ${_rupiah(_consultationPrice)}'),
                  const SizedBox(height: 6),
                  _Line(
                      label: 'Service Fee',
                      value: 'Rp ${_rupiah(_serviceFee)}'),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Total',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                      Text(
                        'Rp ${_rupiah(_total)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: MalvaColors.seed,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_isGatewayMode)
              const Text(
                'Metode pembayaran dipilih di halaman Midtrans.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              )
            else
              const Text(
                'Mode pembayaran internal (simulasi gateway). Transaksi tercatat di server.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            const SizedBox(height: 12),
            if (_isGatewayMode) ...[
              // Mode gateway: metode TIDAK dipilih di sini. Grid di bawah hanya
              // berlaku untuk mode simulasi; menampilkannya akan menyesatkan
              // (seolah metode lokal yang dipakai padahal Midtrans yang memilih).
              const SoftCard(
                child: Column(
                  children: [
                    Text(
                      'GoPay, QRIS, Virtual Account & kartu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Semua metode pembayaran tersedia di halaman Midtrans. '
                      'Setelah pembayaran selesai, status di layar ini diperbarui otomatis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SectionLabel('E-Wallet'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: [
                  for (final (value, label, icon) in _wallets)
                    _MethodTile(
                      label: label,
                      icon: icon,
                      selected: _method == value,
                      onTap: () => setState(() => _method = value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const SectionLabel('Virtual Account, Bank & QRIS'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: [
                  for (final (value, label, icon) in _banks)
                    _MethodTile(
                      label: label,
                      icon: icon,
                      selected: _method == value,
                      onTap: () => setState(() => _method = value),
                    ),
                ],
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          if (_waiting) ...[
            SoftCard(
              child: Column(
                children: [
                  const Text('Menunggu pembayaran',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(
                    _waitingNote.isEmpty
                        ? 'Selesaikan pembayaran di halaman Midtrans. '
                            'Status di layar ini diperbarui otomatis.'
                        : _waitingNote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(_pendingReference),
                  OutlinedButton(
                    onPressed: _isPaying ? null : () => _checkPaymentStatus(),
                    child: const Text('Cek status'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _pendingRedirectUrl.isEmpty
                        ? null
                        : () =>
                            unawaited(_openPaymentPage(_pendingRedirectUrl)),
                    child: const Text('Buka halaman pembayaran'),
                  ),
                  if (_pendingRedirectUrl.isEmpty && widget.reference == null)
                    TextButton(
                        onPressed: _isPaying ? null : _pay,
                        child: const Text('Pulihkan halaman pembayaran')),
                ],
              ),
            ),
          ] else if (widget.reference == null)
            FilledButton(
              onPressed: _isPaying ? null : _pay,
              child: Text(_isPaying ? 'Memproses...' : 'Bayar Sekarang'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Setelah pembayaran berhasil, lihat paket atau sesi kamu di MyCare. Pengaturan berbagi data dapat diubah melalui Kelola Data.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _pay() async {
    // Fallback ke provider bila apiClient tidak dioper eksplisit (mis.
    // deep-link), konsisten dengan layar lain.
    final MalvaApiClient apiClient = _api;
    final accessToken = widget.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk melakukan pembayaran.');
      return;
    }
    setState(() {
      _isPaying = true;
      _error = null;
    });
    try {
      if (widget.isPackage) {
        await _payPackage(apiClient, accessToken);
        return;
      }
      final response = await apiClient.createPayment(
        accessToken: accessToken,
        bookingId: widget.booking!.id,
        paymentMethod: _method,
      );
      await _afterPaymentCreated(apiClient, accessToken, response.payment);
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  /// Bayar paket: pasien memilih slot sesi PERTAMA (chat/video) di sini
  /// lewat sheet yang sama dengan penjadwalan sesi paket — tidak ada lagi
  /// slot otomatis "pertama yang bebas". Setelah bayar, paket aktif dan
  /// sesi pertama langsung terjadwal sesuai pilihan pasien.
  Future<void> _payPackage(MalvaApiClient apiClient, String accessToken) async {
    var booking = _packageBooking;
    if (booking == null && widget.package!.bookingId != null) {
      final bookings =
          await apiClient.listBookings(accessToken: accessToken, limit: 100);
      for (final b in bookings) {
        if (b.id == widget.package!.bookingId) {
          booking = b;
          break;
        }
      }
      if (booking == null) {
        throw const MalvaApiException(
            'Booking paket belum ditemukan. Muat ulang paket lalu coba lagi.');
      }
    }
    if (booking == null) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (_) => PackageFirstSessionSheet(
          apiClient: apiClient,
          accessToken: accessToken,
          professionalId: widget.package!.professionalId,
        ),
      );
      if (picked == null || !mounted) return;
      final parts = picked.split('|');
      booking = await apiClient.createPackageSessionBooking(
        accessToken: accessToken,
        packageId: widget.package!.id,
        bookingDate: parts[0].split('T')[0],
        slotTime: parts[0].split('T')[1],
        sessionType: parts.length > 1 ? parts[1] : 'chat',
      );
    }
    _packageBooking = booking;
    final response = await apiClient.createPayment(
      accessToken: accessToken,
      bookingId: booking.id,
      paymentMethod: _method,
    );
    await _afterPaymentCreated(apiClient, accessToken, response.payment);
  }

  /// Menentukan langkah setelah payment dibuat.
  ///
  /// Mode gateway (ditandai `redirect_url` terisi): konfirmasi manual TIDAK
  /// dipanggil (server membalas 410) — pembayaran dikonfirmasi webhook
  /// Midtrans, dan klien memantau statusnya. Mode simulasi: perilaku lama.
  Future<void> _afterPaymentCreated(
    MalvaApiClient apiClient,
    String accessToken,
    BackendPayment payment,
  ) async {
    if (payment.status.toLowerCase() == 'paid') {
      _goToSuccess(payment.reference);
      return;
    }
    if (payment.redirectUrl.isNotEmpty ||
        payment.gateway == 'midtrans' ||
        _isGatewayMode) {
      _startWaitingForGateway(payment);
      return;
    }
    await apiClient.markPaymentPaid(
      accessToken: accessToken,
      reference: payment.reference,
    );
    _goToSuccess(payment.reference);
  }

  /// Masuk keadaan menunggu pembayaran gateway: pantau status lebih dulu, lalu
  /// buka halaman Midtrans. Urutan ini penting — polling tidak boleh
  /// bergantung pada keberhasilan membuka browser eksternal (mis. platform
  /// channel tidak tersedia / pengguna menutup browser), karena webhook tetap
  /// bisa melunasi pembayaran tanpa aplikasi membuka apa pun.
  void _startWaitingForGateway(BackendPayment payment) {
    _pollTimer?.cancel();
    setState(() {
      _waiting = true;
      _isPaying = false;
      _error = null;
      _waitingNote = payment.redirectUrl.isEmpty
          ? 'Transaksi sedang diperiksa. Jangan membuat pembayaran baru. Pulihkan halaman pembayaran atau hubungi tim Malva dengan nomor referensi ini bila halaman belum tersedia.'
          : '';
      _pendingReference = payment.reference;
      _pendingRedirectUrl = payment.redirectUrl;
      _pollElapsedSeconds = 0;
    });
    _claimReference();
    _startPolling();
    unawaited(_openPaymentPage(payment.redirectUrl));
  }

  void _claimReference() {
    final key = _ownerKey(widget.session, _pendingReference);
    final previous = _active[key];
    if (previous != null && !identical(previous, this)) {
      previous._pollTimer?.cancel();
      previous._navigated = true;
    }
    _active[key] = this;
  }

  Future<void> _restoreReturnContext(
      BackendPayment payment, String accessToken) async {
    if (widget.reference == null ||
        widget.booking != null ||
        widget.package != null) return;
    final bookings =
        await _api.listBookings(accessToken: accessToken, limit: 100);
    for (final booking in bookings) {
      if (booking.id == payment.bookingId) {
        _packageBooking = booking;
        break;
      }
    }
    if (_packageBooking == null)
      throw const MalvaApiException(
          'Pembayaran diterima. Konteks booking belum tersedia; cek status lagi atau buka MyCare.');
    if (_packageBooking!.serviceType == 'package_session') {
      final packages = await _api.listCarePackages(accessToken: accessToken);
      for (final package in packages) {
        if (package.bookingId == payment.bookingId) {
          _restoredPackage = package;
          break;
        }
      }
      if (_restoredPackage == null)
        throw const MalvaApiException(
            'Pembayaran diterima. Paket belum tersedia; cek status lagi atau buka MyCare.');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _pollElapsedSeconds += _pollInterval.inSeconds;
      if (_pollElapsedSeconds >= _pollMaxSeconds &&
          _pollElapsedSeconds % 15 != 0) return;
      unawaited(_checkPaymentStatus(silent: true));
    });
  }

  /// Membuka halaman pembayaran gateway. Kegagalan membuka halaman tidak
  /// menggagalkan alur: pengguna tetap punya tombol "Buka halaman pembayaran".
  Future<void> _openPaymentPage(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      _embeddedPaymentPage =
          ref.read(capabilitiesProvider).canUseEmbeddedPaymentSandbox &&
              uri.scheme == 'https' &&
              uri.host == 'app.sandbox.midtrans.com' &&
              uri.path.startsWith('/snap/');
      final opened = _embeddedPaymentPage
          ? (await _paymentBrowser
                  .invokeMethod<bool>('openSandbox', {'url': url}) ??
              false)
          : await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _waitingNote =
            'Halaman pembayaran tidak bisa dibuka otomatis. Tekan "Buka halaman pembayaran" di bawah.');
      }
    } on Object {
      // Platform channel tidak tersedia (mis. widget test) — diabaikan.
    }
  }

  /// Memeriksa status pembayaran ke server (juga memicu aktivasi best-effort
  /// di server bila sudah lunas tetapi sesinya belum lahir).
  Future<void> _checkPaymentStatus({bool silent = false}) async {
    if (_pendingReference.isEmpty || _checkingStatus || _navigated) return;
    final accessToken = widget.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;
    _checkingStatus = true;
    if (!silent && mounted) setState(() => _isPaying = true);
    try {
      final status = await _api.getPaymentStatus(
        accessToken: accessToken,
        reference: _pendingReference,
      );
      if (!mounted || _navigated) return;
      final state = status.payment.status.toLowerCase();
      if (status.payment.redirectUrl.isNotEmpty) {
        _pendingRedirectUrl = status.payment.redirectUrl;
      }
      if (state == 'paid') {
        await _restoreReturnContext(status.payment, accessToken);
        if (!mounted || _navigated) return;
        _pollTimer?.cancel();
        setState(() => _waiting = false);
        _goToSuccess(_pendingReference);
        return;
      }
      if (state == 'cancelled' || state == 'expired' || state == 'deny') {
        _pollTimer?.cancel();
        setState(() {
          _waiting = false;
          _isPaying = false;
          _error = 'Pembayaran tidak selesai ($state). '
              '${widget.reference == null ? 'Kamu bisa mencoba lagi dengan menekan "Bayar Sekarang".' : 'Kembali ke MyCare untuk melanjutkan pembelian.'}';
        });
        return;
      }
      // Setelah lima menit tetap pantau dengan interval lebih jarang.
      if (_pollElapsedSeconds >= _pollMaxSeconds) {
        setState(() {
          _isPaying = false;
          _waitingNote =
              'Pembayaran belum terkonfirmasi. Status tetap diperiksa otomatis. '
              'Bila sudah membayar, kamu juga bisa menekan "Cek status".';
        });
        return;
      }
      if (mounted) setState(() => _isPaying = false);
    } on Object catch (e) {
      // Kegagalan jaringan saat memeriksa status bukan kegagalan pembayaran.
      if (!mounted) return;
      setState(() {
        _isPaying = false;
        if (!silent) _waitingNote = friendlyErrorMessage(e);
      });
    } finally {
      _checkingStatus = false;
    }
  }

  /// Pindah ke layar sukses (layar itu yang mengarahkan ke MyCare).
  void _goToSuccess(String reference) {
    if (!mounted || _navigated) return;
    _navigated = true;
    unawaited(_closePaymentPage());
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          reference: reference,
          package: widget.package ?? _restoredPackage,
          doctorUserId: _doctorUserId,
          doctorName: widget.doctorName,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }

  Future<void> _closePaymentPage() async {
    if (!_embeddedPaymentPage) return;
    try {
      await _paymentBrowser.invokeMethod<void>('closeSandbox');
    } on Object {/* unsupported platform */}
  }

  static String _rupiah(int value) {
    return _rupiahFmt(value);
  }

  static String _rupiahFmt(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      buf.write(s[i]);
      if (pos > 1 && pos % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? MalvaColors.seed.withValues(alpha: 0.12)
              : MalvaColors.seed.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MalvaColors.seed
                : MalvaColors.seed.withValues(alpha: 0.35),
            width: selected ? 2 : 1.5,
          ),
        ),
        // Column (bukan Row): ikon di atas, label di bawah. Grid 4 kolom
        // hanya ~80px per tile — Row memaksa teks ke lebar ~28px sehingga
        // setiap huruf turun vertikal satu per satu ("G\no\nP\na\ny").
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: MalvaColors.seed,
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                if (selected)
                  const Positioned(
                    top: -4,
                    right: -4,
                    child: Icon(Icons.check_circle_rounded,
                        color: MalvaColors.seed, size: 14),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
