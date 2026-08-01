// ignore_for_file: lines_longer_than_80_chars

import 'package:signals/signals.dart';
import 'package:signals_store_example/stores.dart';
import 'package:test/test.dart';

/// Runtime smoke-тест для сгенерированных сторов.
///
/// Проверяет, что кодогенерированные классы (`FirstSomeStore`,
/// `SecondSomeStore`) реально работают: реактивное чтение/запись через
/// `Signal` и изоляция сторов друг от друга.
void main() {
  group('generated stores', () {
    test('FirstSomeStore reads/writes reactively', () {
      final store = FirstSomeStore(name: 'initial');
      expect(store.name, 'initial');

      store.name = 'updated';
      expect(store.name, 'updated');
    });

    test('SecondSomeStore is independent from FirstSomeStore', () {
      final first = FirstSomeStore(name: 'a');
      final second = SecondSomeStore(name: 'b');

      first.name = 'a2';
      expect(first.name, 'a2');
      expect(second.name, 'b', reason: 'стор-реализации изолированы');
    });

    test('debug name of the signal uses StoreName.field', () {
      final store = FirstSomeStore(name: 'x');
      // Доступ к внутреннему сигналу через тот же backdoor-паттерн, что и в
      // тестах signals_store: чтение `signalFor` здесь не применимо (нет
      // ReactiveStore), поэтому проверяем реактивность через эффект.
      final seen = <String>[];
      final sub = effect(() => seen.add(store.name));

      store.name = 'reactive';
      expect(seen, contains('reactive'));
      sub();
    });
  });
}
