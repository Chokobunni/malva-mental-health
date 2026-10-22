import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';

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
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;

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

  Set<String> _selectedSpecialties = {};
  List<Map<String, dynamic>> _education = [];

  // Status unggah media — true saat proses upload berlangsung.
  bool _isUploadingPhoto = false;
  bool _isUploadingVideo = false;

  // Berkas lokal yang baru dipilih (untuk pratinjau sebelum/sesudah upload).
  File? _localPhotoFile;
  File? _localVideoFile;

  final _imagePicker = ImagePicker();

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String? get _token => widget.session?.accessToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _hospitalNameController.dispose();
    _addressController.dispose();
    _photoUrlController.dispose();
    _videoUrlController.dispose();
    _yearsExpController.dispose();
    _strController.dispose();
    _sipController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Login dulu untuk mengedit profil.';
      });
      return;
    }
    try {
      final cred = await _api.getMyCredentials(accessToken: token);
      if (!mounted) return;
      setState(() {
        _cred = cred;
        _populateFromCredential(cred);
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
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
    _sipController.text = cred.sippNumber;
    _selectedSpecialties = Set<String>.from(cred.subSpecialties);
    _education = List<Map<String, dynamic>>.from(cred.education);
  }

  Future<void> _save() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    setState(() {
      _isSaving = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final updated = await _api.uploadProfessionalCredentials(
        accessToken: token,
        strNumber: _strController.text.trim(),
        sipNumber: _sipController.text.trim(),
        sippNumber: _sipController.text.trim(),
        specialization: _cred?.specialization ?? 'M.Psi',
        subSpecialties: _selectedSpecialties.toList(),
        hospitalName: _hospitalNameController.text.trim(),
        addressDetails: _addressController.text.trim(),
        isBpjsSupported: _cred?.isBpjsSupported ?? false,
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
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Validasi ekstensi sisi klien.
      final ext = '.' + picked.name.split('.').last.toLowerCase();
      if (!_allowedImageExtensions.contains(ext)) {
        setState(() => _error = 'Format foto tidak didukung. Gunakan JPEG, PNG, atau WebP.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = true;
        _error = null;
        _localPhotoFile = File(picked.path);
      });

      final url = await _api.uploadFile(
        accessToken: token,
        filePath: picked.path,
      );

      if (!mounted) return;
      setState(() {
        _photoUrlController.text = url;
        _isUploadingPhoto = false;
        _localPhotoFile = null; // bersihkan setelah berhasil
      });
      // Simpan langsung agar foto baru tampil realtime di sisi pasien
      // (server menyiarkan event professional.profile.updated).
      await _save();
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
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
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      // Validasi ekstensi sisi klien.
      final ext = '.' + picked.name.split('.').last.toLowerCase();
      if (!_allowedVideoExtensions.contains(ext)) {
        setState(() => _error = 'Format video tidak didukung. Gunakan MP4.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _isUploadingVideo = true;
        _error = null;
        _localVideoFile = File(picked.path);
      });

      final url = await _api.uploadFile(
        accessToken: token,
        filePath: picked.path,
      );

      if (!mounted) return;
      setState(() {
        _videoUrlController.text = url;
        _isUploadingVideo = false;
        _localVideoFile = null;
      });
      // Simpan langsung agar video intro baru tampil realtime di sisi pasien.
      await _save();
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingVideo = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingVideo = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  /// Menghasilkan avatar AI via DiceBear API menggunakan user ID sebagai seed.
  void _generateAiAvatar() {
    final userId = _cred?.userId ?? widget.session?.backendUserId ?? '';
    if (userId.isEmpty) {
      setState(() => _error = 'User ID tidak tersedia untuk menghasilkan avatar AI.');
      return;
    }
    setState(() {
      _photoUrlController.text =
          'https://api.dicebear.com/9.x/notionists/svg?seed=$userId';
      _localPhotoFile = null; // reset berkas lokal karena pakai URL eksternal
    });
  }

  void _addEducation() {
    setState(() {
      _education.add({'degree': '', 'school': '', 'year': DateTime.now().year});
    });
  }

  void _removeEducation(int index) {
    setState(() {
      _education.removeAt(index);
    });
  }

  void _updateEducation(int index, String field, String value) {
    setState(() {
      _education[index] = {..._education[index], field: value};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profil Profesional'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          if (_successMessage != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  _successMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _cred == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
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
                    // ── Foto Profil ──────────────────────────────────────
                    const SectionLabel('Foto Profil'),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Pratinjau foto: berkas lokal > URL jaringan > kosong
                          Center(
                            child: _buildPhotoPreview(),
                          ),
                          const SizedBox(height: 12),

                          // Tombol aksi: pilih dari galeri + generate AI avatar
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    _isUploadingPhoto ? null : _pickAndUploadPhoto,
                                icon: _isUploadingPhoto
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.photo_library_rounded,
                                        size: 18),
                                label: Text(_isUploadingPhoto
                                    ? 'Mengunggah...'
                                    : 'Pilih dari Galeri'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _generateAiAvatar,
                                icon: const Icon(Icons.auto_awesome_rounded,
                                    size: 18),
                                label: const Text('Generate AI Avatar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Bio / Overview ───────────────────────────────────
                    const SectionLabel('Bio / Overview'),
                    SoftCard(
                      child: TextField(
                        controller: _bioController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Deskripsi profesional',
                          hintText:
                              'Ceritakan pengalaman, pendekatan terapi, dan fokus keahlianmu...',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Sub-spesialisasi ─────────────────────────────────
                    const SectionLabel('Bidang Keahlian'),
                    SoftCard(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (key, label) in _availableSpecialties)
                            FilterChip(
                              label: Text(label),
                              selected: _selectedSpecialties.contains(key),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedSpecialties.add(key);
                                  } else {
                                    _selectedSpecialties.remove(key);
                                  }
                                });
                              },
                              selectedColor:
                                  MalvaColors.seed.withValues(alpha: 0.2),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Riwayat Pendidikan ───────────────────────────────
                    const SectionLabel('Riwayat Pendidikan'),
                    SoftCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < _education.length; i++) ...[
                            _EducationRow(
                              key: ValueKey('edu-$i-${_education[i].hashCode}'),
                              degree: _education[i]['degree']?.toString() ?? '',
                              school: _education[i]['school']?.toString() ?? '',
                              year: _education[i]['year']?.toString() ?? '',
                              onDegreeChanged: (v) =>
                                  _updateEducation(i, 'degree', v),
                              onSchoolChanged: (v) =>
                                  _updateEducation(i, 'school', v),
                              onYearChanged: (v) =>
                                  _updateEducation(i, 'year', v),
                              onRemove: () => _removeEducation(i),
                            ),
                            if (i < _education.length - 1)
                              const Divider(height: 16),
                          ],
                          OutlinedButton.icon(
                            onPressed: _addEducation,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Tambah Pendidikan'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Pengalaman & Faskes ──────────────────────────────
                    const SectionLabel('Pengalaman & Faskes'),
                    SoftCard(
                      child: Column(
                        children: [
                          TextField(
                            controller: _yearsExpController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Tahun pengalaman praktik'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _hospitalNameController,
                            decoration: const InputDecoration(
                                labelText: 'Nama faskes / tempat praktik'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                                labelText: 'Alamat faskes / tempat praktik'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Lisensi ──────────────────────────────────────────
                    const SectionLabel('Lisensi'),
                    SoftCard(
                      child: Column(
                        children: [
                          TextField(
                            controller: _strController,
                            decoration:
                                const InputDecoration(labelText: 'Nomor STR'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _sipController,
                            decoration: const InputDecoration(
                                labelText: 'Nomor SIP / SIPP'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Video Perkenalan ─────────────────────────────────
                    const SectionLabel('Video Perkenalan'),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tombol pilih video dari galeri
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isUploadingVideo
                                      ? null
                                      : _pickAndUploadVideo,
                                  icon: _isUploadingVideo
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(
                                          Icons.video_library_rounded,
                                          size: 18),
                                  label: Text(_isUploadingVideo
                                      ? 'Mengunggah video...'
                                      : 'Pilih Video dari Galeri'),
                                ),
                              ),
                            ],
                          ),
                          // Pratinjau thumbnail video lokal
                          if (_localVideoFile != null) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                width: 120,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: MalvaColors.seed.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(Icons.videocam_rounded,
                                      size: 32, color: MalvaColors.seed),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Error & Save ─────────────────────────────────────
                    if (_error != null) ...[
                      Text(_error!,
                          style: const TextStyle(
                              color: MalvaColors.danger,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                    ],

                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_isSaving ? 'Menyimpan...' : 'Simpan Profil'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  /// Membangun widget pratinjau foto profil.
  /// Prioritas: berkas lokal yang sedang di-upload > URL jaringan > placeholder.
  Widget _buildPhotoPreview() {
    // Sedang mengunggah — tampilkan indikator loading.
    if (_isUploadingPhoto) {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MalvaColors.seed.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // Berkas lokal yang baru dipilih (sebelum/sesudah upload).
    if (_localPhotoFile != null) {
      return ClipOval(
        child: Image.file(
          _localPhotoFile!,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder(),
        ),
      );
    }

    // URL jaringan (dari server atau DiceBear).
    final url = _photoUrlController.text.trim();
    if (url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder(),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MalvaColors.seed.withValues(alpha: 0.1),
              ),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      );
    }

    return _photoPlaceholder();
  }

  /// Placeholder ketika belum ada foto.
  Widget _photoPlaceholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MalvaColors.seed.withValues(alpha: 0.1),
      ),
      child: const Center(
        child: Icon(Icons.person_outline_rounded,
            size: 40, color: MalvaColors.seed),
      ),
    );
  }
}

/// Baris pendidikan dengan TextEditingController yang diinisialisasi sekali.
class _EducationRow extends StatefulWidget {
  const _EducationRow({
    super.key,
    required this.degree,
    required this.school,
    required this.year,
    required this.onDegreeChanged,
    required this.onSchoolChanged,
    required this.onYearChanged,
    required this.onRemove,
  });

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _degreeCtrl,
            onChanged: widget.onDegreeChanged,
            decoration: const InputDecoration(
                labelText: 'Gelar', hintText: 'Sp.KJ, M.Psi, S.Psi'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: _schoolCtrl,
            onChanged: widget.onSchoolChanged,
            decoration: const InputDecoration(
                labelText: 'Institusi', hintText: 'FKUI, UNPAD, UGM'),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: TextField(
            controller: _yearCtrl,
            onChanged: widget.onYearChanged,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Tahun'),
          ),
        ),
        IconButton(
          onPressed: widget.onRemove,
          icon: const Icon(Icons.close_rounded, color: MalvaColors.danger),
        ),
      ],
    );
  }
}
