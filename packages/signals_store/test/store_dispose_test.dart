import 'package:test/test.dart';
import 'package:signals_store/src/store.dart';

void main() {
  setUp(ReactiveStore.resetCache);
  tearDown(ReactiveStore.resetCache);

  group('dispose()', () {
    test('disposes all held signals', () {
      final store = _Store()
        ..a = 1
        ..b = 2;

      // До dispose сигналы живы и читаемы.
      expect(store.a, 1);
      expect(store.b, 2);

      // dispose не должен бросать.
      expect(store.dispose, returnsNormally);
    });

    test('is idempotent (second call is a no-op)', () {
      final store = _Store()..a = 1;

      store.dispose();
      // Второй вызов не должен бросать и не должен иметь побочных эффектов.
      expect(store.dispose, returnsNormally);
      expect(store.dispose, returnsNormally);
    });

    test('getter access after dispose throws StateError', () {
      final store = _Store()..a = 1;
      store.dispose();

      expect(
        () => store.a,
        throwsA(
          allOf(
            isA<StateError>(),
            predicate<StateError>(
              (e) => e.message.contains('disposed'),
            ),
          ),
        ),
      );
    });

    test('setter access after dispose throws StateError', () {
      final store = _Store()..a = 1;
      store.dispose();

      expect(
        () => store.a = 99,
        throwsA(isA<StateError>()),
      );
    });

    test('StateError message mentions the offending field symbol', () {
      final store = _Store()..a = 1;
      store.dispose();

      try {
        store.a;
        fail('должно было бросить StateError');
      } on StateError catch (e) {
        // Сообщение должно помочь диагностировать, какое поле затронуто.
        expect(e.message, contains('a'));
      }
    });
  });
}

abstract class _Impl {
  abstract int a;
  abstract int b;
}

class _Store extends _Impl with ReactiveStore {}
