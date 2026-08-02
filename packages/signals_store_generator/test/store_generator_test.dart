// ignore_for_file: lines_longer_than_80_chars

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:signals_store_generator/src/builder.dart';
import 'package:test/test.dart';

import 'helpers/flutter_test_harness.dart';

/// Тесты генератора сторов через `testBuilder`.
///
/// Проверяем инварианты сгенерированного кода через `contains`-матчеры вместо
/// побайтового сравнения: это устойчиво к форматированию (`dartfmt`), но
/// надёжно ловит регрессии в именах классов/полей/сигналов.
void main() {
  late final PackageConfig packageConfig;

  setUpAll(() async {
    // Подменяет buildProcessState.{packageConfigUri,dartSdkPath} и
    // предгенерирует кэш SDK-сводки, иначе под `flutter test` резолвер
    // падает на `Isolate.packageConfigSync`/неверном пути SDK.
    await configureBuildProcessStateForTests();
    packageConfig = await loadWorkspacePackageConfig();
  });

  // Общий заголовок входной библиотеки. `signals` импортируется, т.к.
  // сгенерированный код ссылается на `Signal`/`SignalOptions` (сам генератор
  // их не резолвит — только типы полей, но проверка компилируемости
  // сгенерированного кода — отдельная задача).
  const headers = '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals/signals.dart';
''';

  test('single @Store → single concrete class with one field', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'FirstSomeStore')
      abstract class SomeStoreImpl {
        abstract String name;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('class FirstSomeStore extends SomeStoreImpl'),
        contains('Signal<String> name\$'),
        contains("name: 'FirstSomeStore.name'"),
        contains('String get name => name\$.value;'),
        contains('set name(String value) => name\$.value = value;'),
        contains('FirstSomeStore({required String name})'),
      ]),
    );
  });

  test('multiple @Store annotations on one class → build error, no output asset',
      () async {
    final result = await _runResult(
      packageConfig,
      headers,
      '''
      @Store(name: 'FirstSomeStore')
      @Store(name: 'SecondSomeStore')
      abstract class SomeStoreImpl {
        abstract String name;
      }
      ''',
    );
    // На одном классе допускается ровно одна аннотация @Store.
    expect(result.succeeded, false);
    expect(result.errors, isNotEmpty);
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('multiple fields of different types are all generated', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'CounterStore')
      abstract class CounterImpl {
        abstract int count;
        abstract String name;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('class CounterStore extends CounterImpl'),
        // count.
        contains('Signal<int> count\$'),
        contains('int get count => count\$.value;'),
        contains("name: 'CounterStore.count'"),
        // name.
        contains('Signal<String> name\$'),
        contains('String get name => name\$.value;'),
        contains("name: 'CounterStore.name'"),
        // Конструктор с обоими required-параметрами.
        contains('CounterStore({required int count, required String name})'),
      ]),
    );
  });

  test('nullable field type is preserved', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'NullableStore')
      abstract class NullableImpl {
        abstract int? maybe;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('Signal<int?> maybe\$'),
        contains('required int? maybe'),
        contains('int? get maybe => maybe\$.value;'),
        contains('set maybe(int? value) => maybe\$.value = value;'),
      ]),
    );
  });

  test('a generic field type is rendered as-is', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'ListStore')
      abstract class ListImpl {
        abstract List<String> items;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('Signal<List<String>> items\$'),
        contains('required List<String> items'),
      ]),
    );
  });

  test('class without abstract fields → build error, no output asset',
      () async {
    final result = await _runResult(
      packageConfig,
      headers,
      '''
      @Store(name: 'EmptyStore')
      abstract class EmptyImpl {}
      ''',
    );
    // Генератор бросает InvalidGenerationSource → статус failure и ошибки.
    expect(result.succeeded, false);
    expect(result.errors, isNotEmpty);
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('@Store on a non-class element → build error, no output asset',
      () async {
    final result = await _runResult(
      packageConfig,
      headers,
      '''
      @Store(name: 'XStore')
      const value = 42;
      ''',
    );
    expect(result.succeeded, false);
    expect(result.errors, isNotEmpty);
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  // --- Concrete (pass-through) поля ---

  test('concrete field is passed through as super.param, not Signal-wrapped',
      () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'Holder')
      abstract class HolderImpl {
        final int stable;
        HolderImpl({required this.stable});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('class Holder extends HolderImpl'),
        // Concrete-поле пробрасывается через super-параметр.
        contains('required super.stable'),
        // И НЕ оборачивается в Signal.
        isNot(contains('Signal<int>')),
        isNot(contains('stable\$')),
      ]),
    );
  });

  test('mixed abstract (reactive) + concrete (pass-through) fields', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'Mixed')
      abstract class MixedImpl {
        final int stable;
        abstract String reactive;
        MixedImpl({required this.stable});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Concrete → super-параметр.
        contains('required super.stable'),
        // Reactive → Signal + override-аксессоры.
        contains('Signal<String> reactive\$'),
        contains('@override'),
        contains('String get reactive => reactive\$.value;'),
      ]),
    );
  });

  // --- Область видимости signal-поля (наследуется от исходного поля) ---

  test('public abstract field → public signal field (no underscore prefix)', () async {
    // Публичное поле `count` → публичное signal-поле `count$` (без `_`).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'CounterStore')
      abstract class CounterImpl {
        abstract int count;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Поле-сигнал публичное — без префикса `_`.
        contains('final Signal<int> count\$'),
        contains('count\$ = Signal<int>('),
        contains('int get count => count\$.value;'),
        // И НЕ приватное.
        isNot(contains('_count\$')),
      ]),
    );
  });

  test('private abstract field → private signal field (underscore preserved)', () async {
    // Приватное поле `_count` → приватное signal-поле `_count$`.
    // Видимость наследуется от исходного поля.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'CounterStore')
      abstract class CounterImpl {
        abstract int _count;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Поле-сигнал приватное — префикс `_` сохранён.
        contains('final Signal<int> _count\$'),
        contains('_count\$ = Signal<int>('),
        contains("name: 'CounterStore._count'"),
        contains('int get _count => _count\$.value;'),
        contains('set _count(int value) => _count\$.value = value;'),
        // Параметр конструктора — приватное имя.
        contains('required int _count'),
      ]),
    );
  });

  test('mixed public and private fields keep their respective visibility', () async {
    // Публичное и приватное поля в одном классе: signal-поля наследуют
    // видимость каждого (public → `name$`, private → `_count$`).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'MixedStore')
      abstract class MixedImpl {
        abstract String name;
        abstract int _count;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Публичное поле → публичный signal.
        contains('final Signal<String> name\$'),
        // Приватное поле → приватный signal.
        contains('final Signal<int> _count\$'),
        contains('String get name => name\$.value;'),
        contains('int get _count => _count\$.value;'),
      ]),
    );
  });

  // --- Форма конструктора и декларации класса ---

  test('concrete-only class emits constructor without initializer list', () async {
    // Класс без reactive-полей → конструктор без `:` (нет Signal-инициализаторов).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'TagsStore')
      abstract class TagsImpl {
        final Map<String, int> tags;
        TagsImpl({required this.tags});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('TagsStore({required super.tags});'),
        // Конкретный класс без reactive-полей не имеет Signal-полей/override.
        // (используем `Signal<`, чтобы не матчить упоминание `[Signal]` в doc.)
        isNot(contains('Signal<')),
        isNot(contains('@override')),
      ]),
    );
  });

  test('reactive-only class emits constructor with initializer list', () async {
    // Только reactive-поля → конструктор с инициализатором сигнала, без super.x.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'FilterStore')
      abstract class FilterImpl {
        abstract bool active;
        abstract String? query;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Есть инициализатор сигнала (`: active$ = ...`).
        contains('active\$ = Signal<bool>('),
        contains('query\$ = Signal<String?>('),
        // Нет super-параметров (нет concrete-полей).
        isNot(contains('super.')),
      ]),
    );
  });

  test('generic abstract store emits abstract keyword with type params', () async {
    // Комбинация abstract: true + generics — заголовок с `abstract class` и bounds.
    final generated = await _run(
      packageConfig,
      '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals/signals.dart';

class Result {}
''',
      '''
      @Store(name: 'GenericStore', abstract: true)
      abstract class SomeStore<T, R extends Result> {
        abstract T value;
      }
      ''',
    );
    // Точный заголовок из целевого кейса задачи.
    expect(
      generated,
      contains('abstract class GenericStore<T, R extends Result> '
          'extends SomeStore<T, R>'),
    );
  });

  // --- Вложенные сторы (impl → implementation rewrite) ---

  test('field typed as another @Store impl uses the implementation name', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'InnerStore')
      abstract class InnerStoreImpl {
        abstract int value;
      }

      @Store(name: 'OuterStore')
      abstract class OuterStoreImpl {
        final InnerStoreImpl inner;
        OuterStoreImpl({required this.inner});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // OuterStore должен типизировать поле concrete-имя РЕАЛИЗАЦИИ InnerStore,
        // а не impl-классом InnerStoreImpl.
        contains('required super.inner'),
        // InnerStore-реализация сгенерирована с реактивным полем.
        contains('class InnerStore extends InnerStoreImpl'),
        contains('Signal<int> value\$'),
      ]),
    );
    // Генератор НЕ должен эмитить InvalidType для поля, ссылающегося на
    // ещё-не-существующее имя реализации.
    expect(generated, isNot(contains('InvalidType')));
  });

  test('abstract field typed as another @Store impl uses implementation name', () async {
    // В отличие от concrete-полей (super.x, тип из суперкласса), reactive-поле
    // типизированное impl-классом, рендерится с явным типом → rewrite на имя
    // реализации обязателен.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'InnerStore')
      abstract class InnerStoreImpl {
        abstract int value;
      }

      @Store(name: 'OuterStore')
      abstract class OuterStoreImpl {
        abstract InnerStoreImpl inner;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Reactive-поле получает Signal<InnerStore>, а не InnerStoreImpl —
        // consumer работает с типизированным подстором.
        contains('Signal<InnerStore> inner\$'),
        contains('required InnerStore inner'),
        contains('InnerStore get inner => inner\$.value;'),
      ]),
    );
  });

  test('multiple nested substores form a composition tree', () async {
    // Корневой стор с несколькими подсторами (как AppStore в example):
    // каждый concrete-поле пробрасывается через super-параметр.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'SessionStore')
      abstract class SessionStoreImpl {
        abstract User? currentUser;
      }

      @Store(name: 'SettingsStore')
      abstract class SettingsStoreImpl {
        abstract bool darkMode;
      }

      @Store(name: 'AppStore')
      abstract class AppStoreImpl {
        final SessionStoreImpl session;
        final SettingsStoreImpl settings;
        AppStoreImpl({required this.session, required this.settings});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Все три реализации сгенерированы.
        contains('class SessionStore extends SessionStoreImpl'),
        contains('class SettingsStore extends SettingsStoreImpl'),
        contains('class AppStore extends AppStoreImpl'),
        // Корневой стор пробрасывает оба подстора через super-параметры.
        contains('required super.session'),
        contains('required super.settings'),
        // AppStore не имеет собственных reactive-полей → нет Signal-полей.
        isNot(contains('Signal<SessionStoreImpl>')),
      ]),
    );
  });

  test('deeply nested store chain (A → B → C) generates all levels', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'LeafStore')
      abstract class LeafImpl {
        abstract int value;
      }

      @Store(name: 'MiddleStore')
      abstract class MiddleImpl {
        final LeafImpl leaf;
        MiddleImpl({required this.leaf});
      }

      @Store(name: 'RootStore')
      abstract class RootImpl {
        final MiddleImpl middle;
        RootImpl({required this.middle});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Все уровни дерева сгенерированы.
        contains('class LeafStore extends LeafImpl'),
        contains('Signal<int> value\$'),
        contains('class MiddleStore extends MiddleImpl'),
        contains('required super.leaf'),
        contains('class RootStore extends RootImpl'),
        contains('required super.middle'),
      ]),
    );
    expect(generated, isNot(contains('InvalidType')));
  });

  test('concrete field typed as non-store type is NOT rewritten', () async {
    // Concrete-поле с обычным (не стором) типом рендерится как super.x —
    // rewrite на impl-имя НЕ должен применяться.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'ConfigStore')
      abstract class ConfigImpl {
        final String label;
        abstract int count;
        ConfigImpl({required this.label});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Concrete-поле пробрасывается как есть.
        contains('required super.label'),
        // Reactive-поле обёрнуто в Signal.
        contains('Signal<int> count\$'),
        // Никакого ложного rewrite.
        isNot(contains('Signal<String>')),
      ]),
    );
  });

  test('nullable reactive field typed as @Store impl keeps nullable suffix', () async {
    // Reactive-поле с nullable impl-типом: rewrite `InnerStoreImpl?` → `InnerStore?`.
    // Проверяет ветку nullabilitySuffix == question в _typeStringFor.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'InnerStore')
      abstract class InnerStoreImpl {
        abstract int value;
      }

      @Store(name: 'OuterStore')
      abstract class OuterStoreImpl {
        abstract InnerStoreImpl? maybeInner;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('Signal<InnerStore?> maybeInner\$'),
        contains('required InnerStore? maybeInner'),
        contains('InnerStore? get maybeInner => maybeInner\$.value;'),
        contains('set maybeInner(InnerStore? value)'),
      ]),
    );
  });

  test('reactive field typed as generic @Store impl keeps type args', () async {
    // Reactive-поле типизированное generic-стором: rewrite должен сохранить
    // type-аргументы (`BoxImpl<int>` → `Box<int>`, а не голый `Box`).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'Box')
      abstract class BoxImpl<T> {
        abstract T value;
      }

      @Store(name: 'OuterStore')
      abstract class OuterStoreImpl {
        abstract BoxImpl<int> box;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Type-аргумент <int> сохранён при rewrite impl → implementation.
        contains('Signal<Box<int>> box\$'),
        contains('required Box<int> box'),
        contains('Box<int> get box => box\$.value;'),
        contains('set box(Box<int> value)'),
      ]),
    );
    expect(generated, isNot(contains('Signal<Box> ')));
  });

  test('concrete field typed as generic @Store impl is passed via super param', () async {
    // Concrete-поле типизированное generic-стором: пробрасывается через
    // super-параметр (тип берётся из объявления суперкласса, rewrite для
    // concrete-полей не применяется — см. комментарий в _generateForAnnotation).
    // Generic-стор при этом сохраняет type-параметр в декларации (Box<T>),
    // а конкретизация (<int>) остаётся в типе concrete-поля суперкласса.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'Box')
      abstract class BoxImpl<T> {
        abstract T value;
      }

      @Store(name: 'OuterStore')
      abstract class OuterStoreImpl {
        final BoxImpl<int> box;
        OuterStoreImpl({required this.box});
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // concrete-поле → super-параметр (без Signal-обёртки).
        contains('required super.box'),
        // Generic-стор сохраняет type-параметр в декларации (не конкретизируется).
        contains('class Box<T> extends BoxImpl<T>'),
        // Concrete-поле НЕ обёрнуто в Signal.
        isNot(contains('Signal<BoxImpl<int>>')),
      ]),
    );
  });

  // --- Специальные виды полей: static, late ---

  test('static field in store class is ignored (not a constructor param)', () async {
    // `static const`-поле — это константа класса, а не состояние экземпляра;
    // оно НЕ должно попадать в конструктор сгенерированного стора.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'ConfigStore')
      abstract class ConfigImpl {
        abstract int count;
        static const int maxItems = 100;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // count — реактивное поле.
        contains('Signal<int> count\$'),
        // Конструктор принимает ТОЛЬКО count — без несуществующего super.maxItems.
        contains('ConfigStore({required int count})'),
        isNot(contains('super.maxItems')),
        isNot(contains('maxItems')),
      ]),
    );
  });

  test('late field in store class is ignored (not a super param)', () async {
    // `late`-поле без инициализатора не является ни реактивным (abstract),
    // ни concrete pass-through — оно инициализируется позже вручную и НЕ должно
    // становиться super-параметром (у суперкласса нет такого параметра).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'LazyStore')
      abstract class LazyImpl {
        abstract int count;
        late String label;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // count — реактивное поле.
        contains('Signal<int> count\$'),
        // Конструктор принимает ТОЛЬКО count — без super.label.
        contains('LazyStore({required int count})'),
        isNot(contains('super.label')),
      ]),
    );
  });

  // --- Обобщённые параметры (generics) ---

  test('generic type params are carried over to declaration and extends', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'BoxStore')
      abstract class BoxImpl<T> {
        abstract T value;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Декларация с type param.
        contains('class BoxStore<T> extends BoxImpl<T>'),
        // Поле использует параметр типа.
        contains('Signal<T> value\$'),
        contains('required T value'),
        contains('T get value => value\$.value;'),
      ]),
    );
  });

  test('multiple generic params with bounds are preserved in declaration', () async {
    final generated = await _run(
      packageConfig,
      '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals/signals.dart';

class Result {}
''',
      '''
      @Store(name: 'GenericStore')
      abstract class SomeStore<T, R extends Result> {
        abstract T value;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Bounds сохраняются в декларации наследника.
        contains('class GenericStore<T, R extends Result>'),
        // extends конкретизируется теми же параметрами (без bounds).
        contains('extends SomeStore<T, R>'),
        contains('Signal<T> value\$'),
      ]),
    );
  });

  // --- Абстрактные сторы (@Store(abstract: true)) ---

  test('abstract: true emits `abstract class` keyword', () async {
    final generated = await _run(
      packageConfig,
      '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals/signals.dart';

class Result {}
''',
      '''
      @Store(name: 'GenericStore', abstract: true)
      abstract class SomeStore<T, R extends Result> {
        abstract T value;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('abstract class GenericStore<T, R extends Result> '
            'extends SomeStore<T, R>'),
        contains('Signal<T> value\$'),
      ]),
    );
    // Не должен эмитить `class` без `abstract`.
    expect(generated, isNot(contains('\nclass GenericStore')));
  });

  test('abstract defaults to false (concrete class by default)', () async {
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'ConcreteStore')
      abstract class SomeImpl {
        abstract String name;
      }
      ''',
    );
    // По умолчанию — конкретный класс (без `abstract`).
    expect(generated, contains('class ConcreteStore extends SomeImpl'));
    expect(generated, isNot(contains('abstract class ConcreteStore')));
  });
}

/// Пустые BuilderOptions для тестов — generator не параметризуется.
const _testOptions = BuilderOptions({});

/// Запускает builder и возвращает сгенерированную часть как строку.
///
/// `SharedPartBuilder` пишет в `<source>.store_generator.g.part`, а не в
/// финальный `.g.dart` (последний собирается `combining_builder`'ом, который
/// не запускается в изолированном `testBuilder`). Поэтому читаем именно part.
///
/// Бросает проверку, если сборка не удалась или актив не сгенерирован —
/// для позитивных кейсов это и есть искомое поведение.
Future<String> _run(
  PackageConfig packageConfig,
  String headers,
  String body,
) async {
  final result = await _runResult(packageConfig, headers, body);
  expect(result.succeeded, true,
      reason: 'Ожидалась успешная сборка, но получили ошибки:\n'
          '${result.errors.join('\n')}');
  // SharedPartBuilder пишет скрытый part-файл; берём единственный output.
  expect(result.outputs, hasLength(1),
      reason: 'Ожидался ровно один сгенерированный актив.');
  return result.readerWriter.readAsString(result.outputs.single);
}

/// Низкоуровневый запуск: возвращает полный результат сборки.
Future<TestBuilderResult> _runResult(
  PackageConfig packageConfig,
  String headers,
  String body,
) {
  return testBuilder(
    storeBuilder(_testOptions),
    {
      'a|lib/store.dart': '$headers\n$body',
    },
    packageConfig: packageConfig,
    // Предзагружаем источники внешних пакетов (аннотация, signals), чтобы
    // резолвер раскрыл `@Store` во входной библиотеке.
    readerWriter: createDependencyReader(packageConfig),
    // Делаем скрытые part-выходы SharedPartBuilder читаемыми по логическому ID.
    flattenOutput: true,
  );
}
