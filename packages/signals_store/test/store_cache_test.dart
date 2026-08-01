import 'package:test/test.dart';
import 'package:signals_store/src/store.dart';

void main() {
  tearDown(ReactiveStore.resetCache);

  test('resetCache clears the global type-keyed symbol cache', () {
    // Arrange: один стор прогревает кэш (должна появиться запись для его типа).
    final store = _Store()..value = 1;
    expect(store.value, 1);

    // Act: сбрасываем кэш.
    ReactiveStore.resetCache();

    // Assert: после сброса новый стор должен работать с нуля (кэш пересоздаётся).
    // Проверяем это косвенно — чтение после записи должно вернуть значение.
    final fresh = _Store()..value = 2;
    expect(fresh.value, 2);
  });

  test('resetCache is idempotent (no-op when cache empty)', () {
    ReactiveStore.resetCache();
    ReactiveStore.resetCache(); // не должно бросать
    expect(() => ReactiveStore.resetCache(), returnsNormally);
  });
}

abstract class _Impl {
  abstract int value;
}

class _Store extends _Impl with ReactiveStore {}
