import 'app.dart';
import 'core/url_strategy.dart';

void main() {
  // Flutter Web defaults to the hash strategy; make it explicit so every
  // GoRoute (including /#/payment-redirect) survives a browser refresh.
  setHashUrlStrategy();
  bootstrap();
}
