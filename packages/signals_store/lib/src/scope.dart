import 'dart:async';
import 'dart:io' show Platform;

import 'package:meta/meta.dart';

/// Глобальный реестр корня дерева сторов с детектом окружения по env-var.
///
/// Окружение определяется автоматически (без флага и ручного включения):
/// - **Тест:** `flutter test` выставляет `Platform.environment['FLUTTER_TEST']`
///   → per-zone реестр (изоляция через per-test зоны раннера).
/// - **App** (plain или с `runZonedGuarded`): переменная отсутствует → единый
///   глобальный реестр, независимо от топологии зон приложения.
///
/// Окружения не пересекаются.
///
/// **Циклы удержания:** реестр хранит корни ТОЛЬКО через [WeakReference].
/// Стор удерживается обычными ссылками приложения; scope его не держит.
/// Корневой стор в [dispose] снимает регистрацию через [unregister] —
/// детерминизм для тестов вместо ожидания GC.
class StoreRootScope {
  StoreRootScope._();

  // `flutter test` автоматически выставляет FLUTTER_TEST (runtime env-var).
  // bool.fromEnvironment('FLUTTER_TEST') под flutter test даёт false —
  // проверено; нужен явный --dart-define. Поэтому runtime env-var.
  static final bool _isTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  static final _Registry _appRegistry = _Registry();
  static final Expando<_Registry> _testByZone = Expando();

  /// Регистрирует [root] (слабо) в активном окружении. Повторная регистрация
  /// того же типа заменяет предыдущую. Превентивно чистит мёртвые weak-записи.
  ///
  /// Регистрация привязывается к [Zone.current]: derived-сторы, чьи Computed
  /// выполняются в дочерних зонах (например, эффекты библиотеки signals под
  /// `flutter test`), найдут корень через обход цепочки родительских зон в
  /// [of] — см. `_lookupIn`.
  static void register(Object root) {
    final reg = _active();
    reg.purge();
    reg.set(root);
  }

  /// Явное снятие регистрации — вызывается из dispose корневого стора.
  ///
  /// Снимает регистрацию в [Zone.current] (где [register] её и ставил).
  static void unregister(Object root) => _active().remove(root);

  /// Резолвит корень типа [T]. Бросает [StateError], если не зарегистрирован.
  ///
  /// Под `flutter test` (per-zone реестр) ищет по цепочке зон от [Zone.current]
  /// вверх до корня: корень, зарегистрированный в родительской зоне (тело
  /// теста), виден дочерним зонам (эффекты signals при пересчёте Computed
  /// выполняются в отдельной дочерней зоне). Без обхода дочерняя зона
  /// разрешалась пусто → «корень не зарегистрирован».
  static T of<T>() {
    final target = _lookupIn<T>(Zone.current);
    if (target != null) return target;
    throw StateError(
      'StoreRootScope: корень типа $T не зарегистрирован. '
      'Убедитесь, что соответствующий стор помечен @Store(root: true) '
      'и создан, либо вызовите StoreRootScope.register(...) в тесте.',
    );
  }

  /// Очищает per-zone реестр текущей зоны (tearDown). Опционально: per-test
  /// зоны раннера уже изолируют.
  @visibleForTesting
  static void resetCurrentZone() {
    _testByZone[Zone.current]?.clear();
  }

  static _Registry _active() {
    if (_isTest) {
      return _testByZone[Zone.current] ??= _Registry();
    }
    return _appRegistry;
  }

  /// Обходит цепочку зон от [start] вверх до корня и возвращает первый
  /// найденный корень типа [T]. Вне тестов (единый `_appRegistry`) обход
  /// не нужен — `_lookupIn` сразу читает глобальный реестр.
  static T? _lookupIn<T>(Zone start) {
    if (!_isTest) return _appRegistry.lookup<T>();
    var zone = start;
    while (true) {
      final hit = _testByZone[zone]?.lookup<T>();
      if (hit != null) return hit;
      final parent = zone.parent;
      if (parent == null || identical(parent, zone)) return null;
      zone = parent;
    }
  }
}

/// Внутренний реестр: weak-ссылки на корни + lookup по типу с очисткой мусора.
class _Registry {
  final List<WeakReference<Object>> _refs = [];

  void set(Object root) {
    _refs
      ..removeWhere((r) => r.target?.runtimeType == root.runtimeType)
      ..add(WeakReference(root));
  }

  void remove(Object root) =>
      _refs.removeWhere((r) => identical(r.target, root));

  void purge() => _refs.removeWhere((r) => r.target == null);

  T? lookup<T>() {
    T? found;
    for (final ref in _refs.toList()) {
      final t = ref.target;
      if (t == null) {
        _refs.remove(ref);
        continue;
      }
      if (t is T) found = t as T; // последний wins (см. спеку).
    }
    return found;
  }

  void clear() => _refs.clear();
}
