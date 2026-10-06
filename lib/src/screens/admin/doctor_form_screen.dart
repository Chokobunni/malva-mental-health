import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';

const _dayNames = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];

/// Form tambah / edit dokter (khusus admin).
/// Mengatur profil, spesialisasi, jadwal praktik, dan paket harga.
class DoctorFormScreen extends ConsumerStatefulWidget {
  const DoctorFormScreen({
    super.key,
    required this.apiClient,
    required this.accessToken,
    this.userId,
    this.displayName,
  });

  final MalvaApiClient apiClient;
  final String accessToken;
  final String? userId;
  final String? displayName;

  bool get isEdit => userId != null && userId!.isNotEmpty;

  @override
  ConsumerState<DoctorFormScreen> createState() => _DoctorFormScreenState();
}

class _ScheduleRow {
  int day;
  String start;
  String end;
  int duration;
  _ScheduleRow(
      {required this.day,
      required this.start,
      required this.end,
      required this.duration});
}

class _PackageRow {
  int sessions;
  int days;
  int price;
  String label;
  _PackageRow(
      {required this.sessions,
      required this.days,
      required this.price,
      required this.label});
}

class _DoctorFormScreenState extends ConsumerState<DoctorFormScreen> {
  bool _loading = false;
  bool _saving = false;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _profId = TextEditingController();
  String _spec = 'Sp.KJ';
  final _subSpec = TextEditingController();
  final _hospital = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool _bpjs = false;
  final _bio = TextEditingController();
  final _years = TextEditingController();
  final _price = TextEditingController();
  final _str = TextEditingController();
  final _sip = TextEditingController();
  final _sipp = TextEditingController();
  final _photo = TextEditingController();
  final _video = TextEditingController();
  final _education = TextEditingController();

  int _newDay = 1;
  final _newStart = TextEditingController(text: '09:00');
  final _newEnd = TextEditingController(text: '12:00');
  final _newDur = TextEditingController(text: '30');
  final _schedules = <_ScheduleRow>[];

  final _pkgSessions = TextEditingController(text: '1');
  final _pkgDays = TextEditingController(text: '7');
  final _pkgPrice = TextEditingController(text: '199000');
  final _pkgLabel = TextEditingController(text: '7 Days Continuous Care');
  final _packages = <_PackageRow>[];

  @override
  void initState() {
    super.initState();
    if (widget.displayName != null) _name.text = widget.displayName!;
    if (widget.isEdit) _loadDoctor();
  }

  @override
  void dispose() {
    for (final c in [
      _email,
      _password,
      _name,
      _profId,
      _subSpec,
      _hospital,
      _address,
      _lat,
      _lng,
      _bio,
      _years,
      _price,
      _str,
      _sip,
      _sipp,
      _photo,
      _video,
      _education,
      _newStart,
      _newEnd,
      _newDur,
      _pkgSessions,
      _pkgDays,
      _pkgPrice,
      _pkgLabel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDoctor() async {
    setState(() => _loading = true);
    try {
      final data = await widget.apiClient.getAdminDoctor(
        accessToken: widget.accessToken,
        userId: widget.userId!,
      );
      if (!mounted) return;
      final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? {};
      final cred = (data['credential'] as Map?)?.cast<String, dynamic>() ?? {};
      _name.text = user['display_name']?.toString() ?? _name.text;
      _spec = cred['specialization']?.toString() == 'M.Psi' ? 'M.Psi' : 'Sp.KJ';
      _subSpec.text = ((cred['sub_specialties'] as List?) ?? []).join(', ');
      _hospital.text = cred['hospital_name']?.toString() ?? '';
      _address.text = cred['address_details']?.toString() ?? '';
      _lat.text = cred['hospital_lat']?.toString() ?? '';
      _lng.text = cred['hospital_lng']?.toString() ?? '';
      _bpjs = cred['is_bpjs_supported'] == true;
      _bio.text = cred['bio']?.toString() ?? '';
      _years.text = cred['years_experience']?.toString() ?? '';
      _price.text = cred['price_from']?.toString() ?? '';
      _str.text = cred['str_number']?.toString() ?? '';
      _sip.text = cred['sip_number']?.toString() ?? '';
      _sipp.text = cred['sipp_number']?.toString() ?? '';
      _photo.text = cred['photo_intro_url']?.toString() ?? '';
      _video.text = cred['video_intro_url']?.toString() ?? '';
      _education.text = ((cred['education'] as List?) ?? [])
          .map((e) => e is Map
              ? (e['title'] ?? e['label'] ?? e.toString()).toString()
              : e.toString())
          .join('\n');
      _schedules.clear();
      for (final s in (data['schedules'] as List?) ?? []) {
        final m = (s as Map).cast<String, dynamic>();
        _schedules.add(_ScheduleRow(
          day: (m['day_of_week'] as num?)?.toInt() ?? 1,
          start: (m['start_time']?.toString() ?? '09:00').substring(0, 5),
          end: (m['end_time']?.toString() ?? '12:00').substring(0, 5),
          duration: (m['slot_duration_minutes'] as num?)?.toInt() ?? 30,
        ));
      }
      _packages.clear();
      for (final p in (data['packages'] as List?) ?? []) {
        final m = (p as Map).cast<String, dynamic>();
        _packages.add(_PackageRow(
          sessions: (m['package_sessions'] as num?)?.toInt() ?? 1,
          days: (m['package_duration_days'] as num?)?.toInt() ?? 7,
          price: (m['price'] as num?)?.toInt() ?? 0,
          label: m['label']?.toString() ?? '',
        ));
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is MalvaApiException
                ? e.message
                : 'Gagal memuat data dokter.')),
      );
      Navigator.pop(context);
    }
  }

  Map<String, Object?> _credentialsBody() {
    double? lat = double.tryParse(_lat.text.trim());
    double? lng = double.tryParse(_lng.text.trim());
    return {
      'str_number': _str.text.trim(),
      'sip_number': _sip.text.trim(),
      'sipp_number': _sipp.text.trim(),
      'specialization': _spec,
      'sub_specialties': _subSpec.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      if (lat != null) 'hospital_lat': lat,
      if (lng != null) 'hospital_lng': lng,
      'hospital_name': _hospital.text.trim(),
      'address_details': _address.text.trim(),
      'is_bpjs_supported': _bpjs,
      'photo_intro_url': _photo.text.trim(),
      'video_intro_url': _video.text.trim(),
      'bio': _bio.text.trim(),
      'education': _education.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => {'title': e})
          .toList(),
      'years_experience': int.tryParse(_years.text.trim()) ?? 0,
      'price_from': int.tryParse(_price.text.trim()) ?? 0,
    };
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _snack('Nama dokter wajib diisi.');
      return;
    }
    if (!widget.isEdit) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
        _snack('Format email tidak valid.');
        return;
      }
      if (_password.text.length < 8) {
        _snack('Password akun dokter minimal 8 karakter.');
        return;
      }
      if (!RegExp(r'^\d{16}$').hasMatch(_profId.text.trim())) {
        _snack('ID profesional harus tepat 16 digit angka.');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      if (widget.isEdit) {
        await widget.apiClient.updateDoctor(
          accessToken: widget.accessToken,
          userId: widget.userId!,
          displayName: _name.text.trim(),
          credentials: _credentialsBody(),
          schedules: [
            for (final s in _schedules)
              {
                'day_of_week': s.day,
                'start_time': s.start,
                'end_time': s.end,
                'slot_duration_minutes': s.duration,
              },
          ],
          packages: [
            for (final p in _packages)
              {
                'package_sessions': p.sessions,
                'package_duration_days': p.days,
                'price': p.price,
                'label': p.label,
              },
          ],
        );
      } else {
        await widget.apiClient.createDoctor(
          accessToken: widget.accessToken,
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
          professionalId: _profId.text,
          credentials: _credentialsBody(),
          schedules: [
            for (final s in _schedules)
              {
                'day_of_week': s.day,
                'start_time': s.start,
                'end_time': s.end,
                'slot_duration_minutes': s.duration,
              },
          ],
          packages: [
            for (final p in _packages)
              {
                'package_sessions': p.sessions,
                'package_duration_days': p.days,
                'price': p.price,
                'label': p.label,
              },
          ],
        );
      }
      if (!mounted) return;
      _snack(widget.isEdit
          ? 'Dokter diperbarui.'
          : 'Dokter ditambahkan & terverifikasi.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack(e is MalvaApiException ? e.message : 'Gagal menyimpan.');
      setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(widget.isEdit ? 'Edit Dokter' : 'Tambah Dokter')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (!widget.isEdit) ...[
                  const SectionLabel('Akun Login'),
                  TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Email akun',
                          prefixIcon: Icon(Icons.email_rounded))),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText:
                              'Password akun (min. 8, besar+kecil+angka+simbol)',
                          prefixIcon: Icon(Icons.lock_rounded))),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _profId,
                      keyboardType: TextInputType.number,
                      maxLength: 16,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'ID profesional (16 digit)',
                          prefixIcon: Icon(Icons.verified_user_rounded),
                          counterText: '')),
                  const SizedBox(height: 10),
                ],
                const SectionLabel('Profil'),
                TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Nama (cth: dr. Ayu Sp.KJ)',
                        prefixIcon: Icon(Icons.badge_rounded))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _spec,
                  decoration: const InputDecoration(
                      labelText: 'Spesialisasi',
                      prefixIcon: Icon(Icons.school_rounded)),
                  items: const [
                    DropdownMenuItem(
                        value: 'Sp.KJ',
                        child: Text('Sp.KJ — Psikiater (bisa resep)')),
                    DropdownMenuItem(
                        value: 'M.Psi',
                        child: Text('M.Psi — Psikolog (terapi)')),
                    DropdownMenuItem(
                        value: 'Sp.Psi',
                        child: Text('Sp.Psi — Psikolog spesialis')),
                    DropdownMenuItem(
                        value: 'Sp.An',
                        child: Text('Sp.An — Psikiater subspesialis lain')),
                  ],
                  onChanged: (v) => setState(() => _spec = v ?? _spec),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: _subSpec,
                    decoration: const InputDecoration(
                        labelText: 'Sub-spesialisasi (pisah koma)',
                        hintText: 'Kecemasan, Depresi, Trauma',
                        prefixIcon: Icon(Icons.tag_rounded))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: _years,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Pengalaman (thn)'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: _price,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Harga mulai (Rp)'))),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Bio singkat',
                        prefixIcon: Icon(Icons.info_rounded))),
                const SizedBox(height: 10),
                TextField(
                    controller: _education,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Pendidikan (1 baris = 1 riwayat)',
                        prefixIcon: Icon(Icons.history_edu_rounded))),
                const SizedBox(height: 18),
                const SectionLabel('Tempat Praktik'),
                TextField(
                    controller: _hospital,
                    decoration: const InputDecoration(
                        labelText: 'Rumah sakit / klinik',
                        prefixIcon: Icon(Icons.local_hospital_rounded))),
                const SizedBox(height: 10),
                TextField(
                    controller: _address,
                    decoration: const InputDecoration(
                        labelText: 'Alamat detail',
                        prefixIcon: Icon(Icons.place_rounded))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: _lat,
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true, decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Latitude'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: _lng,
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true, decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Longitude'))),
                  ],
                ),
                SwitchListTile(
                  title: const Text('Mendukung BPJS'),
                  value: _bpjs,
                  onChanged: (v) => setState(() => _bpjs = v),
                ),
                const SizedBox(height: 10),
                const SectionLabel('Legalitas & Media'),
                TextField(
                    controller: _str,
                    decoration: const InputDecoration(labelText: 'No. STR')),
                const SizedBox(height: 10),
                TextField(
                    controller: _sip,
                    decoration: const InputDecoration(labelText: 'No. SIP')),
                const SizedBox(height: 10),
                TextField(
                    controller: _sipp,
                    decoration: const InputDecoration(labelText: 'No. SIPP')),
                const SizedBox(height: 10),
                TextField(
                    controller: _photo,
                    decoration: const InputDecoration(
                        labelText: 'URL foto (opsional)')),
                const SizedBox(height: 10),
                TextField(
                    controller: _video,
                    decoration: const InputDecoration(
                        labelText: 'URL video perkenalan (opsional)')),
                const SizedBox(height: 18),
                const SectionLabel('Jadwal Praktik'),
                for (var i = 0; i < _schedules.length; i++)
                  Card(
                    child: ListTile(
                      title: Text(
                          '${_dayNames[_schedules[i].day]} ${_schedules[i].start}–${_schedules[i].end}'),
                      subtitle: Text('Slot ${_schedules[i].duration} mnt'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_rounded,
                            color: MalvaColors.danger),
                        onPressed: () => setState(() => _schedules.removeAt(i)),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _newDay,
                        decoration: const InputDecoration(labelText: 'Hari'),
                        items: [
                          for (var d = 0; d < 7; d++)
                            DropdownMenuItem(
                                value: d, child: Text(_dayNames[d])),
                        ],
                        onChanged: (v) => setState(() => _newDay = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _newStart,
                            decoration:
                                const InputDecoration(labelText: 'Mulai'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _newEnd,
                            decoration:
                                const InputDecoration(labelText: 'Selesai'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _newDur,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'mnt'))),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    if (!RegExp(r'^\d{2}:\d{2}$')
                            .hasMatch(_newStart.text.trim()) ||
                        !RegExp(r'^\d{2}:\d{2}$')
                            .hasMatch(_newEnd.text.trim())) {
                      _snack('Format jam HH:MM, cth 09:00.');
                      return;
                    }
                    setState(() => _schedules.add(_ScheduleRow(
                          day: _newDay,
                          start: _newStart.text.trim(),
                          end: _newEnd.text.trim(),
                          duration: int.tryParse(_newDur.text.trim()) ?? 30,
                        )));
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah jadwal'),
                ),
                const SizedBox(height: 18),
                const SectionLabel('Paket Harga'),
                for (var i = 0; i < _packages.length; i++)
                  Card(
                    child: ListTile(
                      title: Text(_packages[i].label.isEmpty
                          ? '${_packages[i].sessions} sesi / ${_packages[i].days} hari'
                          : _packages[i].label),
                      subtitle: Text(
                          '${_packages[i].sessions} sesi • ${_packages[i].days} hari • Rp${_packages[i].price}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_rounded,
                            color: MalvaColors.danger),
                        onPressed: () => setState(() => _packages.removeAt(i)),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: _pkgSessions,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Sesi'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _pkgDays,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Hari'))),
                    const SizedBox(width: 8),
                    Expanded(
                        flex: 2,
                        child: TextField(
                            controller: _pkgPrice,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Harga (Rp)'))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: _pkgLabel,
                    decoration:
                        const InputDecoration(labelText: 'Label paket')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _packages.add(_PackageRow(
                        sessions: int.tryParse(_pkgSessions.text.trim()) ?? 1,
                        days: int.tryParse(_pkgDays.text.trim()) ?? 7,
                        price: int.tryParse(_pkgPrice.text.trim()) ?? 0,
                        label: _pkgLabel.text.trim(),
                      ))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah paket'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving
                      ? 'Menyimpan...'
                      : widget.isEdit
                          ? 'Simpan Perubahan'
                          : 'Tambah Dokter'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
