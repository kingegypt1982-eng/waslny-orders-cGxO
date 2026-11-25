import 'package:flutter_test/flutter_test.dart';
import 'package:wasalny_orders/core/json_utils.dart';

void main() {
  group('asDoubleOrNull / asDouble', () {
    test('accepts numbers', () {
      expect(asDouble(39.44), 39.44);
      expect(asDouble(40), 40);
      expect(asDoubleOrNull(0), 0);
    });

    test('accepts Decimal strings from the API', () {
      expect(asDouble('39.44'), 39.44);
      expect(asDouble(' 39.44 '), 39.44);
      expect(asDoubleOrNull('0.00'), 0);
      expect(asDoubleOrNull('12'), 12);
    });

    test('falls back for null, garbage and non-finite values', () {
      expect(asDoubleOrNull(null), isNull);
      expect(asDoubleOrNull('abc'), isNull);
      expect(asDoubleOrNull(''), isNull);
      expect(asDoubleOrNull(double.nan), isNull);
      expect(asDoubleOrNull(double.infinity), isNull);
      expect(asDouble(null), 0);
      expect(asDouble('abc', fallback: 7), 7);
    });
  });

  group('asIntOrNull / asInt', () {
    test('accepts numbers and strings, truncating decimals', () {
      expect(asInt(3), 3);
      expect(asInt('42'), 42);
      expect(asInt('3.4'), 3);
      expect(asIntOrNull(''), isNull);
      expect(asIntOrNull('abc'), isNull);
      expect(asInt(null, fallback: 5), 5);
    });
  });

  test('asString and asBool handle API payload shapes', () {
    expect(asString('PACKAGE'), 'PACKAGE');
    expect(asString(null), '');
    expect(asString(null, fallback: '-'), '-');
    expect(asBool(true), isTrue);
    expect(asBool('true'), isTrue);
    expect(asBool('1'), isTrue);
    expect(asBool('false'), isFalse);
    expect(asBool('0'), isFalse);
    expect(asBool(null, fallback: true), isTrue);
  });
}
