import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// ============================================================
// LOKASI PASIEN — izin diminta saat aplikasi dibuka.
// Dipakai untuk menghitung jarak faskes (km) di Cari Profesional.
// Gagal izin/GPS bukan error: UI menampilkan kartu tanpa jarak.
// ============================================================

class PatientLocationState {
  const PatientLocationState({
    this.position,
    this.permissionDenied = false,
    this.serviceDisabled = false,
    this.resolving = false,
  });

  final Position? position;
  final bool permissionDenied;
  final bool serviceDisabled;
  final bool resolving;

  PatientLocationState copyWith({
    Position? position,
    bool? permissionDenied,
    bool? serviceDisabled,
    bool? resolving,
    bool clearPosition = false,
  }) {
    return PatientLocationState(
      position: clearPosition ? null : (position ?? this.position),
      permissionDenied: permissionDenied ?? this.permissionDenied,
      serviceDisabled: serviceDisabled ?? this.serviceDisabled,
      resolving: resolving ?? this.resolving,
    );
  }
}

class PatientLocationNotifier extends StateNotifier<PatientLocationState> {
  PatientLocationNotifier() : super(const PatientLocationState());

  /// Dipanggil sekali saat aplikasi dibuka (dari splash).
  Future<void> resolveOnStartup() async {
    if (state.resolving) return;
    state = state.copyWith(resolving: true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          resolving: false,
          permissionDenied: true,
          clearPosition: true,
        );
        return;
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        state = state.copyWith(
          resolving: false,
          serviceDisabled: true,
          clearPosition: true,
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      state = state.copyWith(
        position: position,
        resolving: false,
        permissionDenied: false,
        serviceDisabled: false,
      );
    } on Object {
      // Timeout / error GPS — jangan gagalkan aplikasi.
      state = state.copyWith(resolving: false, clearPosition: true);
    }
  }

  /// Coba lagi dari halaman Cari Profesional (mis. user baru izinkan).
  Future<void> retry() async {
    if (state.resolving) return;
    state = const PatientLocationState();
    await resolveOnStartup();
  }
}

final patientLocationProvider =
    StateNotifierProvider<PatientLocationNotifier, PatientLocationState>(
  (ref) => PatientLocationNotifier(),
);

/// Haversine jarak km antara dua titik.
double? distanceKmBetween({
  required double? fromLat,
  required double? fromLng,
  required double? toLat,
  required double? toLng,
}) {
  if (fromLat == null || fromLng == null || toLat == null || toLng == null) {
    return null;
  }
  if (![fromLat, fromLng, toLat, toLng].every((v) => v.isFinite) ||
      fromLat.abs() > 90 ||
      toLat.abs() > 90 ||
      fromLng.abs() > 180 ||
      toLng.abs() > 180) return null;
  const earthRadius = 6371.0;
  final dLat = _deg2rad(toLat - fromLat);
  final dLng = _deg2rad(toLng - fromLng);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(fromLat)) *
          math.cos(_deg2rad(toLat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final bounded = a.clamp(0.0, 1.0);
  final c = 2 * math.atan2(math.sqrt(bounded), math.sqrt(1 - bounded));
  return double.parse((earthRadius * c).toStringAsFixed(1));
}

double _deg2rad(double deg) => deg * (math.pi / 180.0);

String professionalDistanceLabel(
    {required double? km,
    required double? hospitalLat,
    required double? hospitalLng}) {
  if (km != null) return '${km.toStringAsFixed(1)} km';
  return hospitalLat == null || hospitalLng == null
      ? 'Lokasi praktik belum tersedia'
      : 'Lokasi pasien belum tersedia';
}
