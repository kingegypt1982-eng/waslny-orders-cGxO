import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Reasons a position could not be resolved, so the UI can explain the problem
/// instead of quietly falling back to a fixed city centre.
enum LocationFailure {
  /// GPS / location services are switched off on the device.
  serviceDisabled,

  /// The user dismissed the permission prompt.
  permissionDenied,

  /// The user permanently denied the permission.
  permissionDeniedForever,

  /// No location plugin on this platform (desktop, headless tests).
  unsupported,

  /// No fix within the time limit.
  timeout,

  /// Anything else.
  unknown,
}

/// The outcome of a location request: either a [point] or a [failure].
class LocationResult {
  const LocationResult.ok(LatLng this.point) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : point = null;

  final LatLng? point;
  final LocationFailure? failure;

  bool get ok => point != null;
}

/// Resolves the device position. Abstracts geolocator so widget tests can
/// inject a deterministic implementation.
abstract class LocationService {
  Future<LocationResult> current();

  /// Arabic, user-facing explanation for [failure].
  static String message(LocationFailure failure) => switch (failure) {
    LocationFailure.serviceDisabled =>
      'خدمة الموقع مغلقة على جهازك. شغّل GPS ثم أعد المحاولة.',
    LocationFailure.permissionDenied =>
      'لم تسمح باستخدام موقعك. اسمح بالوصول للموقع لعرض الطلبات القريبة.',
    LocationFailure.permissionDeniedForever =>
      'صلاحية الموقع مرفوضة نهائياً. فعّلها من إعدادات الهاتف.',
    LocationFailure.unsupported => 'الموقع غير متاح على هذه المنصة.',
    LocationFailure.timeout => 'تعذر تحديد موقعك الآن. حاول مرة أخرى.',
    LocationFailure.unknown => 'الموقع غير متاح حالياً.',
  };
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 15),
  );

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationFailure.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failed(LocationFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationFailure.permissionDeniedForever);
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: _settings,
        );
        return LocationResult.ok(
          LatLng(position.latitude, position.longitude),
        );
      } on TimeoutException {
        // A stale fix is still the device's own position, never a constant.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationResult.ok(LatLng(last.latitude, last.longitude));
        }
        return const LocationResult.failed(LocationFailure.timeout);
      }
    } on MissingPluginException {
      return const LocationResult.failed(LocationFailure.unsupported);
    } on UnimplementedError {
      return const LocationResult.failed(LocationFailure.unsupported);
    } catch (_) {
      return const LocationResult.failed(LocationFailure.unknown);
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

/// The captain's last resolved position.
///
/// Starts as `null` on purpose: the app never assumes a fixed city, it waits
/// for a real device fix (or a location the captain picked on the map picker).
final captainLocationProvider = StateProvider<LatLng?>((ref) => null);
