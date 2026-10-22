import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';

// ============================================================
// EDITOR PROFIL PROFESIONAL
// Profesional mengatur: foto (URL), bio, sub-spesialisasi,
// riwayat pendidikan, pengalaman, faskes, alamat.
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
                    // Foto profil URL
                    const SectionLabel('Foto Profil'),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _photoUrlController,
                            decoration: const InputDecoration(
                              labelText: 'URL Foto Profil',
                              hintText:
                                  'https://contoh.com/foto.jpg atau URL DiceBear',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tips: gunakan https://api.dicebear.com/9.x/notionists/svg?seed=namaunik '
                            'untuk avatar AI gratis, atau upload foto ke cloud storage dan paste URL-nya.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          if (_photoUrlController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: ClipOval(
                                child: Image.network(
                                  _photoUrlController.text,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const CircleAvatar(
                                    radius: 40,
                                    child: Icon(Icons.broken_image_rounded),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Bio / Overview
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

                    // Sub-spesialisasi
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

                    // Riwayat Pendidikan
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

                    // Pengalaman & Faskes
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

                    // Lisensi
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

                    // Video intro URL
                    const SectionLabel('Video Perkenalan'),
                    SoftCard(
                      child: TextField(
                        controller: _videoUrlController,
                        decoration: const InputDecoration(
                          labelText: 'URL Video Intro',
                          hintText:
                              'https://youtube.com/watch?v=... atau URL lain',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

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
