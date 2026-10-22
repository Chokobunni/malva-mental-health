import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Revisi data profil profesional.
///
/// Nilainya dinaikkan setiap kali server mengirim event realtime
/// `professional.profile.updated` lewat WebSocket. Layar pasien yang
/// menampilkan foto/video intro profesional mendengarkan provider ini untuk
/// memuat ulang data secara otomatis tanpa refresh manual.
final professionalProfileRevisionProvider = StateProvider<int>((ref) => 0);

/// ID pengguna profesional yang terakhir mengubah profilnya (bila diketahui).
///
/// Berguna untuk memuat ulang hanya data profesional terkait. Bernilai string
/// kosong bila belum ada event.
final professionalProfileUpdatedIdProvider = StateProvider<String>((ref) => '');
