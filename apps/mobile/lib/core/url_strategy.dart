// Conditional export: only the web build links `flutter_web_plugins`.
export 'url_strategy_stub.dart' if (dart.library.html) 'url_strategy_web.dart';
