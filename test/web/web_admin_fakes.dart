import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

/// [MalvaApiClient] palsu untuk test layar web (admin & asesmen).
///
/// Hanya metode yang dipakai layar yang di-override; sisanya memakai
/// implementasi asli (tidak pernah dipanggil karena test tidak melakukan HTTP).
class FakeAdminApi extends MalvaApiClient {
  FakeAdminApi({
    this.page,
    this.detail,
    this.pricing = const <AdminPricingItem>[],
    this.overview,
    this.users = const <AdminUser>[],
    this.pendingCredentials = const <BackendProfessionalCredential>[],
    this.doctors = const <BackendDoctorSearchResult>[],
    this.screenings = const <BackendScreeningSession>[],
    this.therapySubmissions = const <BackendTherapySubmission>[],
    this.links = const <BackendPatientProfessionalLink>[],
  }) : super(baseUrl: 'http://test.local');

  AdminPaymentPage? page;
  AdminPaymentDetail? detail;
  List<AdminPricingItem> pricing;
  AdminOverview? overview;
  List<AdminUser> users;
  List<BackendProfessionalCredential> pendingCredentials;
  List<BackendDoctorSearchResult> doctors;

  /// Riwayat asesmen yang dikembalikan server palsu.
  List<BackendScreeningSession> screenings;
  List<BackendTherapySubmission> therapySubmissions;
  List<BackendPatientProfessionalLink> links;

  /// Jumlah panggilan tulis (untuk memastikan UI tidak mengirim saat belum sah).
  int screeningSubmits = 0;
  int therapyCreates = 0;
  int shares = 0;
  String lastShareProfessionalId = '';

  /// Data katalog/booking/MyCare untuk test #4b.
  BackendDoctorProfile? doctorProfile;
  BackendProfessionalPricing professionalPricing =
      const BackendProfessionalPricing(
    quickChatPrice: 150000,
    quickVideoPrice: 250000,
    packagePrice: 800000,
  );
  List<BackendDoctorSlot> slots = const <BackendDoctorSlot>[
    BackendDoctorSlot(time: '09:00', available: true),
    BackendDoctorSlot(time: '10:00', available: true),
    BackendDoctorSlot(time: '11:00', available: false),
  ];
  List<BackendCarePackage> carePackages = const <BackendCarePackage>[];
  List<BackendCareSession> careSessions = const <BackendCareSession>[];

  /// Status pembayaran yang dilaporkan `getPaymentStatus`.
  String paymentStatusValue = 'pending';
  int bookingCreates = 0;
  int paymentCreates = 0;
  int rescheduleCalls = 0;
  int cancelSessionCalls = 0;
  int cancelPackageCalls = 0;

  /// Bila diisi, semua panggilan melempar error ini (uji tampilan error).
  Object? failWith;

  final List<({String paymentId, String status, String reason})> overrides =
      <({String paymentId, String status, String reason})>[];
  final List<({String professionalId, int chat, int video, int package})>
      pricingUpdates =
      <({String professionalId, int chat, int video, int package})>[];
  int resetPasswordCalls = 0;
  int revokeSessionCalls = 0;
  final List<({String userId, bool? disabled, String? role})> userUpdates =
      <({String userId, bool? disabled, String? role})>[];

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<AdminOverview> adminOverview({required String accessToken}) async {
    _maybeFail();
    return overview ??
        const AdminOverview(
          usersTotal: 0,
          usersPatients: 0,
          usersProfessionals: 0,
          usersDisabled: 0,
          paidCount: 0,
          pendingCount: 0,
          monthRevenue: 0,
          sessionsToday: 0,
          credentialsPending: 0,
        );
  }

  @override
  Future<AdminPaymentPage> listAdminPayments({
    required String accessToken,
    String query = '',
    String status = '',
    String from = '',
    String to = '',
    int limit = 50,
    int offset = 0,
  }) async {
    _maybeFail();
    return page ??
        const AdminPaymentPage(
          items: <AdminPaymentItem>[],
          total: 0,
          summary: AdminPaymentSummary(
            pending: 0,
            paid: 0,
            failed: 0,
            refunded: 0,
            grossPaid: 0,
          ),
        );
  }

  @override
  Future<AdminPaymentDetail> getAdminPayment({
    required String accessToken,
    required String paymentId,
  }) async {
    _maybeFail();
    final current = detail;
    if (current != null) return current;
    return AdminPaymentDetail(
      payment: AdminPaymentItem(
        id: paymentId,
        reference: 'INV-TEST',
        status: 'pending',
        paymentMethod: 'qris',
        grossAmount: 0,
        serviceFeeAmount: 0,
        platformFeeAmount: 0,
        netAmount: 0,
      ),
      events: const <AdminPaymentEvent>[],
      refunds: const <AdminRefundItem>[],
    );
  }

  @override
  Future<AdminPaymentOverrideResult> overrideAdminPayment({
    required String accessToken,
    required String paymentId,
    required String status,
    required String reason,
  }) async {
    _maybeFail();
    overrides.add((paymentId: paymentId, status: status, reason: reason));
    final current = detail;
    final payment = current?.payment ??
        AdminPaymentItem(
          id: paymentId,
          reference: 'INV-TEST',
          status: status,
          paymentMethod: '',
          grossAmount: 0,
          serviceFeeAmount: 0,
          platformFeeAmount: 0,
          netAmount: 0,
        );
    return AdminPaymentOverrideResult(payment: payment, changed: true);
  }

  @override
  Future<List<AdminPricingItem>> listAdminPricing({
    required String accessToken,
  }) async {
    _maybeFail();
    return pricing;
  }

  @override
  Future<AdminPricingItem> updateAdminPricing({
    required String accessToken,
    required String professionalId,
    int? quickChatPrice,
    int? quickVideoPrice,
    int? packagePrice,
  }) async {
    _maybeFail();
    final index = pricing
        .indexWhere((AdminPricingItem e) => e.professionalId == professionalId);
    final current = index >= 0
        ? pricing[index]
        : AdminPricingItem(
            professionalId: professionalId,
            name: 'Dokter Uji',
            email: 'uji@malva.test',
            specialization: 'Sp.KJ',
            quickChatPrice: 0,
            quickVideoPrice: 0,
            packagePrice: 0,
          );
    final updated = AdminPricingItem(
      professionalId: current.professionalId,
      name: current.name,
      email: current.email,
      specialization: current.specialization,
      quickChatPrice: quickChatPrice ?? current.quickChatPrice,
      quickVideoPrice: quickVideoPrice ?? current.quickVideoPrice,
      packagePrice: packagePrice ?? current.packagePrice,
      updatedAt: current.updatedAt,
    );
    pricingUpdates.add((
      professionalId: professionalId,
      chat: updated.quickChatPrice,
      video: updated.quickVideoPrice,
      package: updated.packagePrice,
    ));
    if (index >= 0) {
      pricing = <AdminPricingItem>[...pricing]..[index] = updated;
    }
    return updated;
  }

  @override
  Future<List<AdminUser>> listAdminUsers({
    required String accessToken,
    String query = '',
    String role = '',
    String status = '',
    int limit = 200,
  }) async {
    _maybeFail();
    return users;
  }

  @override
  Future<AdminUser> updateAdminUser({
    required String accessToken,
    required String userId,
    String? displayName,
    String? role,
    String? phone,
    String? dateOfBirth,
    String? gender,
    bool? disabled,
  }) async {
    _maybeFail();
    userUpdates.add((userId: userId, disabled: disabled, role: role));
    final index = users.indexWhere((AdminUser u) => u.id == userId);
    final current = index >= 0
        ? users[index]
        : const AdminUser(
            id: 'unknown',
            email: 'unknown@malva.test',
            role: 'patient',
            displayName: 'Tanpa Nama',
          );
    return AdminUser(
      id: current.id,
      email: current.email,
      role: role ?? current.role,
      displayName: current.displayName,
      disabled: disabled ?? current.disabled,
    );
  }

  @override
  Future<void> resetAdminUserPassword({
    required String accessToken,
    required String userId,
    required String newPassword,
  }) async {
    _maybeFail();
    resetPasswordCalls++;
  }

  @override
  Future<int> revokeAdminUserSessions({
    required String accessToken,
    required String userId,
  }) async {
    _maybeFail();
    revokeSessionCalls++;
    return 2;
  }

  @override
  Future<List<BackendProfessionalCredential>> listPendingCredentials({
    required String accessToken,
  }) async {
    _maybeFail();
    return pendingCredentials;
  }

  @override
  Future<List<BackendDoctorSearchResult>> listAdminDoctors({
    required String accessToken,
  }) async {
    _maybeFail();
    return doctors;
  }

  // ── Asesmen (screening + therapy submission) ──
  @override
  Future<BackendScreeningResult> submitScreening({
    required String accessToken,
    required ScreeningBundle bundle,
    List<int>? phq9Answers,
    List<int>? gad7Answers,
    String? patientId,
  }) async {
    _maybeFail();
    screeningSubmits++;
    return BackendScreeningResult(
      id: 'scr-test',
      overallLevel: 'minimal',
      crisisFlag: false,
      createdAt: wibNow(),
    );
  }

  @override
  Future<List<BackendScreeningSession>> listScreenings({
    required String accessToken,
    required String patientId,
    int limit = 20,
  }) async {
    _maybeFail();
    return screenings;
  }

  @override
  Future<List<BackendTherapySubmission>> listTherapySubmissions({
    required String accessToken,
    String? patientId,
    int limit = 100,
  }) async {
    _maybeFail();
    return therapySubmissions;
  }

  @override
  Future<BackendTherapySubmission> createTherapySubmission({
    required String accessToken,
    required String moduleId,
    required String title,
    required Map<String, dynamic> answers,
    String summary = '',
  }) async {
    _maybeFail();
    therapyCreates++;
    return BackendTherapySubmission(
      id: 'sub-test',
      moduleId: moduleId,
      title: title,
      answers: answers,
      summary: summary,
      createdAt: '2026-11-02T09:00:00+07:00',
    );
  }

  @override
  Future<List<BackendPatientProfessionalLink>> listPatientProfessionalLinks({
    required String accessToken,
  }) async {
    _maybeFail();
    return links;
  }

  @override
  Future<BackendTherapySubmission> shareTherapySubmission({
    required String accessToken,
    required String submissionId,
    required String professionalId,
  }) async {
    _maybeFail();
    shares++;
    lastShareProfessionalId = professionalId;
    return BackendTherapySubmission(
      id: submissionId,
      moduleId: 'dass21',
      title: 'test',
      answers: const <String, dynamic>{},
      summary: '',
      sharedWithProfessionalId: professionalId,
    );
  }

  // ── Katalog profesional, booking, pembayaran ──
  @override
  Future<List<BackendDoctorSearchResult>> searchDoctors({
    String? accessToken,
    double? patientLat,
    double? patientLng,
    String specialization = '',
    int? maxPrice,
    double? maxKm,
    bool? isBpjsSupported,
    String sortBy = 'name_asc',
    int limit = 50,
  }) async {
    _maybeFail();
    return doctors;
  }

  @override
  Future<BackendDoctorProfile> getDoctorProfile({
    String? accessToken,
    required String userId,
  }) async {
    _maybeFail();
    return doctorProfile ??
        BackendDoctorProfile(
          credential: const BackendProfessionalCredential(
            id: 'cred-1',
            userId: 'pro-1',
            specialization: 'Sp.KJ',
            verificationStatus: 'VERIFIED',
            strNumber: '1234567890123456',
            sipNumber: '6543210987654321',
            sippNumber: '',
            bio: 'Psikiater dengan pengalaman 10 tahun.',
          ),
          pricing: professionalPricing,
        );
  }

  @override
  Future<BackendProfessionalPricing> getPricing({
    required String accessToken,
    String? professionalId,
  }) async {
    _maybeFail();
    return professionalPricing;
  }

  @override
  Future<BackendDoctorReviews> listDoctorReviews({
    String? accessToken,
    required String userId,
  }) async {
    _maybeFail();
    return const BackendDoctorReviews();
  }

  @override
  Future<List<BackendDoctorSlot>> getDoctorAvailableSlots({
    String? accessToken,
    required String userId,
    required String date,
  }) async {
    _maybeFail();
    return slots;
  }

  @override
  Future<BackendBooking> createBooking({
    required String accessToken,
    String patientId = '',
    required String professionalId,
    String? packageId,
    String serviceType = 'quick_consult',
    String sessionType = 'chat',
    required String bookingDate,
    String? slotTime,
    int durationMinutes = 30,
    required int price,
  }) async {
    _maybeFail();
    bookingCreates++;
    return BackendBooking(
      id: 'bk-test',
      patientId: patientId,
      professionalId: professionalId,
      serviceType: serviceType,
      bookingDate: bookingDate,
      status: 'pending',
      price: price,
    );
  }

  @override
  Future<BackendBooking> createPackageSessionBooking({
    required String accessToken,
    required String packageId,
    required String bookingDate,
    required String slotTime,
    String sessionType = 'chat',
    int durationMinutes = 30,
  }) async {
    _maybeFail();
    bookingCreates++;
    return BackendBooking(
      id: 'bk-package',
      patientId: 'patient-1',
      professionalId: 'pro-1',
      serviceType: 'package_session',
      bookingDate: bookingDate,
      status: 'pending',
      price: 0,
      packageId: packageId,
    );
  }

  @override
  Future<BackendCarePackage> createCarePackage({
    required String accessToken,
    required String professionalId,
  }) async {
    _maybeFail();
    return BackendCarePackage(
      id: 'pkg-test',
      patientId: 'patient-1',
      professionalId: professionalId,
      status: 'pending_payment',
    );
  }

  @override
  Future<BackendPaymentResponse> createPayment({
    required String accessToken,
    required String bookingId,
    String paymentMethod = 'gopay',
  }) async {
    _maybeFail();
    paymentCreates++;
    return BackendPaymentResponse(
      payment: BackendPayment(
        id: 'pay-test',
        bookingId: bookingId,
        reference: 'REF-TEST',
        status: 'pending',
      ),
      breakdown: const <String, dynamic>{},
    );
  }

  @override
  Future<BackendPaymentStatus> getPaymentStatus({
    required String accessToken,
    required String reference,
  }) async {
    _maybeFail();
    return BackendPaymentStatus(
      payment: BackendPayment(
        id: 'pay-test',
        bookingId: 'bk-test',
        reference: reference,
        status: paymentStatusValue,
      ),
      sessionId: '',
    );
  }

  @override
  Future<List<BackendCarePackage>> listCarePackages({
    required String accessToken,
    String? patientId,
  }) async {
    _maybeFail();
    return carePackages;
  }

  @override
  Future<List<BackendCareSession>> listCareSessions({
    required String accessToken,
    String scope = 'all',
    String? patientId,
  }) async {
    _maybeFail();
    return careSessions;
  }

  @override
  Future<BackendCareSession> updateCareSession({
    required String accessToken,
    required String sessionId,
    String? status,
    String? cancelReason,
    String? meetingUrl,
    String? summaryForPatient,
    String? privateNote,
  }) async {
    _maybeFail();
    cancelSessionCalls++;
    return const BackendCareSession(
      id: 'session-1',
      patientId: 'patient-1',
      professionalId: 'pro-1',
      status: 'cancelled_by_patient',
    );
  }

  @override
  Future<BackendRescheduleResult> rescheduleCareSession({
    required String accessToken,
    required String sessionId,
    required String scheduledAt,
  }) async {
    _maybeFail();
    rescheduleCalls++;
    return const BackendRescheduleResult(
      session: BackendCareSession(
        id: 'session-1',
        patientId: 'patient-1',
        professionalId: 'pro-1',
        status: 'scheduled',
      ),
    );
  }

  @override
  Future<void> cancelPendingCarePackage({
    required String accessToken,
    required String packageId,
  }) async {
    _maybeFail();
    cancelPackageCalls++;
  }
}
