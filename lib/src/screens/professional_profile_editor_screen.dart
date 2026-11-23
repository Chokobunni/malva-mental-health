import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/professional_avatar.dart';
import '../time/wib.dart';

// ============================================================
// EDITOR PROFIL PROFESIONAL
// Profesional mengatur: foto (upload galeri / URL / AI avatar), bio,
// sub-spesialisasi, riwayat pendidikan, pengalaman, faskes, alamat.
// Perubahan langsung terlihat di halaman "Profesional Info" pasien.
// ============================================================

/// Daftar sub-spesialisasi yang tersedia. Profesional bisa memilih beberapa.
const _availableSpecialties = [
  ('depresi', 'Depresi'),
  ('ansietas', 'Ansietas / Kecemasan'),
  ('gangguan_tidur', 'Gangguan Tidur'),
  ('bipolar', 'Bipolar'),
  ('suicidal_ideation', 'Ideasi Suicidal'),
  ('stress_pasca_trauma', 'Stress Pasca Trauma (PTSD)'),
  ('kesehatan_jiwa_perempuan', 'Kesehatan Jiwa Perempuan'),
  ('trauma', 'Trauma'),
  ('pemulihan_krisis', 'Pemulihan Krisis'),
  ('kekerasan_domestik', 'Kekerasan Domestik'),
  ('pranikah', 'Konseling Pranikah'),
  ('seksualitas', 'Seksualitas'),
  ('cbt', 'CBT (Cognitive Behavioral Therapy)'),
  ('manajemen_stres', 'Manajemen Stres'),
  ('konseling_remaja', 'Konseling Remaja'),
  ('bullying', 'Bullying'),
  ('gangguan_makan', 'Gangguan Makan'),
  ('self_harm', 'Self-Harm'),
  ('relasi', 'Relasi / Pasangan'),
  ('burnout', 'Burnout'),
  ('pengembangan_diri', 'Pengembangan Diri'),
  ('kecemasan_sosial', 'Kecemasan Sosial'),
  ('parenting', 'Parenting'),
  ('grief', 'Grief / Duka'),
];

/// Ekstensi gambar yang didukung untuk unggahan foto profil.
const _allowedImageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

/// Ekstensi video yang didukung untuk unggahan video perkenalan.
const _allowedVideoExtensions = {'.mp4'};

class ProfessionalProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfessionalProfileEditorScreen({
    super.key,
    this.session,
    this.apiClient,
    this.onSaved,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  /// Dipanggil setelah profil berhasil disimpan. Dipakai pemanggil (mis.
  /// `_ProfessionalPortalSection`) untuk memuat ulang data profesional agar
  /// foto/nama baru langsung tampil tanpa menutup layar.
  final VoidCallback? onSaved;

  @override
  ConsumerState<ProfessionalProfileEditorScreen> createState() =>
      _ProfessionalProfileEditorScreenState();
}

class _ProfessionalProfileEditorScreenState
    extends ConsumerState<ProfessionalProfileEditorScreen> {
  BackendProfessionalCredential? _cred;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _loadError;
  bool _showAllSpecialties = false;
  bool _isBpjsSupported = false;
  String? _uploadedVideoName;
  bool _birthDateLoadError = false;
  String? _savedBirthDateKey;
  DateTime? _selectedBirthDate;
  final _birthDateController = TextEditingController();
  String? _successMessage;

  // Form fields
  final _bioController = TextEditingController();
  final _hospitalNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _photoUrlController = TextEditingController();
  final _videoUrlController = TextEditingController();
  final _yearsExpController = TextEditingController();
  final _strController = TextEditingController();
  final _sipController = TextEditingController();

  /// Controller TERPISAH untuk SIPP. Sebelumnya satu controller dipakai untuk
  /// SIP dan SIPP sekaligus, sehingga `sip_number` terhapus dan `sipp_number`
  /// terduplikasi setiap kali profil disimpan (bug 28 Okt 2026).
  final _sippController = TextEditingController();

  Set<String> _selectedSpecialties = {};
  List<Map<String, dynamic>> _education = [];

  // Status unggah media — true saat proses upload berlangsung.
  bool _isUploadingPhoto = false;
  bool _isUploadingVideo = false;

  // Berkas lokal yang baru dipilih (untuk pratinjau sebelum/sesudah upload).
  // Disimpan sebagai byte, bukan File — di web tidak ada berkas nyata.
  Uint8List? _localPhotoBytes;
  bool _hasLocalVideo = false;

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String? get _token => widget.session?.accessToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _birthDateController.dispose();
    _bioController.dispose();
    _hospitalNameController.dispose();
    _addressController.dispose();
    _photoUrlController.dispose();
    _videoUrlController.dispose();
    _yearsExpController.dispose();
    _strController.dispose();
    _sipController.dispose();
    _sippController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _loadError = 'Login dulu untuk mengedit profil.';
      });
      return;
    }
    try {
      final cred = await _api.getMyCredentials(accessToken: token);
      if (!mounted) return;
      await _loadBirthDate();
      if (!mounted) return;
      setState(() {
        _cred = cred;
        _populateFromCredential(cred);
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBirthDate() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      final profile = await _api.fetchUserProfile(accessToken: token);
      if (!mounted) return;
      setState(() {
        final birthDate = profile.birthDateTime;
        _savedBirthDateKey = birthDate == null ? null : wibDateKey(birthDate);
        _selectedBirthDate = birthDate;
        _birthDateController.text =
            birthDate == null ? '' : formatWibDate(birthDate);
        _birthDateLoadError = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _birthDateLoadError = true);
    }
  }

  Future<void> _pickBirthDate() async {
    final today = wibNow();
    final oldest = DateTime(1900);
    final current = _selectedBirthDate;
    final date = await showDatePicker(
      context: context,
      firstDate: oldest,
      lastDate: today,
      currentDate: today,
      initialDate: current != null &&
              !current.isBefore(oldest) &&
              !current.isAfter(today)
          ? DateTime(current.year, current.month, current.day)
          : null,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Pilih tanggal lahir',
    );
    if (date == null || !mounted) return;
    // The picker returns calendar components in the device zone.
    final birthDate = parseWibStored(
      "${date.year}-${date.month.toString().padLeft(2, '0')}-"
      "${date.day.toString().padLeft(2, '0')}",
    );
    if (birthDate == null) return;
    setState(() {
      _selectedBirthDate = birthDate;
      _birthDateController.text = formatWibDate(birthDate);
    });
  }

  void _populateFromCredential(BackendProfessionalCredential? cred) {
    if (cred == null) return;
    _bioController.text = cred.bio;
    _hospitalNameController.text = cred.hospitalName;
    _addressController.text = cred.addressDetails;
    _photoUrlController.text = cred.photoIntroUrl;
    _videoUrlController.text = cred.videoIntroUrl;
    _yearsExpController.text =
        cred.yearsExperience > 0 ? '${cred.yearsExperience}' : '';
    _strController.text = cred.strNumber;
    // SIP dan SIPP adalah dua field berbeda — jangan tertukar.
    _sipController.text = cred.sipNumber;
    _sippController.text = cred.sippNumber;
    _selectedSpecialties = Set<String>.from(cred.subSpecialties);
    _education = cred.education.map((row) => {...row}).toList();
    _isBpjsSupported = cred.isBpjsSupported;
  }

  Future<void> _save({bool saveBirthDate = false}) async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    setState(() {
      _isSaving = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final birthDate = _selectedBirthDate;
      final dateKey = birthDate == null ? null : wibDateKey(birthDate);
      if (saveBirthDate && dateKey != null && dateKey != _savedBirthDateKey) {
        await _api.updateMe(accessToken: token, dateOfBirth: dateKey);
        if (!mounted) return;
        _savedBirthDateKey = dateKey;
      }
      final updated = await _api.uploadProfessionalCredentials(
        accessToken: token,
        strNumber: _strController.text.trim(),
        sipNumber: _sipController.text.trim(),
        sippNumber: _sippController.text.trim(),
        specialization: _cred?.specialization ?? 'M.Psi',
        subSpecialties: _selectedSpecialties.toList(),
        // Kirim balik koordinat faskes yang sudah ada. Form editor tidak
        // punya kolom koordinat; tanpa ini setiap simpan mengosongkan
        // hospital_lat/lng (pertahanan berlapis di sisi klien — server juga
        // mempertahankan nilai lama bila field tidak dikirim).
        hospitalLat: _cred?.hospitalLat,
        hospitalLng: _cred?.hospitalLng,
        hospitalName: _hospitalNameController.text.trim(),
        addressDetails: _addressController.text.trim(),
        isBpjsSupported: _isBpjsSupported,
        bio: _bioController.text.trim(),
        photoIntroUrl: _photoUrlController.text.trim(),
        videoIntroUrl: _videoUrlController.text.trim(),
        education: _education,
      );
      if (!mounted) return;
      setState(() {
        _cred = updated;
        _isSaving = false;
        _successMessage = 'Profil berhasil disimpan.';
      });
      // Beri tahu layar lain (dashboard profesional & sisi pasien) bahwa
      // profil berubah, sehingga foto/nama baru langsung tampil di kedua sisi.
      ref.read(professionalProfileRevisionProvider.notifier).state++;
      final userId = updated.userId.isNotEmpty
          ? updated.userId
          : (widget.session?.backendUserId ?? '');
      if (userId.isNotEmpty) {
        ref.read(professionalProfileUpdatedIdProvider.notifier).state = userId;
      }
      widget.onSaved?.call();
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  /// Memilih foto dari galeri lalu mengunggahnya ke server.
  Future<void> _pickAndUploadPhoto() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Login dulu untuk mengunggah foto.');
      return;
    }
    try {
      final picker = ref.read(filePickerProvider);
      // Kompresi dikembalikan persis seperti versi lama: 1024×1024, kualitas 85
      // agar foto kamera 12 MP tidak melewati batas unggah backend.
      final picked = await picker.pick(
        'image',
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      // Validasi ekstensi sisi klien.
      final ext = '.' + picked.name.split('.').last.toLowerCase();
      if (!_allowedImageExtensions.contains(ext)) {
        setState(() => _error =
            'Format foto tidak didukung. Gunakan JPEG, PNG, atau WebP.');
        return;
      }

      setState(() {
        _isUploadingPhoto = true;
        _error = null;
        _localPhotoBytes = picked.bytes;
      });

      final url = await _api.uploadFile(
        accessToken: token,
        fileName: picked.name,
        bytes: picked.bytes,
        mimeType: picked.mimeType,
      );

      if (!mounted) return;
      setState(() {
        _photoUrlController.text = url;
        _isUploadingPhoto = false;
        _localPhotoBytes = null; // bersihkan setelah berhasil
      });
      // Simpan langsung agar foto baru tampil realtime di sisi pasien
      // (server menyiarkan event professional.profile.updated).
      await _save();
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
        _localPhotoBytes = null;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
        _localPhotoBytes = null;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  /// Memilih video dari galeri lalu mengunggahnya ke server.
  Future<void> _pickAndUploadVideo() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Login dulu untuk mengunggah video.');
      return;
    }
    try {
      final picker = ref.read(filePickerProvider);
      final picked = await picker.pick('video');
      if (picked == null || !mounted) return;

      // Validasi ekstensi sisi klien.
      final ext = '.' + picked.name.split('.').last.toLowerCase();
      if (!_allowedVideoExtensions.contains(ext)) {
        setState(() => _error = 'Format video tidak didukung. Gunakan MP4.');
        return;
      }

      setState(() {
        _isUploadingVideo = true;
        _error = null;
        _hasLocalVideo = true;
      });

      final url = await _api.uploadFile(
        accessToken: token,
        fileName: picked.name,
        bytes: picked.bytes,
        mimeType: picked.mimeType,
      );

      if (!mounted) return;
      setState(() {
        _videoUrlController.text = url;
        _uploadedVideoName = picked.name;
        _isUploadingVideo = false;
        _hasLocalVideo = false;
      });
      // Simpan langsung agar video intro baru tampil realtime di sisi pasien.
      await _save();
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingVideo = false;
        _hasLocalVideo = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingVideo = false;
        _hasLocalVideo = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  /// Menghasilkan avatar AI via DiceBear API menggunakan user ID sebagai seed.
  void _generateAiAvatar() {
    final userId = _cred?.userId ?? widget.session?.backendUserId ?? '';
    if (userId.isEmpty) {
      setState(() =>
          _error = 'User ID tidak tersedia untuk menghasilkan avatar AI.');
      return;
    }
    setState(() {
      _photoUrlController.text =
          'https://api.dicebear.com/9.x/notionists/svg?seed=$userId';
      _localPhotoBytes = null; // reset berkas lokal karena pakai URL eksternal
    });
  }

  void _addEducation() {
    setState(() {
      _education.add({'degree': '', 'school': '', 'year': wibNow().year});
    });
  }

  void _removeEducation(int index) {
    setState(() {
      _education.removeAt(index);
    });
  }

  void _updateEducation(int index, String field, String value) {
    _education[index][field] = value;
  }

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final busy = _isSaving || _isUploadingPhoto || _isUploadingVideo;
    final showForm = !_isLoading && _loadError == null;
    final visibleSpecialties = _showAllSpecialties
        ? _availableSpecialties
        : _availableSpecialties
            .where((entry) => _selectedSpecialties.contains(entry.$1))
            .take(6)
            .toList();
    final hiddenSpecialtyCount =
        _availableSpecialties.length - visibleSpecialties.length;
    return Scaffold(
      backgroundColor: light ? const Color(0xFFF8F7FB) : null,
      appBar: AppBar(
        title: const Text('Edit Profil Profesional'),
        centerTitle: true,
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: showForm
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null || _successMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error ?? _successMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _error == null
                              ? MalvaColors.plum
                              : MalvaColors.danger,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _save(saveBirthDate: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: MalvaColors.seed,
                      minimumSize: const Size(0, 50),
                      foregroundColor: Colors.white,
                    ),
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Menyimpan...' : 'Simpan Profil'),
                  ),
                ],
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    _section('Foto Profil & Identitas', [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEEF0F3)),
                        ),
                        child: Row(
                          children: [
                            Stack(clipBehavior: Clip.none, children: [
                              _buildPhotoPreview(),
                              Positioned(
                                  right: -3,
                                  bottom: -3,
                                  child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                          color: MalvaColors.plum,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2)),
                                      child: const Icon(
                                          Icons.camera_alt_outlined,
                                          color: Colors.white,
                                          size: 13))),
                            ]),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed:
                                        busy ? null : _pickAndUploadPhoto,
                                    style: _mediaButtonStyle,
                                    icon: const Icon(Icons.image_outlined,
                                        size: 19),
                                    label: Text(_isUploadingPhoto
                                        ? 'Mengunggah...'
                                        : 'Pilih Foto dari Galeri'),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text('JPG, PNG, WebP • maks. 5 MB',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF98A2AE))),
                                  TextButton.icon(
                                    onPressed: busy ? null : _generateAiAvatar,
                                    icon: const Icon(
                                        Icons.auto_awesome_outlined,
                                        size: 16),
                                    label: const Text('Buat avatar'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _field(
                        'Tanggal Lahir',
                        _birthDateController,
                        hint: 'DD/MM/YYYY',
                        readOnly: true,
                        onTap:
                            busy || _birthDateLoadError ? null : _pickBirthDate,
                        suffixIcon: const Icon(Icons.expand_more_rounded),
                      ),
                      if (_birthDateLoadError)
                        TextButton(
                          onPressed: busy ? null : _loadBirthDate,
                          child: const Text('Muat ulang tanggal lahir'),
                        ),
                    ]),
                    _section(
                        'Video Perkenalan',
                        [
                          if (_hasLocalVideo ||
                              _videoUrlController.text.isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FB),
                                border:
                                    Border.all(color: const Color(0xFFE9EDF1)),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(children: [
                                Container(
                                    width: 80,
                                    height: 52,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF3D0961),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: const Text('Video',
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          _uploadedVideoName ??
                                              'Video perkenalan',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 3),
                                      Text(
                                          _isUploadingVideo
                                              ? 'Mengunggah video...'
                                              : 'Tersimpan • Siap tampil',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF98A2AE))),
                                    ])),
                              ]),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : _pickAndUploadVideo,
                              style: _mediaButtonStyle,
                              icon: const Icon(Icons.videocam_outlined),
                              label: Text(_videoUrlController.text.isNotEmpty
                                  ? 'Ganti Video dari Galeri'
                                  : 'Pilih Video dari Galeri'),
                            ),
                          ),
                        ],
                        trailing: _videoUrlController.text.isNotEmpty
                            ? _statusPill('Terunggah', green: true)
                            : null),
                    _section(
                        'Bio / Overview',
                        [
                          _field(
                            'Deskripsi profesional',
                            _bioController,
                            hint: 'Ceritakan pengalaman dan fokus keahlianmu',
                            maxLines: 5,
                          ),
                        ],
                        trailing: const Text('Publik',
                            style: TextStyle(
                                color: Color(0xFF98A2AE), fontSize: 12))),
                    _section(
                        'Bidang Keahlian',
                        [
                          if (visibleSpecialties.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final (key, label) in visibleSpecialties)
                                  FilterChip(
                                    label: Text(label),
                                    visualDensity: VisualDensity.compact,
                                    selected:
                                        _selectedSpecialties.contains(key),
                                    selectedColor: const Color(0xFFEFE3F7),
                                    checkmarkColor: MalvaColors.plum,
                                    labelStyle: const TextStyle(
                                        color: MalvaColors.plum,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12),
                                    side: const BorderSide(
                                        color: Color(0xFFEADDF3)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    onSelected: busy
                                        ? null
                                        : (selected) => setState(() {
                                              if (selected) {
                                                _selectedSpecialties.add(key);
                                              } else {
                                                _selectedSpecialties
                                                    .remove(key);
                                              }
                                            }),
                                  ),
                              ],
                            ),
                          if (_showAllSpecialties ||
                              hiddenSpecialtyCount > 0) ...[
                            const Divider(),
                            Align(
                              alignment: Alignment.center,
                              child: TextButton.icon(
                                onPressed: () => setState(() =>
                                    _showAllSpecialties = !_showAllSpecialties),
                                icon: Icon(_showAllSpecialties
                                    ? Icons.expand_less
                                    : Icons.expand_more),
                                label: Text(_showAllSpecialties
                                    ? 'Lihat lebih sedikit'
                                    : 'Lihat $hiddenSpecialtyCount lainnya'),
                              ),
                            ),
                          ],
                        ],
                        trailing: _statusPill(
                            '${_selectedSpecialties.length} dipilih')),
                    _section('Riwayat Pendidikan', [
                      for (var i = 0; i < _education.length; i++) ...[
                        _EducationRow(
                          key: ObjectKey(_education[i]),
                          index: i + 1,
                          degree: _education[i]['degree']?.toString() ?? '',
                          school: _education[i]['school']?.toString() ?? '',
                          year: _education[i]['year']?.toString() ?? '',
                          onDegreeChanged: (v) =>
                              _updateEducation(i, 'degree', v),
                          onSchoolChanged: (v) =>
                              _updateEducation(i, 'school', v),
                          onYearChanged: (v) => _updateEducation(i, 'year', v),
                          onRemove: () => _removeEducation(i),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _addEducation,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          style: _mediaButtonStyle,
                          label: const Text('Tambah Pendidikan'),
                        ),
                      ),
                    ]),
                    _section('Pengalaman & Faskes', [
                      _field(
                        'Tahun pengalaman praktik',
                        _yearsExpController,
                        hint: 'Dikelola oleh admin',
                        readOnly: true,
                      ),
                      const SizedBox(height: 10),
                      _field('Nama faskes / tempat praktik',
                          _hospitalNameController),
                      const SizedBox(height: 10),
                      _field(
                          'Alamat faskes / tempat praktik', _addressController,
                          maxLines: 2),
                      const SizedBox(height: 18),
                      const Divider(color: Color(0xFFEEF0F3)),
                      const SizedBox(height: 6),
                      const Text('Layanan BPJS Kesehatan (Offline)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                          'Cantumkan apakah Anda menerima pasien BPJS untuk pemeriksaan tatap muka langsung di fasilitas kesehatan di atas.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF82909D),
                              height: 1.6)),
                      const SizedBox(height: 12),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _bpjsChoice(true, busy)),
                            const SizedBox(width: 10),
                            Expanded(child: _bpjsChoice(false, busy)),
                          ]),
                    ]),
                    _section('Lisensi & Legalitas', [
                      _field('Nomor STR', _strController),
                      const SizedBox(height: 10),
                      _field('Nomor SIP', _sipController,
                          hint: 'Masukkan nomor SIP'),
                      const SizedBox(height: 10),
                      _field('Nomor SIPP (bila ada)', _sippController,
                          hint: 'Masukkan nomor SIPP'),
                    ]),
                  ],
                ),
    );
  }

  Widget _statusPill(String label, {bool green = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: green ? const Color(0xFFECFBF5) : const Color(0xFFFAF4FD),
          borderRadius: BorderRadius.circular(30)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: green ? const Color(0xFF167A64) : MalvaColors.plum)));

  Widget _bpjsChoice(bool value, bool busy) {
    final selected = _isBpjsSupported == value;
    return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: busy ? null : () => setState(() => _isBpjsSupported = value),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 90),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFF0FCF8)
                    : const Color(0xFFF9FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    width: selected ? 1.5 : 1,
                    color: selected
                        ? const Color(0xFF36AD91)
                        : const Color(0xFFE7EAF0))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 19,
                  color: selected
                      ? const Color(0xFF119775)
                      : const Color(0xFFCBD3DB)),
              const SizedBox(width: 7),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(value ? 'Menerima BPJS' : 'Tidak Menerima',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                        value
                            ? 'Tampil lencana BPJS (Offline)'
                            : 'Hanya pasien umum/asuransi',
                        style: const TextStyle(
                            fontSize: 10,
                            height: 1.5,
                            color: Color(0xFF82909D))),
                  ])),
            ]),
          ),
        ));
  }

  Widget _section(String title, List<Widget> children, {Widget? trailing}) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (title) {
      'Foto Profil & Identitas' => Icons.account_circle_outlined,
      'Video Perkenalan' => Icons.videocam_outlined,
      'Bio / Overview' => Icons.description_outlined,
      'Bidang Keahlian' => Icons.auto_awesome_outlined,
      'Riwayat Pendidikan' => Icons.school_outlined,
      'Pengalaman & Faskes' => Icons.apartment_outlined,
      _ => Icons.verified_user_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : colors.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xFFECEBF2))),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFBF5FE),
                      borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, size: 20, color: MalvaColors.plum)),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface))),
              if (trailing != null) ...[const SizedBox(width: 6), trailing],
            ]),
            const SizedBox(height: 16),
            ...children,
          ]),
        ),
      ),
    );
  }

  ButtonStyle get _mediaButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: MalvaColors.seed,
        side: const BorderSide(color: Color(0xFFE6D6F0)),
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            onTap: onTap,
            maxLines: maxLines,
            decoration: _profileInput(
              hintText: hint,
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }

  /// Membangun widget pratinjau foto profil.
  /// Prioritas: berkas lokal yang sedang di-upload > URL jaringan > placeholder.
  Widget _buildPhotoPreview() {
    // Sedang mengunggah — tampilkan indikator loading.
    if (_isUploadingPhoto) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: MalvaColors.seed.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // Berkas lokal yang baru dipilih (sebelum/sesudah upload).
    if (_localPhotoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.memory(
          _localPhotoBytes!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder(),
        ),
      );
    }

    // URL jaringan (dari server atau DiceBear).
    final url = _photoUrlController.text.trim();
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ProfessionalPhoto(
          photoUrl: url,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          fallback: _photoPlaceholder(),
        ),
      );
    }

    return _photoPlaceholder();
  }

  /// Placeholder ketika belum ada foto.
  Widget _photoPlaceholder() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: MalvaColors.seed.withValues(alpha: 0.1),
      ),
      child: Center(
        child: (widget.session?.displayName ?? '').trim().isEmpty
            ? const Icon(Icons.person_outline_rounded,
                size: 36, color: MalvaColors.seed)
            : Padding(
                padding: const EdgeInsets.all(7),
                child: Text(widget.session!.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: MalvaColors.plum,
                        fontWeight: FontWeight.w700,
                        fontSize: 12))),
      ),
    );
  }
}

InputDecoration _profileInput({
  String? labelText,
  String? hintText,
  Widget? suffixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(17),
    borderSide: const BorderSide(color: Color(0xFFE4E9EE)),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    suffixIcon: suffixIcon,
    suffixIconColor: MalvaColors.plum,
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFF8F9FB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: border,
    enabledBorder: border,
  );
}

/// Baris pendidikan dengan TextEditingController yang diinisialisasi sekali.
class _EducationRow extends StatefulWidget {
  const _EducationRow({
    super.key,
    required this.index,
    required this.degree,
    required this.school,
    required this.year,
    required this.onDegreeChanged,
    required this.onSchoolChanged,
    required this.onYearChanged,
    required this.onRemove,
  });

  final int index;
  final String degree;
  final String school;
  final String year;
  final ValueChanged<String> onDegreeChanged;
  final ValueChanged<String> onSchoolChanged;
  final ValueChanged<String> onYearChanged;
  final VoidCallback onRemove;

  @override
  State<_EducationRow> createState() => _EducationRowState();
}

class _EducationRowState extends State<_EducationRow> {
  late final TextEditingController _degreeCtrl;
  late final TextEditingController _schoolCtrl;
  late final TextEditingController _yearCtrl;

  @override
  void initState() {
    super.initState();
    _degreeCtrl = TextEditingController(text: widget.degree);
    _schoolCtrl = TextEditingController(text: widget.school);
    _yearCtrl = TextEditingController(text: widget.year);
  }

  @override
  void dispose() {
    _degreeCtrl.dispose();
    _schoolCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFF9FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECEEF2))),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Text('PENDIDIKAN #${widget.index}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: MalvaColors.plum,
                      fontWeight: FontWeight.w700))),
          IconButton(
              onPressed: widget.onRemove,
              tooltip: 'Hapus pendidikan',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFF98A2AE))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              flex: 3,
              child: TextField(
                  controller: _degreeCtrl,
                  style: const TextStyle(fontSize: 13),
                  onChanged: widget.onDegreeChanged,
                  decoration: _profileInput(hintText: 'Gelar'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _yearCtrl,
                  style: const TextStyle(fontSize: 13),
                  onChanged: widget.onYearChanged,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: _profileInput(hintText: 'Tahun'))),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: _schoolCtrl,
            style: const TextStyle(fontSize: 13),
            onChanged: widget.onSchoolChanged,
            decoration: _profileInput(hintText: 'Institusi')),
      ]),
    );
  }
}
