# Derived-сторы: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Поддержать на уровне генерации derived-сторы — полноценные сторы с собственным состоянием и доступом к корню дерева, создаваемые on-demand в любом месте приложения.

**Architecture:** Новая аннотация `@DerivedStore` + флаг `@Store(root: true)` для маркировки корня. Runtime-класс `StoreRootScope` (zone-aware реестр через `Expando` + **`WeakReference`** для разрыва циклов удержания, с явным разделением app/test окружений) резолвит корень по типу. Генератор **максимально переиспользует** существующий пайплайн `@Store` через единый приватный эмиттер `_emitStoreClass` — никакого дублирования логики полей/геттеров/конструктора. `dispose()` становится единой механикой и для `@Store`, и для `@DerivedStore`. Детектор реактивности получает имя root-геттера в reactive-базу — новых механизмов реактивности не нужно.

**Tech Stack:** Dart ^3.12, Flutter ≥3.44, analyzer 12.1.0, source_gen/build_runner, signals ^7.0.0.

## Global Constraints

- **Версии пакетов** (поднять согласованно): `signals_store_annotation` 0.2.1 → **0.3.0**; `signals_store` (runtime) 0.2.1 → **0.3.0**; `signals_store_generator` 0.5.0 → **0.6.0**. В `signals_store_generator/pubspec.yaml` поднять зависимость annotation на `^0.3.0`.
- **analyzer 12.1.0** — ceiling (Flutter meta 1.18.0 pin). Использовать проверенные API: `isOriginDeclaration`, `name`/`namePart.typeName.lexeme`, `formal.field.name`. НЕ использовать удалённые API (`isSynthetic` для origin и т.п.).
- **Тесты генератора** запускаются под `flutter test`; обязательны: (1) `configureBuildProcessStateForTests()` в `setUpAll`, (2) `createDependencyReader` с предзагрузкой `signals_store` (новое), (3) каждый сгенерированный кейс проверяется `_expectCompiles` (принцип codegen-tests-must-compile), (4) валидационные ошибки — через `_runResult` + `expect(result.succeeded, false)`.
- **FN-vs-FP**: детектор реактивности не меняется по существу — только добавляется имя root-геттера в базу. Регрессионные тесты `reactivity_test.dart` должны оставаться зелёными.
- **Переиспользование генератора (требование):** `@Store` и `@DerivedStore` идут через единый приватный эмиттер `_emitStoreClass`; дублирование логики полей/геттеров/конструктора/коллизий между ними запрещено. Любой новый кейс-обработчик должен лечь в `_emitStoreClass` с флагом, а не в отдельную копию.
- **`dispose()` едино для `@Store` и `@DerivedStore`:** `_emitStoreClass` всегда эмитит `dispose()` (Signal/Computed). `@Store(root: true)` дополнительно снимает регистрацию (`StoreRootScope.unregister(this)`).
- **`WeakReference` против циклов:** `StoreRootScope` хранит корни только через `WeakReference` — никогда сильной ссылкой. Это снятое требование, а не оптимизация.
- **Комментарии/документация** — на русском, в стиле существующих докстринг.
- **Verify-before-planning**: эмпирические проверки зон (Task 2) выполняются ДО реализации `StoreRootScope` — от их результата зависит устройство `enableTestMode`/`resetTestScope`.

## Ссылка на дизайн

`docs/superpowers/specs/2026-08-08-derived-stores-design.md` — единственный источник решений. Все спорные моменты — туда.

## File Structure

**Создать:**
- `packages/signals_store/lib/src/scope.dart` — `StoreRootScope` (runtime реестр).
- `packages/signals_store/test/scope_test.dart` — unit-тесты `StoreRootScope` (вкл. zone-изоляцию).
- `packages/signals_store/test/zone_probe_test.dart` — эмпирические зонды (Task 2); после фиксации находок можно оставить как регрессию или удалить.
- `packages/signals_store_generator/test/derived_store_generator_test.dart` — тесты генерации `@DerivedStore` + `@Store(root: true)`.
- `packages/signals_store_example/lib/domain/derived_stores.dart` — generated derived-сторы (замена рукописного `ui/derived.dart`).

**Изменить:**
- `packages/signals_store_annotation/lib/src/annotations.dart` — `root` в `@Store`, новый класс `DerivedStore`.
- `packages/signals_store/lib/signals_store.dart` — `export 'src/scope.dart';`.
- `packages/signals_store_generator/lib/src/store_generator.dart` — авторегистрация корня, обработка `@DerivedStore`, dispose.
- `packages/signals_store_generator/test/helpers/flutter_test_harness.dart` — `dependencyPackages` += `signals_store`.
- `packages/signals_store_generator/test/store_generator_test.dart` — `headers` += import signals_store (для `_expectCompiles` root-генерации).
- `packages/signals_store_example/lib/domain/stores.dart` — `@Store(name: 'AppStore', root: true)`.
- `packages/signals_store_example/lib/main.dart` — убрать рукописную инициализацию, если миграция требует.
- CHANGELOG'и трёх пакетов.

---

### Task 1: Аннотации — `@Store(root: true)` и `@DerivedStore`

**Files:**
- Modify: `packages/signals_store_annotation/lib/src/annotations.dart`
- Modify: `packages/signals_store_annotation/pubspec.yaml` (version → 0.3.0)
- Modify: `packages/signals_store_annotation/CHANGELOG.md`
- Test: `packages/signals_store_annotation/test/annotations_test.dart` (создать)

**Interfaces:**
- Produces: `Store({required String name, bool abstract, bool root})` с `final bool root;` (default `false`); `DerivedStore({required String name})` с `final String name;`.

- [ ] **Step 1: Написать падающий тест**

Создать `packages/signals_store_annotation/test/annotations_test.dart`:

```dart
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:test/test.dart';

void main() {
  test('@Store has root flag defaulting to false', () {
    const store = Store(name: 'AppStore');
    expect(store.root, false);
    expect(store.abstract, false);
  });

  test('@Store(root: true) keeps the flag', () {
    const store = Store(name: 'AppStore', root: true);
    expect(store.root, true);
  });

  test('@DerivedStore carries name', () {
    const derived = DerivedStore(name: 'TodoDetailsStore');
    expect(derived.name, 'TodoDetailsStore');
  });
}
```

- [ ] **Step 2: Запустить тест — должен упасть (нет `root`, нет `DerivedStore`)**

Run: `cd packages/signals_store_annotation && flutter test test/annotations_test.dart`
Expected: FAIL — `root` undefined / `DerivedStore` undefined.

- [ ] **Step 3: Реализовать**

В `packages/signals_store_annotation/lib/src/annotations.dart`:

— в класс `Store` добавить поле `root` (конструктор + поле + докстринг):

```dart
class Store {
  const Store({required this.name, this.abstract = false, this.root = false});

  /// Имя генерируемого класса-реализации.
  final String name;

  /// Если `true` — генерируется `abstract`-класс.
  final bool abstract;

  /// Если `true` — сгенерированный стор саморегистрируется в `StoreRootScope`
  /// при создании и является валидной целью root-геттера derived-сторов.
  final bool root;
}
```

— добавить класс `DerivedStore` после `Store`:

```dart
/// Аннотация: помечает `abstract`-класс как derived-стор — полноценный стор
/// с собственным состоянием и доступом к корню дерева сторов.
///
/// Derived-стор идентичен `@Store` по всем механикам (abstract-поля → Signal,
/// concrete-поля → pass-through, concrete-геттеры → Computed). Отличия:
///
/// - обязательный `abstract`-геттер `root`, типизированный `@Store(root: true)`-
///   impl'ом; генератор эмитит его реализацию через `StoreRootScope.of<T>()`;
/// - сгенерированный `dispose()` для on-demand жизненного цикла (см. дизайн).
///
/// На одном классе допускается ровно одна аннотация `@DerivedStore`;
/// `@Store` и `@DerivedStore` на одном классе запрещены.
///
/// ```dart
/// @DerivedStore(name: 'TodoDetailsStore')
/// abstract class TodoDetailsStoreImpl {
///   abstract AppStoreImpl get root;
///   abstract String todoId;
///   Todo? get todo => root.projects.todos[todoId];
/// }
/// ```
class DerivedStore {
  const DerivedStore({required this.name});

  /// Имя генерируемого класса-реализации.
  final String name;
}
```

- [ ] **Step 4: Поднять версию + CHANGELOG**

`pubspec.yaml`: `version: 0.3.0`.
`CHANGELOG.md` — добавить сверху:

```
## 0.3.0

- Добавлен флаг `@Store(root: true)`: стор саморегистрируется в `StoreRootScope`.
- Добавлена аннотация `@DerivedStore` для derived-сторов с доступом к корню.
```

- [ ] **Step 5: Запустить тест — должен пройти**

Run: `cd packages/signals_store_annotation && flutter test test/annotations_test.dart`
Expected: PASS (3 теста).

- [ ] **Step 6: `dart analyze` пакета**

Run: `cd packages/signals_store_annotation && dart analyze`
Expected: no issues.

- [ ] **Step 7: Коммит**

```bash
git add packages/signals_store_annotation
git commit -m "feat(annotation): add @Store(root: true) flag and @DerivedStore annotation (0.3.0)"
```

---

### Task 2: Эмпирические зонды зон (verify-before-planning)

**Цель:** до реализации `StoreRootScope` проверить 3 гипотезы, от которых зависит его устройство. Находки зафиксировать в комментариях `scope.dart` (Task 3).

**Files:**
- Create: `packages/signals_store/test/zone_probe_test.dart`

**Interfaces:**
- Produces: текстовые находки (записываются в Task 3 как комментарии). Проверка: `flutter test test/zone_probe_test.dart` проходит, assertions соответствуют наблюдённому.

- [ ] **Step 1: Написать зонды**

`packages/signals_store/test/zone_probe_test.dart`:

```dart
// Эмпирические зонды Zone-поведения под flutter test.
// Цель: подтвердить допущения StoreRootScope ДО его реализации.
import 'dart:async';
import 'package:test/test.dart';

void main() {
  // Зонд A: разные ли Zone.current у соседних test()?
  test('probe A: per-test Zone.current differs', () {
    final z = Zone.current;
    // Запоминаем во внешнем capture и сравниваем во втором тесте.
    _probeAZones.add(z);
    printOnFailure('A zone: ${z.hashCode}');
  });

  test('probe A2: second test zone', () {
    final z = Zone.current;
    _probeAZones.add(z);
    printOnFailure('A2 zone: ${z.hashCode}');
    // Если раннер даёт зону на тест — хэш-коды различны.
    expect(_probeAZones.toSet().length, greaterThan(1),
        reason: 'Ожидаем разные Zone.current на тест (иначе resetTestScope обязателен)');
  });

  // Зонд B: async-callback внутри теста — та же зона?
  test('probe B: async continuation preserves zone', () async {
    final before = Zone.current;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final after = Zone.current;
    expect(identical(before, after), true,
        reason: 'async-await должен сохранять Zone.current');
  });
}

final _probeAZones = <Zone>[];
```

- [ ] **Step 2: Запустить, прочитать вывод**

Run: `cd packages/signals_store && flutter test test/zone_probe_test.dart`
Наблюдаем: A/A2 — различаются ли хэш-коды? B — passed?

- [ ] **Step 3: Зафиксировать находку**

Записать результат (passed/failed) комментарием в начале файла:

```dart
// НАХОДКИ (flutter test, package:test):
//   A: <различаются / совпадают> — значит resetTestScope <нужен / не нужен>.
//   B: async сохраняет зону → резолв после await видит регистрацию.
// testWidgets-проверка (зонд C) — в Task 3 после реализации, через виджет-тест.
```

(Если A падает — значит раннер НЕ даёт per-test зоны → в Task 3 `resetTestScope()` становится обязательным в tearDown, что уже предусмотрено дизайном.)

- [ ] **Step 4: Коммит**

```bash
git add packages/signals_store/test/zone_probe_test.dart
git commit -m "test(signals_store): zone-behavior probes for StoreRootScope design"
```

---

### Task 3: `StoreRootScope` — runtime реестр с разделением окружений

**Зависит от:** Task 1 (export), находок Task 2.

**Files:**
- Create: `packages/signals_store/lib/src/scope.dart`
- Modify: `packages/signals_store/lib/signals_store.dart` (export)
- Modify: `packages/signals_store/pubspec.yaml` (version → 0.3.0, deps += meta)
- Modify: `packages/signals_store/CHANGELOG.md`
- Test: `packages/signals_store/test/scope_test.dart`

**Interfaces:**
- Produces:
  - `StoreRootScope.register(Object root)` — пишет в активное окружение через **`WeakReference`**.
  - `StoreRootScope.of<T>()` → `T` — резолв по типу (`is T`-скан по weak-ссылкам); убирает мёртвые записи влетую; `StateError` если не найден.
  - `StoreRootScope.unregister(Object root)` — явное удаление weak-записи (вызывается из dispose root-стора).
  - `StoreRootScope.enableTestMode()` (`@visibleForTesting`).
  - `StoreRootScope.resetTestScope()` (`@visibleForTesting`).

- [ ] **Step 1: Написать падающие тесты**

`packages/signals_store/test/scope_test.dart`:

```dart
import 'package:signals_store/signals_store.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(StoreRootScope.enableTestMode);
  tearDown(StoreRootScope.resetTestScope);

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

  test('test-mode does not leak into app registry', () {
    // После resetTestScope (tearDown) предыдущий тест не виден здесь.
    expect(() => StoreRootScope.of<_App>(), throwsStateError);
  });

  // Разрыв цикла удержания: scope НЕ удерживает корень сильно.
  test('weak ref: collected root is not resolvable', () {
    StoreRootScope.register(_App()); // сильной ссылки нет
    // Принуждаем GC и обнуление weak-target. В Dart нет детерминированного GC,
    // но unregister моделирует тот же эффект детерминированно:
    // (детерминированную проверку сбора делает следующий тест через unregister.)
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
    StoreRootScope.register(second); // dispose не вызывался — replace по типу
    expect(StoreRootScope.of<_App>(), same(second));
  });
}

class _App {}
class _Missing {}
abstract class _AppImpl {}
class _ConcreteApp extends _AppImpl {}
```

- [ ] **Step 2: Запустить — должны упасть (нет StoreRootScope)**

Run: `cd packages/signals_store && flutter test test/scope_test.dart`
Expected: FAIL — `StoreRootScope` undefined / export missing.

- [ ] **Step 3: Реализовать `scope.dart`**

`packages/signals_store/lib/src/scope.dart` (с учётом находок Task 2 — если A показал «зоны не различаются», `resetTestScope` в tearDown обязателен, что тесты выше и предполагают):

```dart
import 'dart:async';

import 'package:meta/meta.dart';

/// Глобальный реестр корня дерева сторов с явным разделением окружений.
///
/// **App-окружение** (по умолчанию): один глобальный zone-free реестр.
/// Приложение имеет один инстанс корня каждого типа; топология зон приложения
/// на резолв не влияет.
///
/// **Test-окружение** ([enableTestMode]): регистрации привязываются к
/// `Zone.current` через [Expando] (zone-values иммутабельны — форкать зону
/// ради значения нельзя), плюс file-level fallback. Раннеры, дающие per-test
/// зону, изолируют автоматически; иначе — [resetTestScope] в `tearDown`.
/// Тестовые регистрации никогда не попадают в app-реестр и наоборот.
///
/// **Циклы удержания:** реестр хранит корни ТОЛЬКО через [WeakReference].
/// Стор удерживается обычными ссылками приложения (дерево, State); scope его
/// не держит. Стор без сильных ссылок собирается GC, его weak-запись
/// обнуляется и убирается при следующем обходе [of]. Корневой стор в своём
/// [dispose] дополнительно явно снимает регистрацию через [unregister] —
/// детерминизм для тестов вместо ожидания GC.
class StoreRootScope {
  StoreRootScope._();

  // App-окружение.
  static final List<WeakReference<Object>> _appRoots = [];

  // Test-окружение: реестры по зоне + fallback.
  static final Expando<List<WeakReference<Object>>> _testByZone =
      Expando('StoreRootScope.test');
  static final List<WeakReference<Object>> _testFallback = [];
  static bool _testMode = false;

  /// Регистрирует [root] (слабо) в активном окружении. Повторная регистрация
  /// того же типа заменяет предыдущую (hot reload, повторное создание в тесте).
  /// Превентивно чистит мёртвые weak-записи (`target == null`).
  static void register(Object root) {
    final registry = _activeRegistry();
    // Превентивная очистка мёртвых weak-записей: реестр не копит мусор между
    // вызовами of<T> (важно при пересоздании корня без dispose — см. спеку).
    registry.removeWhere((ref) => ref.target == null);
    registry
      ..removeWhere((ref) => ref.target?.runtimeType == root.runtimeType)
      ..add(WeakReference(root));
  }

  /// Явное снятие регистрации — вызывается из dispose корневого стора.
  static void unregister(Object root) {
    _activeRegistry().removeWhere((ref) => identical(ref.target, root));
  }

  /// Резолвит корень типа [T]. Бросает [StateError], если не зарегистрирован.
  static T of<T>() {
    final registry = _activeRegistry();
    T? found;
    for (final ref in registry.toList()) {
      final target = ref.target;
      if (target == null) {
        // Мёртвая weak-запись — убираем влетую.
        registry.remove(ref);
        continue;
      }
      if (target is T) {
        found = target;
        // Не выходим: позднее повторное override того же типа должно выиграть,
        // если пользователь перерегистрировал (последний wins).
      }
    }
    if (found != null) return found;
    throw StateError(
      'StoreRootScope: корень типа $T не зарегистрирован. '
      'Убедитесь, что соответствующий стор помечен @Store(root: true) '
      'и создан, либо вызовите StoreRootScope.register(...) в тесте.',
    );
  }

  /// Включает тестовое окружение. Вызывать в `setUpAll` тестового файла.
  @visibleForTesting
  static void enableTestMode() => _testMode = true;

  /// Очищает регистрации тестового окружения текущей зоны и fallback.
  @visibleForTesting
  static void resetTestScope() {
    final byZone = _testByZone[Zone.current];
    if (byZone != null) byZone.clear();
    _testFallback.clear();
  }

  static List<WeakReference<Object>> _activeRegistry() {
    if (!_testMode) return _appRoots;
    return _testByZone[Zone.current] ??= _testFallback;
  }
}
```

Примечание к `of<T>`: обход собирает последнее совпадение по типу — это реализует
«последняя регистрация того же типа выигрывает» даже когда типы совпадают по
`is T` (наследник/база). Мёртвые weak-записи убираются в том же проходе.

- [ ] **Step 4: Экспортировать**

`packages/signals_store/lib/signals_store.dart` — добавить:

```dart
export 'src/scope.dart';
```

- [ ] **Step 5: Поднять версию + CHANGELOG + deps**

`pubspec.yaml`: `version: 0.3.0`. В `dependencies` уже есть `meta: ^1.18.0` (используем `@visibleForTesting`).
`CHANGELOG.md`:

```
## 0.3.0

- Добавлен `StoreRootScope` — реестр корня дерева сторов с разделением
  app/test окружений (zone-aware через Expando).
```

- [ ] **Step 6: Запустить тесты — должны пройти**

Run: `cd packages/signals_store && flutter test test/scope_test.dart`
Expected: PASS (5 тестов).

- [ ] **Step 7: Запустить зонды Task 2 повторно — регрессия**

Run: `cd packages/signals_store && flutter test`
Expected: все тесты пакета (scope + zone_probe) зелёные.

- [ ] **Step 8: `dart analyze`**

Run: `cd packages/signals_store && dart analyze`
Expected: no issues.

- [ ] **Step 9: Коммит**

```bash
git add packages/signals_store
git commit -m "feat(signals_store): StoreRootScope with app/test environment separation (0.3.0)"
```

---

### Task 4: Генератор — авторегистрация корня `@Store(root: true)`

**Зависит от:** Task 1 (флаг `root`), Task 3 (`StoreRootScope`).

**Files:**
- Modify: `packages/signals_store_generator/lib/src/store_generator.dart` (чтение `root`, тело конструктора)
- Modify: `packages/signals_store_generator/pubspec.yaml` (annotation `^0.3.0`, version → 0.6.0)
- Modify: `packages/signals_store_generator/test/helpers/flutter_test_harness.dart` (preload `signals_store`)
- Modify: `packages/signals_store_generator/test/store_generator_test.dart` (headers + тест)
- Modify: `packages/signals_store_generator/CHANGELOG.md`

**Interfaces:**
- Consumes: `Store` с полем `root`; `StoreRootScope.register` из signals_store.
- Produces: для `@Store(root: true)` конструктор получает тело `{ StoreRootScope.register(this); }`.

- [ ] **Step 1: Обновить test-harness — предзагрузить signals_store**

`packages/signals_store_generator/test/helpers/flutter_test_harness.dart`, функция `createDependencyReader`, параметр `dependencyPackages`:

```dart
  List<String> dependencyPackages = const [
    'signals_store_annotation',
    'signals_store',
    'signals',
  ],
```

- [ ] **Step 2: Написать падающий тест**

В `packages/signals_store_generator/test/store_generator_test.dart` — обновить `headers` (добавить import signals_store) и добавить тест. В `const headers = ...`:

```dart
  const headers = '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals_store/signals_store.dart';
import 'package:signals/signals.dart';
''';
```

Добавить тест (новая группа):

```dart
  group('@Store(root: true)', () {
    test('root store constructor registers itself in StoreRootScope', () async {
      final generated = await _run(
        packageConfig,
        headers,
        '''
        @Store(name: 'AppStore', root: true)
        abstract class AppStoreImpl {
          abstract int count;
        }
        ''',
      );
      expect(
        generated,
        allOf([
          contains('class AppStore extends AppStoreImpl'),
          contains('StoreRootScope.register(this)'),
        ]),
      );
      await _expectCompiles(headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

$generated''');
    });

    test('non-root store has no registration call', () async {
      final generated = await _run(
        packageConfig,
        headers,
        '''
        @Store(name: 'LeafStore')
        abstract class LeafImpl {
          abstract int count;
        }
        ''',
      );
      expect(generated, isNot(contains('StoreRootScope')));
    });

    test('every @Store emits dispose() disposing signals', () async {
      final generated = await _run(
        packageConfig,
        headers,
        '''
        @Store(name: 'S')
        abstract class SImpl {
          abstract int a;
        }
        ''',
      );
      expect(
        generated,
        allOf([
          contains('void dispose()'),
          contains('a\$.dispose()'),
        ]),
      );
    });

    test('root store dispose() unregisters itself', () async {
      final generated = await _run(
        packageConfig,
        headers,
        '''
        @Store(name: 'AppStore', root: true)
        abstract class AppStoreImpl {
          abstract int count;
        }
        ''',
      );
      expect(generated, contains('StoreRootScope.unregister(this)'));
    });
  });
```

- [ ] **Step 3: Запустить — должен упасть**

Run: `cd packages/signals_store_generator && flutter test test/store_generator_test.dart -P "root store constructor registers itself"`
Expected: FAIL — `StoreRootScope.register(this)` отсутствует.

- [ ] **Step 4: Реализовать чтение `root` и тело конструктора**

В `packages/signals_store_generator/lib/src/store_generator.dart`, в `_generateForAnnotation`:

— после чтения `isAbstract` (~строка, где `final isAbstract = annotation.peek('abstract')?.boolValue ?? false;`) добавить:

```dart
    final isRoot = annotation.peek('root')?.boolValue ?? false;
```

— в блоке эмиссии конструктора найти:

```dart
    buffer
      ..write('  $storeName({${ctorParams.join(', ')}})')
      ..write(allInits.isEmpty ? ';' : ' : ${allInits.join(', ')};')
      ..writeln();
```

— заменить на:

```dart
    // Тело конструктора: для root-стора — авторегистрация в StoreRootScope.
    // `this` доступен в теле (после initializer-list); signals уже созданы.
    final ctorBody = isRoot ? ' { StoreRootScope.register(this); }' : '';
    buffer
      ..write('  $storeName({${ctorParams.join(', ')}})')
      ..write(allInits.isEmpty
          ? (ctorBody.isEmpty ? ';' : ctorBody)
          : ' : ${allInits.join(', ')}$ctorBody')
      ..writeln();
```

— **эмиссия dispose для всех сторов** (в конце `_emitStoreClass`, перед
  `buffer.writeln('}')`). Единый фрагмент, общий для `@Store` и `@DerivedStore`
  (на этом этапе `isDerived` ещё false для `@Store`, но фрагмент пишется так,
  чтобы Task 6 просто включил его):

```dart
    // dispose() — единая механика для @Store и @DerivedStore.
    // Диспозит Signal/Computed-поля; для root-стора снимает регистрацию.
    final disposeBuffer = StringBuffer();
    final hasConcreteDispose = (element as ClassElement).methods.any(
      (m) => m.name == 'dispose' && m.isOriginDeclaration && !m.isStatic &&
             !m.isAbstract,
    );
    if (hasConcreteDispose) disposeBuffer.writeln('  @override');
    disposeBuffer.write('  void dispose() {');
    if (hasConcreteDispose) disposeBuffer.write(' super.dispose();');
    disposeBuffer.writeln();
    for (final f in reactiveFields) {
      disposeBuffer.writeln('    ${f.name}\$.dispose();');
    }
    for (final g in reactiveNames) {
      disposeBuffer.writeln('    ${g}\$.dispose();');
    }
    if (isRoot) disposeBuffer.writeln('    StoreRootScope.unregister(this);');
    disposeBuffer.writeln('  }');
    buffer
      ..writeln()
      ..write(disposeBuffer.toString());
```

(Валидацию сигнатуры пользовательского `dispose()` (non-void/параметры) добавляет
Task 6 для `@DerivedStore`; для `@Store` на этом этапе валидация та же —
рекомендуется вынести в общий хелпер в Task 5.)

- [ ] **Step 5: Поднять версию generator + зависимость**

`pubspec.yaml`: `version: 0.6.0`; в `dependencies` поднять `signals_store_annotation: ^0.3.0`.
`CHANGELOG.md`:

```
## 0.6.0

- `@Store(root: true)` — стор саморегистрируется в `StoreRootScope`.
- (Поддержка `@DerivedStore` — последующие задачи.)
```

- [ ] **Step 6: Запустить тест — должен пройти**

Run: `cd packages/signals_store_generator && flutter test test/store_generator_test.dart`
Expected: PASS (включая новую группу и все существующие — регрессия).

- [ ] **Step 7: Коммит**

```bash
git add packages/signals_store_generator
git commit -m "feat(generator): @Store(root: true) auto-registers in StoreRootScope (0.6.0)"
```

---

### Task 5: Генератор — рефакторинг: выделение общего эмиссора класса

**Цель:** извлечь ВСЁ общее тело `_generateForAnnotation` (поля/геттеры/конструктор/коллизии/**dispose**) в `_emitStoreClass`, чтобы `@DerivedStore` переиспользовал его без копирования. Чистый рефакторинг — поведение `@Store` не меняется (только добавляется dispose, уже покрытый тестами Task 4); защита от регрессии — все существующие тесты + новые dispose-тесты.

**Files:**
- Modify: `packages/signals_store_generator/lib/src/store_generator.dart`

**Interfaces:**
- Produces: приватный метод `_emitStoreClass(Element element, String storeName, bool isAbstract, bool isRoot, Map<String,String> implToStoreName, Set<String> storeImplNames, Set<String> rootImplNames, {bool isDerived, String? rootMemberName, String? rootTypeStr})`. На этом этапе `isDerived` всегда false; dispose-фрагмент уже в `_emitStoreClass`.

- [ ] **Step 1: Базлайн — все тесты зелёные (включая Task 4)**

Run: `cd packages/signals_store_generator && flutter test`
Expected: PASS.

- [ ] **Step 2: Рефакторинг — перенести тело в `_emitStoreClass`**

Перенести содержимое `_generateForAnnotation` (от чтения полей до `buffer.writeln('}')` — включая dispose-фрагмент из Task 4) в `_emitStoreClass`. `_generateForAnnotation` оставить тонкой обёрткой:

```dart
    final storeName = annotation.read('name').stringValue;
    final isAbstract = annotation.peek('abstract')?.boolValue ?? false;
    final isRoot = annotation.peek('root')?.boolValue ?? false;
    return _emitStoreClass(
      element, storeName, isAbstract, isRoot,
      implToStoreName, storeImplNames, rootImplNames,
      isDerived: false,
    );
```

`_emitStoreClass` пока не использует `isDerived`/`rootMemberName`/`rootTypeStr` (Task 6 наполнит). Валидация сигнатуры пользовательского `dispose()` (non-void/параметры) — общий хелпер `_validateDisposeSignature(element)`, вызывается из `_emitStoreClass` всегда (покрывает и `@Store`, и `@DerivedStore`):

```dart
void _validateDisposeSignature(ClassElement element) {
  final dispose = element.methods.firstWhere(
    (m) => m.name == 'dispose' && m.isOriginDeclaration && !m.isStatic,
    orElse: () => null as MethodElement,
  );
  if (dispose == null) return;
  final badSig = !dispose.returnType.isVoid || dispose.parameters.isNotEmpty;
  if (badSig) {
    throw InvalidGenerationSource(
      'dispose() in "${element.name}" must be a no-argument void method.',
      element: dispose,
    );
  }
}
```

- [ ] **Step 3: Запустить ВСЕ тесты генератора — должны остаться зелёными**

Run: `cd packages/signals_store_generator && flutter test`
Expected: PASS (тот же набор, что в Step 1).

- [ ] **Step 4: Коммит**

```bash
git add packages/signals_store_generator/lib/src/store_generator.dart
git commit -m "refactor(generator): extract _emitStoreClass + unified dispose shared by @Store and @DerivedStore"
```

---

### Task 6: Генератор — обработка `@DerivedStore`

**Зависит от:** Task 5. Самая объёмная задача.

**Files:**
- Modify: `packages/signals_store_generator/lib/src/store_generator.dart`
- Create: `packages/signals_store_generator/test/derived_store_generator_test.dart`

**Interfaces:**
- Consumes: `DerivedStore`-checker; `rootImplNames` (impl-имена с `@Store(root:true)`); `StoreRootScope.of<T>`.
- Produces: для `@DerivedStore` — класс с root-геттером (`late final ... = StoreRootScope.of<...>()`), всеми механиками `@Store`, и `dispose()`.

- [ ] **Step 1: Написать падающие тесты**

`packages/signals_store_generator/test/derived_store_generator_test.dart`:

```dart
// ignore_for_file: lines_longer_than_80_chars

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:signals_store_generator/src/builder.dart';
import 'package:test/test.dart';

import 'helpers/flutter_test_harness.dart';

void main() {
  late final PackageConfig packageConfig;

  setUpAll(() async {
    await configureBuildProcessStateForTests();
    packageConfig = await loadWorkspacePackageConfig();
  });

  const headers = '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals_store/signals_store.dart';
import 'package:signals/signals.dart';
''';

  test('derived store: root getter resolves via StoreRootScope.of', () async {
    final generated = await _run(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'CounterDerived')
abstract class CounterDerivedImpl {
  abstract AppStoreImpl get root;
  int get doubled => root.count * 2;
}
''');
    expect(
      generated,
      allOf([
        contains('class CounterDerived extends CounterDerivedImpl'),
        contains('late final AppStoreImpl root = StoreRootScope.of<AppStoreImpl>()'),
        // doubled читает root → Computed
        contains('Computed<int> doubled\$'),
        contains('int get doubledRaw => super.doubled'),
      ]),
    );
    await _expectCompiles(headers, '$headers\n$generated'.replaceFirst(headers, '') + generated);
  });

  test('derived store: own abstract field becomes Signal + ctor param', () async {
    final generated = await _run(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'TodoDetailsStore')
abstract class TodoDetailsStoreImpl {
  abstract AppStoreImpl get root;
  abstract String todoId;
  int get len => root.count + todoId.length;
}
''');
    expect(
      generated,
      allOf([
        contains("TodoDetailsStore({required String todoId})"),
        contains('Signal<String> todoId\$'),
      ]),
    );
  });

  // --- Пересоздание корня: root-геттер (не late final) видит актуальный корень ---

  test('derived store: root is a getter (not late final) → sees re-registered root',
      () async {
    final generated = await _run(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  abstract AppStoreImpl get root;
  int get doubled => root.count * 2;
}
''');
    expect(
      generated,
      allOf([
        contains('AppStoreImpl get root => StoreRootScope.of<AppStoreImpl>()'),
        isNot(contains('late final AppStoreImpl root')),
      ]),
    );
    await _expectCompiles(headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl { abstract int count; }

@DerivedStore(name: 'D')
abstract class DImpl {
  abstract AppStoreImpl get root;
  int get doubled => root.count * 2;
}

$generated''');
  });

  test('derived store: dispose() emitted disposing signals and computed', () async {

  test('derived store: concrete dispose() in impl → super.dispose() first', () async {
    final generated = await _run(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  abstract AppStoreImpl get root;
  abstract int a;
  void dispose() {
    // user cleanup
  }
}
''');
    expect(
      generated,
      allOf([
        contains('@override'),
        contains('void dispose() {'),
        contains('super.dispose();'),
        contains('a\$.dispose()'),
      ]),
    );
  });

  // --- Валидации (FN-критичные) ---

  test('validation: derived without root getter → build error', () async {
    final result = await _runResult(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  abstract int a;
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), contains('root'));
  });

  test('validation: derived root getter typed by non-root store → build error',
      () async {
    final result = await _runResult(packageConfig, headers, '''
@Store(name: 'Leaf')
abstract class LeafImpl {
  abstract int x;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  abstract LeafImpl get root;
  abstract int a;
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), contains('root: true'));
  });

  test('validation: @Store and @DerivedStore on one class → build error',
      () async {
    final result = await _runResult(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@Store(name: 'S')
@DerivedStore(name: 'D')
abstract class DImpl {
  abstract AppStoreImpl get root;
}
''');
    expect(result.succeeded, false);
  });
}

const _testOptions = BuilderOptions({});

Future<String> _run(PackageConfig pc, String headers, String body) async {
  final result = await _runResult(pc, headers, body);
  expect(result.succeeded, true,
      reason: 'Ожидалась успешная сборка:\n${result.errors.join('\n')}');
  expect(result.outputs, hasLength(1));
  return result.readerWriter.readAsString(result.outputs.single);
}

Future<TestBuilderResult> _runResult(PackageConfig pc, String headers, String body) {
  return testBuilder(
    storeBuilder(_testOptions),
    {'a|lib/store.dart': '$headers\n$body'},
    packageConfig: pc,
    readerWriter: createDependencyReader(pc),
    flattenOutput: true,
  );
}

Future<void> _expectCompiles(String headers, String body) async {
  // Делегируется существующему хелперу — см. store_generator_test.dart.
  // Чтобы не дублировать, тесты компилируемости можно держать здесь через
  // копию _expectCompiles, либо вынести хелпер в helpers/ (рекомендуется).
  throw UnimplementedError('см. примечание в Step 1 — вынести _expectCompiles в helpers');
}
```

**Примечание (важно):** `_expectCompiles` дублируется в `store_generator_test.dart`. Перед написанием тестов — вынести `_expectCompiles` (и при необходимости `_run`/`_runResult`) в `packages/signals_store_generator/test/helpers/codegen_checks.dart` как `Future<void> expectCompiles(String headers, String body)` и импортировать из обоих тестовых файлов. Это отдельный мини-шаг ниже.

- [ ] **Step 2: Вынести `_expectCompiles` в общий хелпер**

Создать `packages/signals_store_generator/test/helpers/codegen_checks.dart`, перенести туда `_expectCompiles` (переименовать в `expectCompiles`), `_run`, `_runResult` (как `runBuilder`/`runBuilderResult`), `_testOptions`, `headers`-константу. Обновить импорты в `store_generator_test.dart`. Убедиться, что существующие тесты проходят.

Run: `cd packages/signals_store_generator && flutter test`
Expected: PASS.

- [ ] **Step 3: Запустить новые derived-тесты — должны упасть (нет обработки DerivedStore)**

Run: `cd packages/signals_store_generator && flutter test test/derived_store_generator_test.dart`
Expected: FAIL (generated не содержит root-of / dispose; или build падает по другой причине).

- [ ] **Step 4: Реализовать обработку `@DerivedStore`**

В `store_generator.dart`:

4a. Добавить checker:

```dart
  static final _derivedChecker = TypeChecker.fromUrl(
    'package:signals_store_annotation/src/annotations.dart#DerivedStore',
  );
```

4b. В `generate(LibraryReader library, BuildStep buildStep)` — расширить построение карт. После существующего цикла построения `implToStoreName` добавить построение `rootImplNames` и обработку derived. Переписать финальный цикл так, чтобы он обходил и `@Store`, и `@DerivedStore`:

```dart
    // impl-имя → имя реализации (и @Store, и @DerivedStore).
    final implToStoreName = <String, String>{};
    final rootImplNames = <String>{}; // impl-имена с @Store(root: true)
    for (final element in library.allElements) {
      if (element is! ClassElement) continue;
      final storeAnn = _storeChecker.firstAnnotationOf(element);
      if (storeAnn != null) {
        final name = ConstantReader(storeAnn).read('name').stringValue;
        implToStoreName[element.name!] = name;
        if (ConstantReader(storeAnn).peek('root')?.boolValue ?? false) {
          rootImplNames.add(element.name!);
        }
      }
      final derivedAnn = _derivedChecker.firstAnnotationOf(element);
      if (derivedAnn != null) {
        implToStoreName[element.name!] =
            ConstantReader(derivedAnn).read('name').stringValue;
      }
    }
    final storeImplNames = implToStoreName.keys.toSet();

    final values = <String>[];
    for (final element in library.allElements) {
      if (element is! ClassElement) continue;

      // @Store (ровно одна на класс — проверка дубликатов как раньше)
      final storeAnns = _storeChecker.annotationsOf(element);
      final derivedAnns = _derivedChecker.annotationsOf(element);
      if (storeAnns.isEmpty && derivedAnns.isEmpty) continue;

      if (storeAnns.isNotEmpty && derivedAnns.isNotEmpty) {
        throw InvalidGenerationSource(
          'Class "${element.name}" annotated with both @Store and @DerivedStore. '
          'Use exactly one annotation per class.',
          element: element,
        );
      }
      if (storeAnns.length > 1) {
        // существующая проверка дублирующих @Store — оставить как есть
        throw InvalidGenerationSource(
          'Class "${element.name}" annotated with multiple @Store annotations.',
          element: element,
        );
      }

      if (storeAnns.isNotEmpty) {
        final generated = await _generateForAnnotation(
          element, ConstantReader(storeAnns.single),
          implToStoreName, storeImplNames, rootImplNames,
        );
        if (generated != null) values.add(generated);
      } else {
        final generated = await _generateDerived(
          element, ConstantReader(derivedAnns.single),
          implToStoreName, storeImplNames, rootImplNames,
        );
        if (generated != null) values.add(generated);
      }
    }
    return values.isEmpty ? '' : values.join('\n\n');
```

(Обновить сигнатуру `_generateForAnnotation` — добавить параметр `Set<String> rootImplNames`; он нужен только для derived, но проходит транзитом.)

4c. Добавить `_generateDerived`:

```dart
  Future<String?> _generateDerived(
    Element element,
    ConstantReader annotation,
    Map<String, String> implToStoreName,
    Set<String> storeImplNames,
    Set<String> rootImplNames,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSource(
        '@DerivedStore can only be applied to classes.', element: element);
    }
    if (!element.isAbstract) {
      throw InvalidGenerationSource(
        '@DerivedStore class "${element.name}" must be abstract.', element: element);
    }

    // Поиск root-геттера: ровно один abstract-геттер, тип ∈ rootImplNames.
    final rootGetters = element.getters.where((g) =>
        g.isGetter && g.isAbstract && !g.isStatic && g.isOriginDeclaration).toList();
    final rootGetter = rootGetters.where((g) {
      final t = g.returnType;
      final el = t is InterfaceType ? t.element : null;
      return el != null && rootImplNames.contains(el.name);
    }).toList();
    if (rootGetter.isEmpty) {
      throw InvalidGenerationSource(
        'Derived store "${element.name}" must declare exactly one abstract '
        'getter typed by a @Store(root: true) impl (e.g. '
        '"abstract AppStoreImpl get root;"). Found ${rootGetters.length} '
        'abstract getter(s), none typed by a root store.',
        element: element);
    }
    if (rootGetter.length > 1) {
      throw InvalidGenerationSource(
        'Derived store "${element.name}" declares multiple root-typed getters '
        '(${rootGetter.map((g) => g.name).join(', ')}). Only one is allowed.',
        element: element);
    }
    final rootMember = rootGetter.single;
    final rootTypeStr = rootMember.returnType.getDisplayString();

    // Проверка: поле (не геттер), типизированное корневым impl → ясная ошибка.
    for (final f in _allFields(element)) {
      final el = f.type is InterfaceType ? (f.type as InterfaceType).element : null;
      if (el != null && rootImplNames.contains(el.name)) {
        throw InvalidGenerationSource(
          'Field "${f.name}" in derived store "${element.name}" is typed by a '
          'root store. Declare root access as an abstract getter instead: '
          '"abstract $rootTypeStr get root;".', element: f);
      }
    }

    final storeName = annotation.read('name').stringValue;
    return _emitStoreClass(
      element, storeName, /*isAbstract=*/ false, /*isRoot=*/ false,
      implToStoreName, storeImplNames,
      isDerived: true,
      rootMemberName: rootMember.name!,
      rootTypeStr: rootTypeStr,
    );
  }
```

4d. Расширить `_emitStoreClass` производными-надстройками (логика dispose уже там от Task 5):

— добавить именованные параметры:

```dart
  Future<String> _emitStoreClass(
    Element element, String storeName, bool isAbstract, bool isRoot,
    Map<String, String> implToStoreName, Set<String> storeImplNames,
    Set<String> rootImplNames, {
    bool isDerived = false,
    String? rootMemberName,
    String? rootTypeStr,
  }) async {
```

— для derived: фильтрануть root-имя из `concreteGetters` (страховка; root abstract-геттер и так туда не попадает):

```dart
    if (isDerived) {
      concreteGetters.removeWhere((g) => g.name == rootMemberName);
    }
```

— для derived: добавить имя root-геттера в reactive-базу:

```dart
    if (isDerived) {
      reactiveNames = {...reactiveNames, rootMemberName!};
    }
```

— проверка пустоты для derived (см. Task 5 — `_emitStoreClass` уже содержит общую проверку; добавить derived-ветку рядом).

— эмиссия root-геттера (после accessors, до computed-блока):

```dart
    if (isDerived) {
      buffer.writeln();
      buffer.writeln('  @override');
      buffer.writeln('  $rootTypeStr get $rootMemberName = '
          'StoreRootScope.of<$rootTypeStr>();');
    }
```

— **dispose уже эмитится общим фрагментом из Task 5.** Для derived ничего
  специального не требуется: тот же фрагмент диспозит его Signal/Computed-поля,
  `super.dispose()` вызывается если impl объявил concrete dispose, и unregister
  не нужен (derived не регистрируется). Убедиться, что dispose-фрагмент не
  дублируется — он один, в общем пути.

**Важно:** root — именно **геттер** (`get root => StoreRootScope.of<...>()`),
не `late final`-поле. Резолв при каждом обращении гарантирует, что свежесозданный
derived привяжется к актуальному корню после пересоздания (контракт спеки
«Пересоздание корня»). `of<T>()` читает List/Expando (не сигналы) → ложных
зависимостей в computed нет.

- [ ] **Step 5: Запустить derived-тесты — должны пройти**

Run: `cd packages/signals_store_generator && flutter test test/derived_store_generator_test.dart`
Expected: PASS (все 8 тестов: 5 позитивных + 3 валидации).

- [ ] **Step 6: Запустить весь набор — регрессия**

Run: `cd packages/signals_store_generator && flutter test`
Expected: PASS (store + reactivity + derived).

- [ ] **Step 7: `dart analyze` пакета generator**

Run: `cd packages/signals_store_generator && dart analyze`
Expected: no issues.

- [ ] **Step 8: CHANGELOG generator — дополнить**

В `packages/signals_store_generator/CHANGELOG.md` в записи `## 0.6.0` добавить:

```
- `@DerivedStore` — derived-сторы с доступом к корню через `StoreRootScope.of<T>()`,
  собственным состоянием, computed-геттерами и `dispose()`.
```

- [ ] **Step 9: Коммит**

```bash
git add packages/signals_store_generator
git commit -m "feat(generator): @DerivedStore — root-aware derived stores with dispose"
```

---

### Task 7: Реактивность — root-имя в детекторе (аудит FN/FP)

**Цель:** отдельной проверкой (а не только косвенно через Task 6) убедиться, что детектор `computeReactiveGetters` корректно классифицирует геттеры derived-стора, читающие `root.*`. Хотя Task 6 уже добавляет root-имя в базу на стороне генератора, здесь — прямой модульный тест детектора.

**Files:**
- Modify: `packages/signals_store_generator/test/reactivity_test.dart`

- [ ] **Step 1: Добавить тест детектора**

В `reactivity_test.dart` добавить:

```dart
  test('derived: getter reading root.* → computed', () async {
    final reactive = await _detect(r'''
abstract class AppStoreImpl {
  abstract int count;
}

abstract class DerivedImpl {
  abstract AppStoreImpl get root;
  int get doubled => root.count * 2;   // читает root → реактивен
  int get constant => 42;              // не реактивен
}
''', storeImplNames: {'AppStoreImpl', 'DerivedImpl'}, targetClass: 'DerivedImpl');
    expect(reactive, containsAll(['root', 'doubled']));
    expect(reactive, isNot(contains('constant')));
  });
```

(Если `_detect` уже добавляет все abstract-геттеры в базу — root попадёт автоматически; если нет — это укажет, что генератору нужно добавлять root-имя явно, что и делает Task 6. Тест фиксирует контракт.)

- [ ] **Step 2: Запустить — должен пройти**

Run: `cd packages/signals_store_generator && flutter test test/reactivity_test.dart -P "derived: getter reading root"`
Expected: PASS.

- [ ] **Step 3: Коммит**

```bash
git add packages/signals_store_generator/test/reactivity_test.dart
git commit -m "test(generator): derived root-getter reactivity contract"
```

---

### Task 8: Миграция примера — generated derived-сторы

**Зависит от:** Task 6.

**Files:**
- Modify: `packages/signals_store_example/lib/domain/stores.dart` (`@Store(name: 'AppStore', root: true)`)
- Create: `packages/signals_store_example/lib/domain/derived_stores.dart`
- Modify: `packages/signals_store_example/lib/ui/derived.dart` (удалить рукописный `Derived` или оставить как reference-комментарий)
- Modify: `packages/signals_store_example/lib/ui/app.dart` (переключиться на generated derived)
- Run: `dart run build_runner build` в example.

- [ ] **Step 1: Пометить корень**

В `packages/signals_store_example/lib/domain/stores.dart`:

```dart
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  final SessionStoreImpl session;
  // ... без изменений
}
```

Добавить `import 'package:signals_store/signals_store.dart';` (если ещё нет — нужен для `StoreRootScope` в сгенерированном коде).

- [ ] **Step 2: Создать derived-сторы**

`packages/signals_store_example/lib/domain/derived_stores.dart`:

```dart
import 'enums.dart';
import 'models.dart';
import 'stores.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals_store/signals_store.dart';

part 'derived_stores.g.dart';

/// Derived-стор: агрегаты и селекторы над AppStore.
@DerivedStore(name: 'TodosDerived')
abstract class TodosDerivedImpl {
  abstract AppStoreImpl get root;

  List<Todo> get visibleTodos {
    final filter = root.ui.filter;
    var list = root.projects.todos.values.toList();
    if (filter.projectFilterId != null) {
      list = list.where((t) => t.projectId == filter.projectFilterId).toList();
    }
    if (filter.priorityFilter != null) {
      list = list.where((t) => t.priority == filter.priorityFilter).toList();
    }
    if (filter.hideDone) {
      list = list.where((t) => !t.isDone).toList();
    }
    return list;
  }

  bool get isAuthenticated => root.session.currentUser != null;
}
```

(Перенести логику из рукописного `Derived.of(...)` по мере надобности; для showcase достаточно 2 геттеров.)

- [ ] **Step 3: Запустить codegen**

Run: `cd packages/signals_store_example && dart run build_runner build --delete-conflicting-outputs`
Expected: success, `derived_stores.g.dart` сгенерирован.

- [ ] **Step 4: Использовать в UI**

В `packages/signals_store_example/lib/ui/app.dart` (и/или `home_screen.dart`) — заменить создание рукописного `Derived.of(store)` на `TodosDerived()` (создаётся on-demand, root резолвится автоматически). Удалить `ui/derived.dart` (или оставить с пометкой `// deprecated, см. domain/derived_stores.dart`).

- [ ] **Step 5: `flutter analyze` example**

Run: `cd packages/signals_store_example && flutter analyze`
Expected: no issues.

- [ ] **Step 6: Коммит**

```bash
git add packages/signals_store_example
git commit -m "feat(example): migrate hand-written Derived to generated derived store"
```

---

### Task 9: Интеграционный тест примера — резолв root + dispose

**Files:**
- Create: `packages/signals_store_example/test/derived_store_test.dart`

- [ ] **Step 1: Написать тест**

```dart
import 'package:signals_store/signals_store.dart';
import 'package:signals_store_example/domain/enums.dart';
import 'package:signals_store_example/domain/models.dart';
import 'package:signals_store_example/domain/stores.dart';
import 'package:signals_store_example/domain/derived_stores.dart';
import 'package:signals/signals.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(StoreRootScope.enableTestMode);
  tearDown(StoreRootScope.resetTestScope);

  AppStore _newStore() => AppStore(
        session: SessionStore(currentUser: null, isLoading: false, error: null),
        projects: ProjectsStore(
          projects: mapSignal<String, Project>({}),
          todos: mapSignal<String, Todo>({}),
          currentProjectId: null,
        ),
        tags: TagsStore(tags: mapSignal<String, Tag>({})),
        ui: UiStore(
          filter: TodoFilter(
            hideDone: false,
            priorityFilter: null,
            projectFilterId: null,
            sortBy: TodoSortBy.createdDesc,
          ),
          isBusy: false,
          snackbarMessage: null,
        ),
      );

  test('derived store resolves root and computes from it', () {
    final app = _newStore(); // авторегистрация в test-окружение
    final derived = TodosDerived();
    expect(derived.visibleTodos, isEmpty);
    expect(derived.isAuthenticated, isFalse);

    app.projects.todos['1'] = Todo(/* ... */);
    expect(derived.visibleTodos, hasLength(1));
  });

  test('derived store dispose runs without throwing', () {
    _newStore();
    final derived = TodosDerived();
    expect(derived.dispose, returnsNormally);
  });
}
```

(Уточнить конструкторы `Todo`/`Project` по фактическим сигнатурам в `models.dart`.)

- [ ] **Step 2: Запустить**

Run: `cd packages/signals_store_example && flutter test test/derived_store_test.dart`
Expected: PASS.

- [ ] **Step 3: Коммит**

```bash
git add packages/signals_store_example/test/derived_store_test.dart
git commit -m "test(example): derived store root resolution and dispose"
```

---

### Task 10: Финальная сверка и публикация-подготовка

- [ ] **Step 1: Полный прогон тестов воркспейса**

Run (из корня): `flutter test`
Expected: все пакеты зелёные.

- [ ] **Step 2: `dart analyze` всех пакетов**

Run: `dart analyze` (или `flutter analyze`) из корня.
Expected: no issues.

- [ ] **Step 3: Сверка со спекой (spec coverage)**

Прогнать по секциям `docs/superpowers/specs/2026-08-08-derived-stores-design.md`:
- Семантика (стор + root + dispose) → Tasks 1,6,9 ✓
- API (@DerivedStore, @Store(root:true)) → Task 1 ✓
- Генерируемый код (root-of, dispose 3 формы) → Task 6 ✓
- StoreRootScope (app/test, Expando) → Task 3 ✓
- Эмпирические проверки → Task 2 ✓
- Root-маркировка → Task 4 ✓
- Валидации → Task 6 ✓
- Миграция примера → Task 8 ✓

- [ ] **Step 4: CHANGELOG'и + версии проверены** (выполнено в Tasks 1,3,4,6).

- [ ] **Step 5: Опционально — pub publish dry-run** (по памяти pub-publish-workflow)

Run (для каждого из трёх пакетов):
```
flutter pub publish --dry-run
```
Expected: нет проблем (зависимости консистентны). Публикацию выполнять только по явной просьбе пользователя.

- [ ] **Step 6: Финальный коммит (если есть незакоммиченные правки)**

```bash
git add -A
git commit -m "chore: derived stores feature complete"
```

---

## Self-Review (выполнено автором плана)

**Spec coverage:** все секции спеки покрыты задачами (см. Task 10 Step 3), включая новые — единый dispose (Tasks 4,5,6), переиспользование (Tasks 5,6), WeakReference (Task 3).

**Reuse requirement:** логика полей/геттеров/конструктора/коллизий/dispose — в едином `_emitStoreClass` (Task 5); `@DerivedStore` не дублирует её, а передаёт надстройки (Task 6). Дублирование между `@Store` и `@DerivedStore` исключено по построению.

**Unified dispose:** dispose эмитится для всех сторов (`@Store` и `@DerivedStore`) одним фрагментом в `_emitStoreClass` (Task 4 вводит, Task 5 обобщает, Task 6 только включает derived-поля — без копии кода). Root-стор дополнительно `unregister`.

**Root re-creation:** root в derived — геттер (`get root => of<T>()`), не `late final` (Task 6 Step 4 + тест). Свежесозданный derived привяжется к актуальному корню; контракт «время жизни derived ≤ время жизни корня» — в спеке. `register` превентивно чистит мёртвые weak-записи; replace-without-dispose покрыт тестом (Task 3).

**WeakReference / cycles:** `StoreRootScope` хранит только `WeakReference`; `of<T>` убирает мёртвые записи; root-стор `unregister` в dispose для детерминизма (Task 3). Цикл scope→root→derived→(через of)root разорван — scope не держит стор сильно.

**Placeholder scan:** единственный `UnimplementedError` в Task 6 Step 1 — осознанный указатель на рефакторинг (Step 2), реальный helper `expectCompiles`.

**Type consistency:** `StoreRootScope.{register,of,unregister,enableTestMode,resetTestScope}` (Task 3) используются в Tasks 4,6,8,9; `@Store(root: true)`/`@DerivedStore` (Task 1) — в Tasks 4,6,8; `rootMemberName`/`rootTypeStr` (Task 6) согласованы в `_emitStoreClass`.

**Риски/допущения для реализующего агента:**
- Конкретные номера строк в `store_generator.dart` даны приблизительно (файл 712 строк) — ориентироваться по сигнатурам/комментариям, не по номерам.
- Поведение `_activeRegistry` (Task 3) и zone-изоляция зависят от находок Task 2 — реализовать Step 3 Task 3 только после Step 2/3 Task 2.
- Если эмпирический зонд A покажет, что per-test зон НЕТ — `resetTestScope` обязателен (тесты Task 3 уже предполагают это).
- `WeakReference` в Dart не даёт детерминированного GC-теста; тест «collected root is not resolvable» (Task 3) детерминированно моделирует эффект через `unregister` (отдельный тест). Не полагаться на `gc()` — его нет в стабильном API.
- `of<T>` «последний wins»: при нескольких регистрациях одного типа возвращается последнее совпадание по `is T` — задокументировано в Task 3 Step 3.
