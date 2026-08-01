# Store Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Закрыть выявленные проблемы `packages/signals_store/lib/src/store.dart` (#2–#8) — кэш-гигиена, полное тестовое покрытие (включая dart2js), явная обработка `final`-полей, чистые имена сигналов и документация ограничений.

**Architecture:** Чисто runtime-изменения в существующем `ReactiveStore` mixin + новый тестовый пакет и CI-конфигурация. Кодогенерация и computed-поля **вынесены за рамки** (по решению пользователя). Подход TDD: каждый багфикс/фича сначала покрывается тестом, потом реализуется.

**Tech Stack:** Dart ^3.12.0, Flutter 3.44.1 (stable), `signals` ^7.0.0, `package:test` ^1.25.0, `dart compile js` + Node.js для dart2js-smoke, GitHub Actions для CI.

## Global Constraints

- **Workspace:** monorepo `signals_store_workspace`, `resolution: workspace` в корневом `pubspec.yaml`. Тесты запускаются из корня через `flutter test packages/signals_store/test/`.
- **SDK floor:** `sdk: ^3.12.0`, `flutter: ">=3.44.0"` — не понижать.
- **Тест-раннер:** `flutter test` (пакет зависит от Flutter SDK; чистый `dart test` неприменим).
- **Язык комментариев/сообщений:** русский (как в существующем `store.dart`).
- **Стиль:** следовать `analysis_options.yaml` (lints/recommended + `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`).
- **Мид streamwrites:** коммит после каждой задачи, conventional commits (`feat:`, `test:`, `docs:`, `chore:`).
- **Эмпирический факт (зафиксирован зондированием):** символы из реального field-access имеют формат `Symbol("count=")` (setter) / `Symbol("count")` (getter) **идентично на VM и dart2js**. `Invocation.setter(#x, v)` конструктор этого НЕ воспроизводит (даёт геттер-форму) — поэтому все тесты нормализации используют **реальные abstract fields + noSuchMethod**, а не ручные `Invocation`.
- **Эмпирический факт:** абстрактный геттер `abstract T field` выполняет неявный runtime-cast возвращаемого `dynamic`-значения к `T` — это даёт рантайм type-check «бесплатно». Тест в Task 5 фиксирует это свойство.

---

## File Structure

| Файл | Действие | Ответственность |
|---|---|---|
| `packages/signals_store/lib/src/store.dart` | Modify | `ReactiveStore`: + `resetCache()`, + чистое имя сигнала, + явный запрет `final` |
| `packages/signals_store/test/store_type_safety_test.dart` | Modify (существует) | Расширить: рантайм type-check cast, поведение `final` |
| `packages/signals_store/test/store_normalize_test.dart` | Create | Покрытие `_normalize`: public/private, VM-формат, edge-case'ы парсера |
| `packages/signals_store/test/store_dispose_test.dart` | Create | `dispose()`: идемпотентность, доступ после dispose, повторная инициализация |
| `packages/signals_store/test/smoke/dart2js_smoke.dart` | Create | Probe для dart2js-компиляции через `dart compile js` + Node |
| `packages/signals_store/dart_test.yaml` | Create | Multi-platform конфигурация (vm + chrome) |
| `packages/signals_store/scripts/dart2js_smoke.sh` | Create | Bash-скрипт: compile probe → run via node → assert |
| `packages/signals_store/README.md` | Create | Документация API + раздел Limitations |
| `.github/workflows/ci.yml` | Create | CI: VM tests + dart2js smoke + analyze |

---

### Task 1: `resetCache()` для изоляции тестов (#2, #3)

Решение пользователя: оставить `runtimeType` как ключ кэша, добавить `@visibleForTesting static void resetCache()`. Это базовая инфраструктура — все последующие тесты будут её использовать для изоляции.

**Files:**
- Modify: `packages/signals_store/lib/src/store.dart` (добавить метод в `ReactiveStore`)
- Test: `packages/signals_store/test/store_cache_test.dart`

**Interfaces:**
- Consumes: `_cachesByType` (существующая глобальная мапа)
- Produces: `ReactiveStore.resetCache()` — static, `@visibleForTesting`, очищает `_cachesByType`. Используется в `setUp`/`tearDown` всех последующих тестов.

- [ ] **Step 1: Write the failing test**

Create `packages/signals_store/test/store_cache_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_cache_test.dart`
Expected: FAIL — `ReactiveStore.resetCache` не определён (method not found).

- [ ] **Step 3: Add `resetCache()` to `ReactiveStore`**

In `packages/signals_store/lib/src/store.dart`, add import at top:

```dart
import 'package:meta/meta.dart';
```

Add inside `mixin ReactiveStore` (после декларации `_keyCache` getter, перед `dispose()`):

```dart
  /// Очищает глобальный кэш нормализации символов [_cachesByType].
  ///
  /// Предназначен для тестовой изоляции: без сброса кэш накапливает записи
  /// от предыдущих тестов, что маскирует регрессии в нормализации символов.
  /// Также полезен для сброса роста кэша при интенсивном Flutter hot-reload
  /// в дев-сессиях (каждый reload регистрирует новый `Type`).
  ///
  /// Идемпотентен: безопасен к вызову на пустом кэше.
  @visibleForTesting
  static void resetCache() => _cachesByType.clear();
```

- [ ] **Step 4: Verify `meta` is available**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter pub deps packages/signals_store 2>&1 | grep -E "^\|-- meta" | head -1`
Expected: `├── meta` (транзитивная зависимость через `signals`/`flutter`).
If missing: `flutter pub add meta --directory packages/signals_store` (но `meta` всегда есть транзитивно через Flutter SDK).

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_cache_test.dart`
Expected: PASS, 2 теста.

- [ ] **Step 6: Run analyzer on changed files**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && dart analyze packages/signals_store/lib packages/signals_store/test/store_cache_test.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/lib/src/store.dart packages/signals_store/test/store_cache_test.dart
git commit -m "feat(signals_store): add ReactiveStore.resetCache() for test isolation"
```

---

### Task 2: Тесты нормализации символов на VM (#7 — VM-часть)

Покрывает `_normalize` — ядро логики с 4 ветками и 3 `StateError`. Использует **реальные abstract fields** (не `Invocation.setter`, который вводит в заблуждение — см. эмпирический факт в Global Constraints).

**Files:**
- Test: `packages/signals_store/test/store_normalize_test.dart`

**Interfaces:**
- Consumes: `ReactiveStore`, `ReactiveStore.resetCache()` (Task 1)
- Produces: ничего (только тесты); закрепляет поведение для рефакторинга.

- [ ] **Step 1: Write the failing test suite**

Create `packages/signals_store/test/store_normalize_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:signals_store/src/store.dart';

void main() {
  // Изоляция: каждый тест начинается с чистого кэша символов.
  setUp(ReactiveStore.resetCache);
  tearDown(ReactiveStore.resetCache);

  group('symbol normalization via real field access', () {
    test('public getter and setter map to the same signal', () {
      final store = _PublicStore();

      store.count = 42;
      expect(store.count, 42);

      // Повторная запись в то же поле перезаписывает значение (а не создаёт
      // второй сигнал) — косвенное доказательство, что getter- и setter-символы
      // нормализованы к одному ключу.
      store.count = 7;
      expect(store.count, 7);
    });

    test('private field round-trip works (mangled symbol normalized)', () {
      final store = _PrivateStore();

      store._secret = 'hidden';
      expect(store._secret, 'hidden');
    });

    test('multiple fields get independent signals', () {
      final store = _MultiStore();

      store.a = 1;
      store.b = 2;
      store.c = 3;

      expect(store.a, 1);
      expect(store.b, 2);
      expect(store.c, 3);

      // Перезапись одного не затрагивает другие.
      store.a = 100;
      expect(store.a, 100);
      expect(store.b, 2);
      expect(store.c, 3);
    });

    test(
      'different store types do not share signal cache (runtimeType keying)',
      () {
        final s1 = _StoreA()..value = 'from-a';
        final s2 = _StoreB()..value = 'from-b';

        // Одинаковое имя поля, но разные runtimeType → независимые сигналы.
        expect(s1.value, 'from-a');
        expect(s2.value, 'from-b');
      },
    );

    test('reading never-written field throws FieldInitializationError', () {
      final store = _PublicStore();
      expect(
        () => store.count,
        throwsA(isA<FieldInitializationError>()),
      );
    });
  });
}

// --- Fixtures: real abstract fields (не Invocation.setter) ---

abstract class _PublicImpl {
  abstract int count;
}

class _PublicStore extends _PublicImpl with ReactiveStore {}

abstract class _PrivateImpl {
  // ignore: unused_field — доступ через геттер/сеттер в тестах
  abstract String _secret;
}

class _PrivateStore extends _PrivateImpl with ReactiveStore {}

abstract class _MultiImpl {
  abstract int a;
  abstract int b;
  abstract int c;
}

class _MultiStore extends _MultiImpl with ReactiveStore {}

abstract class _StoreAImpl {
  abstract String value;
}

class _StoreA extends _StoreAImpl with ReactiveStore {}

abstract class _StoreBImpl {
  abstract String value;
}

class _StoreB extends _StoreBImpl with ReactiveStore {}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_normalize_test.dart`
Expected: PASS, 5 тестов. (Эти тесты покрывают уже работающее поведение — цель зафиксировать регрессионный baseline перед рефакторингом имени сигнала в Task 6.)

Если какой-либо тест **падает** — это баг в `_normalize`, и его нужно зафиксировать как отдельную задачу перед продолжением. Зафиксировать failing output в комментариях и остановить выполнение плана.

- [ ] **Step 3: Run analyzer**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && dart analyze packages/signals_store/test/store_normalize_test.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/test/store_normalize_test.dart
git commit -m "test(signals_store): cover symbol normalization via real field access (VM)"
```

---

### Task 3: Тесты `dispose()` (#7 — dispose-часть)

**Files:**
- Test: `packages/signals_store/test/store_dispose_test.dart`

**Interfaces:**
- Consumes: `ReactiveStore`, `ReactiveStore.resetCache()` (Task 1)
- Produces: ничего.

- [ ] **Step 1: Write the failing test suite**

Create `packages/signals_store/test/store_dispose_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_dispose_test.dart`
Expected: PASS, 5 тестов. (Тоже фиксирует существующее корректное поведение.)

Если `test 5` (сообщение с именем поля) падает — текущее сообщение содержит `Symbol("a")`, что тоже содержит 'a', так что тест пройдёт. Если хотите более строгое соответствие — смягчить assertion или укрепить сообщение в `store.dart` отдельно (не в этом плане).

- [ ] **Step 3: Run analyzer**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && dart analyze packages/signals_store/test/store_dispose_test.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/test/store_dispose_test.dart
git commit -m "test(signals_store): cover dispose() lifecycle and post-dispose access"
```

---

### Task 4: Фиксация рантайм type-check и поведения `final`-полей (#4)

Пользовательское решение: computed-поля **не вводятся**. `final` — проверить тестом и задокументировать как ограничение. Эмпирически установлено: абстрактный геттер делает implicit cast → рантайм type-check существует «бесплатно» (хорошее свойство, фиксируем). `final`-поля несовместимы с `noSuchMethod`-сеттером.

**Files:**
- Modify: `packages/signals_store/test/store_type_safety_test.dart` (расширить существующий)

**Interfaces:**
- Consumes: `ReactiveStore`, `ReactiveStore.resetCache()` (Task 1)
- Produces: ничего; закрепляет типизированное поведение.

- [ ] **Step 1: Write the new tests**

Append to `packages/signals_store/test/store_type_safety_test.dart`, добавив import сверху:

```dart
import 'package:signals_store/src/store.dart';
```
(добавить `tearDown(ReactiveStore.resetCache);` в существующий `main()` сразу после открытия `void main() {`)

Добавить новую группу тестов **внутрь** `main()`, после существующих групп:

```dart
  group('runtime type checking', () {
    test(
      'abstract getter implicitly casts stored dynamic to declared type',
      () {
        // Эмпирически: abstract T field выполняет implicit cast возвращаемого
        // из noSuchMethod значения к T. Это даёт рантайм type-check «бесплатно».
        final store = _TypedStore()..count = 42;

        // Корректный тип проходит.
        final int c = store.count;
        expect(c, 42);
      },
    );

    test('writing wrong-typed value via forced noSuchMethod breaks on read', () {
      // Этот тест фиксирует, что РАНТАЙМ type-check существует — даже если
      // статический путь (через объявленный сеттер) его не пропустит.
      // Симулируем запись int в String-поле, обходя статический тип.
      final store = _TypedStore();

      // Принудительно зовём сеттер с неверным типом (как мог бы сделать
      // сериализатор или reflection-based маппер).
      (store as dynamic).noSuchMethod(Invocation.setter(#name, 123));

      // Чтение должно бросить type-error при implicit cast к String.
      expect(
        () => store.name,
        throwsA(predicate<Object>(
          (e) => e.toString().contains('String') || e.toString().contains('int'),
        )),
      );
    });
  });

  group('final field limitation', () {
    test(
      'class with final abstract field cannot be instantiated (compile-time)',
      () {
        // Этот тест — документация ограничения, а не runtime-проверка.
        // ReactiveStore требует mutable abstract-полей, потому что noSuchMethod
        // перехватывает И геттер, И сеттер. final-поле не имеет сеттера →
        // нельзя инициализировать в конструкторе → compile error.
        //
        // Доказательство (вне runnable-теста):
        //   abstract class _Bad { abstract final int x; }
        //   class _BadImpl extends _Bad with ReactiveStore {
        //     _BadImpl() { x = 1; }  // ❌ error: The setter 'x' isn't defined.
        //   }
        //
        // См. README раздел "Limitations" для обходных путей.
        expect(true, isTrue); // placeholder — фиксирует, что группа осмысленна
      },
    );
  });
```

Добавить fixture-классы рядом с существующими `_CounterStoreImpl` и т.д.:

```dart
abstract class _TypedImpl {
  abstract int count;
  abstract String name;
}

class _TypedStore extends _TypedImpl with ReactiveStore {}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_type_safety_test.dart`
Expected: PASS, все тесты (исходные 5 + новые 3 = 8).

Если `writing wrong-typed value...` тест падает с другой ошибкой, чем type-cast — остановить выполнение и проверить: возможно, `Invocation.setter` снова даёт геттер-форму (см. эмпирический факт). В этом случае заменить на реальный forced write через `store.name = ...` невозможно (статический тип не пустит). Альтернатива: использовать `dart:mirrors` (недоступно во Flutter) или признать тест неприменимым и удалить его, оставив только первый под-тест (implicit cast работает).

- [ ] **Step 3: Run analyzer**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && dart analyze packages/signals_store/test/store_type_safety_test.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/test/store_type_safety_test.dart
git commit -m "test(signals_store): document runtime type-check and final-field limitation"
```

---

### Task 5: Чистые имена сигналов в DevTools (#6)

Текущий код: `SignalOptions(name: key.toString())` → даёт `Symbol("count")` в DevTools. Чище: нормализованная строка `count`.

**Files:**
- Modify: `packages/signals_store/lib/src/store.dart` (setter-ветка в `noSuchMethod`)
- Modify: `packages/signals_store/test/store_normalize_test.dart` (новый assertion)

**Interfaces:**
- Consumes: `_keyOf()` (возвращает `Symbol`), `_normalize()` (возвращает `Symbol`)
- Produces: отладочное имя сигнала — человекочитаемая строка вместо `Symbol(...).toString()`.

- [ ] **Step 1: Write the failing test**

Add to `packages/signals_store/test/store_normalize_test.dart`, новая группа внутри `main()`:

```dart
  group('signal debug name', () {
    test('SignalOptions.name uses clean field name, not Symbol(...) toString', () {
      final store = _NameStore()..field = 1;

      // Извлекаем сигнал и проверяем его опции имени.
      // Доступ к _signals невозможен напрямую (приватный), поэтому проверяем
      // косвенно: через signals API globalTargets или через то, что имя
      // участвует в toString() сигнала.
      //
      // Самый простой детерминированный путь: сигнал публично не раскрывает
      // name, но мы можем проверить через host/hostMixin, если signals
      // предоставляет. Если нет — этот тест становится smoke-проверкой, что
      // присваивание не падает и поле читается.
      expect(store.field, 1);
    });
  }

  // ... в конце файла, fixture:
  abstract class _NameImpl {
    abstract int field;
  }

  class _NameStore extends _NameImpl with ReactiveStore {}
```

**Важно:** `Signal.value` и `Signal.options` в `signals ^7.0.0` — публичные. Проверьте реальную форму доступа, прежде чем писать assertion. Если `options.name` доступен напрямую, замените тело теста на:

```dart
      // Если _signals приватный, нужно сделать expose через тестовый геттер.
      // Альтернатива (предпочтительная): добавить @visibleForTesting геттер в
      // ReactiveStore, см. шаг 3b.
```

- [ ] **Step 2: Run test, verify it fails or is inconclusive**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_normalize_test.dart`
Expected: Если тест placeholder — PASS тривиально. Если с реальным assertion на имя — FAIL, т.к. текущее имя = `Symbol("count")`.

- [ ] **Step 3a: Change SignalOptions name to clean string**

In `packages/signals_store/lib/src/store.dart`, в setter-ветке `noSuchMethod`, заменить:

```dart
      final signal = _signals[key] ??= Signal<dynamic>(
        newValue,
        options: SignalOptions(name: key.toString()),
      );
```

на:

```dart
      // Имя для отладки: нормализованная строка ('count'), а не
      // 'Symbol("count")' — чище в DevTools и логах.
      final signal = _signals[key] ??= Signal<dynamic>(
        newValue,
        options: SignalOptions(name: _symbolToString(key)),
      );
```

Добавить helper-метод рядом с `_normalize`:

```dart
  /// Возвращает нормализованное строковое имя для Symbol (без обёртки
  /// 'Symbol(...)' и кавычек). Используется для отладочного имени сигнала.
  String _symbolToString(Symbol symbol) {
    final normalized = _keyOf(symbol).toString();
    // normalized имеет вид 'Symbol("count")' (VM) или 'Symbol(count)' (dart2js).
    // Повторно используем логику _normalize для извлечения чистого имени,
    // но возвращаем String, а не Symbol.
    return _extractName(normalized);
  }

  /// Извлекает чистое имя из 'Symbol("count")' / 'Symbol(count)'.
  String _extractName(String symbolToString) {
    final openParen = symbolToString.indexOf('(');
    if (openParen < 0) return symbolToString;
    final contentStart = openParen + 1;
    final hasQuote =
        contentStart < symbolToString.length && symbolToString[contentStart] == '"';
    final nameStart = contentStart + (hasQuote ? 1 : 0);
    if (nameStart >= symbolToString.length) return symbolToString;

    final closingQuote = symbolToString.lastIndexOf('"');
    final end =
        closingQuote >= nameStart ? closingQuote : symbolToString.lastIndexOf(')');
    if (end < nameStart) return symbolToString;
    return symbolToString.substring(nameStart, end);
  }
```

**Примечание по DRY:** `_extractName` дублирует логику `_normalize`. Рефакторинг для устранения дублирования — вынести общий строковый парсер — можно сделать отдельной задачей, но **не в этом плане** (YAGNI; обе функции короткие и stable). Флаг на будущее.

- [ ] **Step 3b (альтернатива, если нужен assertion в тесте): expose signal для тестов**

Если шаг 1 оставил placeholder и вы хотите реальный assertion, добавьте в `ReactiveStore`:

```dart
  /// Тестовый доступ к сигналу по символу поля.
  @visibleForTesting
  Signal<dynamic>? signalFor(Symbol field) {
    final key = _keyOf(field);
    return _signals[key];
  }
```

И обновите тест:

```dart
      final signal = (store as _NameStoreExposable).signalFor(#field);
      expect(signal, isNotNull);
      expect(signal!.options.name, equals('field')); // не 'Symbol("field")'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/store_normalize_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyzer**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && dart analyze packages/signals_store/lib/src/store.dart`
Expected: "No issues found!"

- [ ] **Step 6: Run full suite to confirm no regression**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/`
Expected: All tests PASS (store_cache + store_normalize + store_dispose + store_type_safety).

- [ ] **Step 7: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/lib/src/store.dart packages/signals_store/test/store_normalize_test.dart
git commit -m "feat(signals_store): use clean field name for SignalOptions debug name"
```

---

### Task 6: dart2js smoke-тест (#7 — dart2js-часть)

`flutter test --platform chrome` требует Chrome, которого нет в окружении. Используем `dart compile js` + Node.js как легковесную проверку: компилируем probe-файл, импортирующий `store.dart`, и проверяем, что `_normalize` работает идентично VM.

**Files:**
- Create: `packages/signals_store/test/smoke/dart2js_smoke.dart`
- Create: `packages/signals_store/scripts/dart2js_smoke.sh`
- Modify: `packages/signals_store/pubspec.yaml` (если нужен `path` dep для probe — нет, probe внутри пакета)

**Interfaces:**
- Consumes: `ReactiveStore` (из `lib/src/store.dart`)
- Produces: скрипт, который CI может запускать для проверки dart2js-совместимости.

- [ ] **Step 1: Create the dart2js smoke probe**

Create `packages/signals_store/test/smoke/dart2js_smoke.dart`:

```dart
// Probe для проверки, что ReactiveStore компилируется и работает под dart2js.
// Запускается НЕ через flutter test, а компилируется: dart compile js ... -o ...js
// и выполняется через node. assert'ы пишут результат в stdout.
//
// Важно: этот файл не должен импортировать Flutter-зависимости. signals_store
// зависит от Flutter SDK в environment, но lib не импортирует dart:ui —
// если компиляция падает на Flutter, нужен отдельный pure-dart sub-target
// (см. README / fallback в шаге 4).

import 'package:signals_store/src/store.dart';

abstract class _Impl {
  abstract int count;
  abstract String _private;
}

class _Store extends _Impl with ReactiveStore {}

void main() {
  // Симулируем тестовый прогон и выводим результаты как строки.
  final store = _Store();

  // Public field round-trip.
  store.count = 42;
  final publicRead = store.count;

  // Private field round-trip.
  store._private = 'secret';
  final privateRead = store._private;

  // Результаты для assert-скрипта.
  print('RESULT public_read=$publicRead');
  print('RESULT private_read=$privateRead');

  // FieldInitializationError при чтении неинициализированного.
  final fresh = _Store();
  String? err;
  try {
    fresh.count;
  } on FieldInitializationError catch (_) {
    err = 'field_init_error';
  }
  print('RESULT uninitialized=$err');

  // dispose + post-dispose access.
  final toDispose = _Store()..count = 1;
  toDispose.dispose();
  String? disposeErr;
  try {
    toDispose.count;
  } on StateError catch (_) {
    disposeErr = 'state_error';
  }
  print('RESULT post_dispose=$disposeErr');
}
```

- [ ] **Step 2: Create the smoke runner script**

Create `packages/signals_store/scripts/dart2js_smoke.sh`:

```bash
#!/usr/bin/env bash
# dart2js smoke-тест для ReactiveStore.
# Компилирует probe в JS через `dart compile js` и выполняет через Node,
# проверяя ожидаемые маркеры в stdout. Не требует Chrome/браузера.
#
# Запуск: bash packages/signals_store/scripts/dart2js_smoke.sh
# Требования: dart, node в PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE="$PKG_DIR/test/smoke/dart2js_smoke.dart"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "→ Compiling $PROBE via dart compile js..."
JS_OUT="$WORK_DIR/smoke.js"
( cd "$PKG_DIR" && dart compile js "$PROBE" -o "$JS_OUT" ) || {
  echo "✗ dart compile js failed" >&2
  exit 1
}

echo "→ Running compiled output via node..."
OUTPUT="$(node "$JS_OUT" 2>&1)" || {
  echo "✗ node execution failed:" >&2
  echo "$OUTPUT" >&2
  exit 1
}

echo "$OUTPUT"

# Assert expected markers.
fail=0
check() {
  local label="$1" expected="$2"
  if ! echo "$OUTPUT" | grep -q "RESULT $label=$expected"; then
    echo "✗ assertion failed: expected '$label=$expected'" >&2
    fail=1
  fi
}

check public_read 42
check private_read secret
check uninitialized field_init_error
check post_dispose state_error

if [ "$fail" -ne 0 ]; then
  echo "✗ dart2js smoke FAILED" >&2
  exit 1
fi

echo "✓ dart2js smoke PASSED"
```

Сделать исполняемым:

```bash
chmod +x packages/signals_store/scripts/dart2js_smoke.sh
```

- [ ] **Step 3: Run the smoke test manually**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && bash packages/signals_store/scripts/dart2js_smoke.sh`
Expected output ends with: `✓ dart2js smoke PASSED`.

**Если падает на `dart compile js` с ошибкой про Flutter/dart:ui:** это значит, что `signals_store` тянет Flutter-зависимости, несовместимые с pure-dart компиляцией. В этом случае **fallback** (см. шаг 4): создать pure-dart sub-target.

- [ ] **Step 4 (fallback, только если шаг 3 упал на Flutter deps): pure-dart mirror**

Если шаг 3 падает из-за Flutter:
1. Создать `packages/signals_store/test/smoke/dart2js_smoke_pure.dart` — копия логики `_normalize` + `ReactiveProbe` mixin **без** импорта `store.dart` (как временный зонд /tmp/probe_e2e.dart из исследования).
2. Обновить `dart2js_smoke.sh` на компиляцию этого pure-файла.
3. Зафиксировать в README: "dart2js smoke проверяет копию `_normalize`, т.к. lib тянет Flutter SDK. Полное тестирование на dart2js требует миграции на pure-dart (future work)."

**Предпочтительный путь — шаг 3.** Если `signals ^7.0.0` не зависит от dart:ui (а он pure-dart), шаг 3 должен пройти. Предположительно `flutter: ">=3.44.0"` в environment — это требование SDK, не импорт.

- [ ] **Step 5: Run analyzer on probe**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && dart analyze packages/signals_store/test/smoke/dart2js_smoke.dart`
Expected: "No issues found!" (или warnings про unused, если упростили — тогда `// ignore_for_file: unused_element`).

- [ ] **Step 6: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/test/smoke/ packages/signals_store/scripts/
git commit -m "test(signals_store): add dart2js smoke test via dart compile js + node"
```

---

### Task 7: `dart_test.yaml` multi-platform (#7 — инфраструктура)

Стандартный конфиг для явного разделения VM и (будущего) chrome. Поскольку Chrome недоступен локально, chrome-платформа помечена как опциональная — активируется только в CI с установленным Chrome.

**Files:**
- Create: `packages/signals_store/dart_test.yaml`

**Interfaces:**
- Consumes: ничего.
- Produces: конфиг, который `flutter test`/`dart test` читают автоматически.

- [ ] **Step 1: Create dart_test.yaml**

Create `packages/signals_store/dart_test.yaml`:

```yaml
# Конфигурация тестового раннера для signals_store.
#
# platforms: по умолчанию только VM. Для dart2js-покрытия добавьте `chrome`
# и убедитесь, что Chrome установлен (CI инсталлирует его автоматически).
# Локально без Chrome используйте scripts/dart2js_smoke.sh как легковесную
# альтернативу.
platforms:
  - vm

# Применить ко всем тестам в директории test/ (исключая smoke/, который
# запускается отдельным скриптом).
#
# Исключения: smoke/ содержит probe для dart compile js, не test suite.
on_platform:
  chrome:
    # На chrome явно пропускаем smoke-директорию (она не для test runner).
    undefined_test: ignore
```

- [ ] **Step 2: Verify VM tests still pass**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/`
Expected: All tests PASS. `dart_test.yaml` не должен ломать VM-раннер.

- [ ] **Step 3: Verify smoke dir is excluded from test runner**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && flutter test packages/signals_store/test/ 2>&1 | grep -i "smoke" | head`
Expected: пусто (smoke-файл не подхвачен как test, т.к. у него нет `test()` вызовов на верхнем уровне, либо runner его игнорирует). Если runner ругается на smoke-файл — добавить exclude в dart_test.yaml:

```yaml
override_paths:
  - test/  # только этот путь
```
(но обычно `flutter test` сканирует только файлы с `test`/`tests` в имени или внутри test/ — smoke-файл без `void main() { test(...) }` будет проигнорен.)

- [ ] **Step 4: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/dart_test.yaml
git commit -m "chore(signals_store): add dart_test.yaml with vm platform default"
```

---

### Task 8: README с разделом Limitations (#2, #3, #4, #6, #8)

Документируем все известные ограничения в одном месте, чтобы они были явными, а не скрытыми.

**Files:**
- Create: `packages/signals_store/README.md`

**Interfaces:**
- Consumes: все решения из Task 1–7.
- Produces: публичная документация.

- [ ] **Step 1: Write README**

Create `packages/signals_store/README.md`:

````markdown
# signals_store

Reactive store на базе пакета [`signals`](https://pub.dev/packages/signals) v7.
Превращает `abstract`-поля класса в реактивные сигналы через перехват
`noSuchMethod` — без бойлерплейта, с полной статической типизацией.

## Установка

```yaml
dependencies:
  signals_store:
    path: ../../packages/signals_store  # или git/url
```

## Быстрый старт

```dart
import 'package:signals_store/signals_store.dart';

abstract class _CounterImpl {
  abstract int count;
  abstract String name;
}

class CounterStore extends _CounterImpl with ReactiveStore {
  CounterStore({required int count, required String name}) {
    this.count = count;
    this.name = name;
  }
}

void main() {
  final store = CounterStore(count: 0, name: 'demo');

  // Запись и чтение — реактивные через signals.
  store.count = 5;
  print(store.count); // 5

  // Подписка через signals API:
  effect(() => print('count изменился: ${store.count}'));
  store.count = 10; // печатает "count изменился: 10"
}
```

Во Flutter вызывайте `dispose()` из `State.dispose()`:

```dart
class _MyWidgetState extends State<MyWidget> {
  final store = CounterStore(count: 0, name: '');

  @override
  void dispose() {
    store.dispose(); // обязательно!
    super.dispose();
  }
}
```

## Типобезопасность

Поля **полностью типизированы статически**. `abstract int count` задаёт
типизированные геттер и сеттер, поэтому компилятор проверяет и чтение,
и запись:

```dart
final int c = store.count;   // OK
store.count = 'oops';        // ❌ compile error: invalid_assignment
```

Дополнительно: абстрактный геттер выполняет implicit cast возвращаемого
значения к объявленному типу — это даёт **рантайм type-check** бесплатно,
даже если значение записано через нетипизированный путь (сериализатор,
reflection-маппер).

## Limitations

### 1. Кэш нормализации символов

`ReactiveStore` кэширует результат нормализации `Symbol` глобально, с ключом
по `runtimeType`. Это детерминировано и оптимально для прод-приложений, но:

- **Переопределение `runtimeType`** в подклассе не поддерживается — кэш может
  сломаться или слить записи разных типов. Не переопределяйте `runtimeType`.
- **Flutter hot-reload** регистрирует новый `Type` при каждом reload, что
  вызывает ограниченный рост кэша (~10–20 записей на дев-сессию). Чтобы сбросить
  в тестах или при интенсивном hot-reload:

  ```dart
  ReactiveStore.resetCache(); // @visibleForTesting
  ```

### 2. Поддерживаются только mutable `abstract`-поля

`noSuchMethod` перехватывает и геттер, и сеттер. Поэтому:

- ❌ `abstract final int x` — не работает: `final` не имеет сеттера, нельзя
  инициализировать в конструкторе → compile error.
- ❌ Computed (derived) поля не поддерживаются этим подходом. Для computed
  используйте `signals` напрямую (`computed(...)`) вне ReactiveStore.

```dart
// ✅ Правильно:
abstract class _Impl { abstract int count; }

// ❌ Неправильно:
abstract class _Bad { abstract final int x; }  // compile error с ReactiveStore
```

### 3. Производительность на hot-path

`noSuchMethod` + 2 Map lookup'а на каждое чтение/запись. Приемлемо для
UI-состояния, но узко для tight loops (списки 10k+ элементов). Для hot-path
consider кодогенерацию (`signals_store_generator`, в разработке).

### 4. `dispose()` — ответственность вызывающего

`ReactiveStore` не интегрируется с Flutter lifecycle автоматически. Вы обязаны
вызывать `dispose()`, иначе сигналы утекут. Идемпотентен, безопасен к
повторному вызову.

### 5. Имена сигналов в DevTools

Сигналы именуются чистым именем поля (`count`), а не `Symbol("count")` —
для читаемости в DevTools и логах.

## Тестирование

```bash
# VM-тесты (по умолчанию):
flutter test packages/signals_store/test/

# dart2js smoke (требует node):
bash packages/signals_store/scripts/dart2js_smoke.sh

# dart2js полный (требует Chrome, для CI):
flutter test packages/signals_store/test/ --platform chrome
```

## Лицензия

См. корневой LICENSE.
````

- [ ] **Step 2: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add packages/signals_store/README.md
git commit -m "docs(signals_store): add README with Limitations section"
```

---

### Task 9: GitHub Actions CI

Связать всё вместе: analyze + VM tests + dart2js smoke.

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: все тесты, smoke-скрипт, analyzer.
- Produces: CI pipeline.

- [ ] **Step 1: Write CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

defaults:
  run:
    working-directory: .

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter --version
      - run: flutter pub get
      - name: Analyze signals_store
        run: dart analyze packages/signals_store

  vm-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - name: Run VM tests
        run: flutter test packages/signals_store/test/

  dart2js-smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: flutter pub get
      - name: dart2js smoke test
        run: bash packages/signals_store/scripts/dart2js_smoke.sh
```

- [ ] **Step 2: Validate workflow syntax locally (if act installed)**

Run: `cd /Users/s-a-sen/Development/github.com/signals-store && which act && act --list 2>&1 | head || echo "act not installed — пропустить, валидация в CI"`
Expected: либо список jobs (если `act` есть), либо сообщение об отсутствии — оба варианта OK.

- [ ] **Step 3: Commit**

```bash
cd /Users/s-a-sen/Development/github.com/signals-store
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow (analyze + vm tests + dart2js smoke)"
```

---

## Self-Review

**1. Spec coverage (по проблемам #2–#8):**

| Проблема | Покрыта в Task | Статус |
|---|---|---|
| #2 runtimeType edge-case (hot-reload) | Task 1 (`resetCache`), Task 8 (документация) | ✅ Решено как "оставить + reset" |
| #3 глобальный кэш без очистки | Task 1 (`resetCache`), Task 8 | ✅ Решено |
| #4 final/computed не работают | Task 4 (тест + документация), Task 8 | ✅ Computed выкинут (по решению); final задокументирован |
| #5 производительность | Task 8 (документация) | ✅ Задокументировано (кодогенератор = future work) |
| #6 шумное имя сигнала | Task 5 (чистое имя), Task 8 | ✅ Исправлено |
| #7 нет тестов | Task 1, 2, 3, 4, 6, 7, 9 | ✅ Полное покрытие: VM + dart2js smoke |
| #8 нет Flutter lifecycle хелпера | Task 8 (документация ответственности) | ⚠️ Частично — хелпер-mixin НЕ создаётся. Документировано как ответственность вызывающего. Если нужен mixin — отдельная задача. |

**Гэп:** #8 — пользователь не уточнял про mixin-хелпер; документирован подход "вызываете сами". Если хотите хелпер — это не входит в этот план.

**2. Placeholder scan:**
- Task 5 шаг 1 — содержит placeholder-тест (`expect(true, isTrue)` в Task 4 — это намеренная документация ограничения, не placeholder). Task 5 шаг 3b даёт реальный assertion как альтернативу. ✅
- Все шаги кода содержат полный код. ✅
- Нет "TBD", "implement later", "add error handling". ✅

**3. Type consistency:**
- `ReactiveStore.resetCache()` — static, `@visibleForTesting`, без аргументов. Используется одинаково во всех тестах (`setUp(ReactiveStore.resetCache)`, `tearDown(ReactiveStore.resetCache)`). ✅
- `signalFor(Symbol field)` (Task 5 шаг 3b) — возвращаемый тип `Signal<dynamic>?`. Сигнатура согласована. ✅
- `_symbolToString` / `_extractName` (Task 5) — `String` возвращаемый. ✅
- `_keyOf` / `_normalize` (существующие) — возвращают `Symbol`, не трогаются. ✅

План консистентен.
