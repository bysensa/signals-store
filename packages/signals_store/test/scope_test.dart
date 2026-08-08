import 'package:signals_store/signals_store.dart';
import 'package:test/test.dart';

void main() {
  // Per-test зоны раннера дают изоляцию; resetCurrentZone — опциональная
  // страховка для раннеров с общей зоной файла.
  tearDown(StoreRootScope.resetCurrentZone);

  test('register then of<T> resolves the instance', () {
    final app = _App();
    StoreRootScope.register(app);
    expect(StoreRootScope.of<_App>(), same(app));
  });

  test('of<T> on missing root throws StateError', () {
    expect(() => StoreRootScope.of<_Missing>(), throwsStateError);
  });

  test('re-register same type replaces previous', () {
    final a = _App();
    final b = _App();
    StoreRootScope.register(a);
    StoreRootScope.register(b);
    expect(StoreRootScope.of<_App>(), same(b));
  });

  test('of<T> resolves by subtype (concrete impl is abstract base)', () {
    final store = _ConcreteApp();
    StoreRootScope.register(store);
    expect(StoreRootScope.of<_AppImpl>(), same(store));
  });

  test('per-test isolation: previous registration not visible here', () {
    // Этот тест идёт после тестов выше; per-test зона → пусто.
    expect(() => StoreRootScope.of<_App>(), throwsStateError);
  });

  test('unregister removes the entry deterministically', () {
    final app = _App();
    StoreRootScope.register(app);
    StoreRootScope.unregister(app);
    expect(() => StoreRootScope.of<_App>(), throwsStateError);
  });

  // Пересоздание корня без dispose (replace): новая регистрация вытесняет старую.
  test('re-create root without dispose: new instance wins', () {
    final first = _App();
    StoreRootScope.register(first);
    final second = _App();
    StoreRootScope.register(second);
    expect(StoreRootScope.of<_App>(), same(second));
  });

  // Двойной unregister/reset идемпотентен (dispose вызывает unregister; повторный
  // dispose не должен падать).
  test('unregister is idempotent (double unregister does not throw)', () {
    final app = _App();
    StoreRootScope.register(app);
    StoreRootScope.unregister(app);
    expect(() => StoreRootScope.unregister(app), returnsNormally);
    expect(() => StoreRootScope.of<_App>(), throwsStateError);
  });
}

class _App {}
class _Missing {}
abstract class _AppImpl {}
class _ConcreteApp extends _AppImpl {}
