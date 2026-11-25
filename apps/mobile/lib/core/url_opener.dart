import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens an external URL (hosted payment pages, support links).
///
/// Indirection so widget tests can capture the requested URL without touching
/// the url_launcher platform channel.
///
/// Returns `false` when the platform refused to open the URL. Note: on web this
/// always reports success once `window.open` is called — the browser cannot
/// tell us whether a pop-up blocker actually suppressed it, which is why the
/// wallet screen also offers a manual "open payment page" button.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// [LaunchMode.externalApplication] opens the real browser (the in-app web view
/// cannot complete a hosted card payment), and [webOnlyWindowName] forces a new
/// tab on Flutter Web (`_blank`). On non-web platforms the name is ignored.
Future<bool> _launchExternal(Uri uri) => launchUrl(
  uri,
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);

final urlOpenerProvider = Provider<UrlOpener>((ref) => _launchExternal);

/// Google Maps directions URL for a trip destination. Coordinates come from
/// the order; an origin is only added when the device has a real fix, so the
/// link never encodes a guessed city centre.
Uri mapsDirectionsUri({
  required double destinationLatitude,
  required double destinationLongitude,
  double? originLatitude,
  double? originLongitude,
}) {
  final hasOrigin = originLatitude != null && originLongitude != null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    if (hasOrigin) 'origin': '$originLatitude,$originLongitude',
    'destination': '$destinationLatitude,$destinationLongitude',
    'travelmode': 'driving',
  });
}

/// `tel:` URI for the order's recipient phone. Keeps the international `+`
/// and drops only display formatting (spaces, dashes, parentheses).
Uri telephoneUri(String phone) {
  final cleaned = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  return Uri(scheme: 'tel', path: cleaned);
}
