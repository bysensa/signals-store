// Регресс-зонды для StoreRootScope:
//   A: Platform.environment['FLUTTER_TEST'] присутствует под flutter test;
//   B: тело теста в дочерней зоне (!= Zone.root), соседние тесты — разные зоны.
import 'dart:async';
import 'dart:io' show Platform;
import 'package:test/test.dart';

void main() {
  test('probe A: FLUTTER_TEST env-var present', () {
    expect(Platform.environment.containsKey('FLUTTER_TEST'), isTrue);
  });

  test('probe B: test body zone is NOT root', () {
    expect(identical(Zone.current, Zone.root), isFalse);
  });

  test('probe B2: per-test distinct zones', () {
    _zones.add(Zone.current);
  });
  test('probe B3: per-test distinct zones (cross-check)', () {
    _zones.add(Zone.current);
    expect(_zones.map((z) => z.hashCode).toSet().length, _zones.length,
        reason: 'соседние тесты должны иметь разные зоны');
  });
}

final _zones = <Zone>[];
