import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Keeps every GoRoute refresh-safe on Flutter Web: the browser path stays `/`
/// and the route lives after `#`, which is served by the same index.html.
void setHashUrlStrategy() => setUrlStrategy(HashUrlStrategy());
