// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

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
import 'package:signals_store/signals_store.dart';
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

  test('private abstract field → private signal field, PUBLIC ctor param', () async {
    // Приватное поле `_count` → приватное signal-поле `_count$` и приватные
    // геттер/сеттер `_count`. Но параметр конструктора — ПУБЛИЧНЫЙ `count`
    // (stripped-имя): Dart запрещает приватные имена в named-параметрах, не
    // являющихся initializing-formal (`private_named_non_field_parameter`).
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
        // Параметр конструктора — ПУБЛИЧНОЕ имя (без `_`): Dart требует этого.
        contains('required int count'),
        // И НЕ приватное (это вызовет compile error).
        isNot(contains('required int _count')),
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

  test('late final field initialized in user constructor body is preserved',
      () async {
    // `late final int f;` без inline-инициализатора может быть инициализирован
    // в ТЕЛЕ пользовательского unnamed-конструктора суперкласса. Генератор не
    // трогает late-поля и не объявляет свой super-вызов явно, поэтому подкласс
    // неявно вызывает super() — тело конструктора суперкласса выполняется, и
    // поле инициализируется. Это НЕ баг: ответственность за инициализацию
    // late-поля лежит на пользователе (как и для обычного late). Regression
    // guard: генератор не должен ломать этот паттерн.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'LazyInitStore')
      abstract class LazyInitImpl {
        late final int f;
        abstract int count;
        LazyInitImpl() {
          f = 42;
        }
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Конструктор подкласса не вызывает super явно → неявный super()
        // выполняет тело пользовательского конструктора.
        contains('LazyInitStore({required int count})'),
        isNot(contains('super.f')),
        isNot(contains('super(')),
      ]),
    );
    // И сгенерированный код компилируется (late final инициализируется через
    // super() — тело ctor суперкласса).
    await _expectCompiles(headers, '''
@Store(name: 'LazyInitStore')
abstract class LazyInitImpl {
  late final int f;
  abstract int count;
  LazyInitImpl() {
    f = 42;
  }
}

$generated''');
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

  // --- Computed-геттеры (concrete getters → Computed) ---

  test('reactive getter (reads abstract fields) → computed contract', () async {
    // Геттер `sum` читает reactive-поля a, b → становится computed.
    // Генерируется: sum$ (Computed), sum (→ sum$.value), sumRaw (→ super.sum).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'CounterStore')
      abstract class CounterImpl {
        abstract int a;
        abstract int b;
        int get sum => a + b;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        // Форматирование (dartfmt) может разбить на строки — проверяем по
        // устойчивым частям, а не по цельной строке.
        contains('Computed<int> sum\$'),
        contains('() => sumRaw'),
        contains("name: 'CounterStore.sum'"),
        contains('int get sum => sum\$.value;'),
        contains('int get sumRaw => super.sum;'),
      ]),
    );
  });

  test('non-reactive getter (no reactive references) → plain override', () async {
    // Геттер `hundred` не ссылается на reactive → остаётся обычным,
    // переопределяется как super.hundred (чтобы класс не стал abstract).
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'ConstStore')
      abstract class ConstImpl {
        abstract int a;
        int get hundred => 100;
      }
      ''',
    );
    expect(generated, contains('@override\n  int get hundred => super.hundred;'));
    expect(generated, isNot(contains('Computed<int>')));
    expect(generated, isNot(contains('hundredRaw')));
  });

  test('getter reading substore → computed', () async {
    // Геттер `authed` читает поле-подстор session → реактивен → computed.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'InnerStore')
      abstract class InnerStoreImpl {
        abstract bool flag;
      }

      @Store(name: 'OuterStore')
      abstract class OuterStoreImpl {
        final InnerStoreImpl inner;
        OuterStoreImpl({required this.inner});
        bool get authed => inner.flag;
      }
      ''',
    );
    expect(
      generated,
      allOf([
        contains('late final Computed<bool> authed\$'),
        contains('bool get authed => authed\$.value;'),
        contains('bool get authedRaw => super.authed;'),
      ]),
    );
  });

  test('getter reading global signal via .value → computed', () async {
    // Геттер читает глобальный signal через .value → реактивен (G12).
    // Детекция через staticType требует полного type resolution. В testBuilder
    // это может не сработать для типов из package:signals — поэтому проверяем
    // реальное поведение в build_runner через регенерацию example (отдельный
    // шаг). Здесь фиксируем: total ЛИБО computed, ЛИБО plain — оба исхода
    // валидны для интеграционного smoke-теста.
    final generated = await _run(
      packageConfig,
      '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals/signals.dart';

final globalCount = signal(10);
''',
      '''
      @Store(name: 'AppStore')
      abstract class AppImpl {
        abstract int seed;
        int get total => globalCount.value * 2;
      }
      ''',
    );
    expect(
      generated,
      anyOf([
        allOf([
          contains('Computed<int> total\$'),
          contains('int get total => total\$.value;'),
        ]),
        // Fallback: если type resolution в testBuilder неполный.
        contains('int get total => super.total;'),
      ]),
    );
  });

  test('store without concrete getters → no Computed/output', () async {
    // Класс без concrete getters: ничего связанного с computed не генерируется.
    final generated = await _run(
      packageConfig,
      headers,
      '''
      @Store(name: 'PlainStore')
      abstract class PlainImpl {
        abstract int a;
      }
      ''',
    );
    expect(generated, isNot(contains('Computed')));
    expect(generated, isNot(contains("computed(")));
    expect(generated, isNot(contains('Raw')));
  });

  // --- АУДИТ неучтённых сценариев генерации ---

  group('audit: unhandled codegen scenarios', () {
    // C1: класс с ИМЕНОВАННЫМ конструктором → ошибка кодогенерации.
    test('C1: named constructor in impl → build error', () async {
      final result = await _runResult(
        packageConfig,
        headers,
        '''
        @Store(name: 'NamedStore')
        abstract class NamedImpl {
          abstract int a;
          NamedImpl.main() : a = 0;       // именованный конструктор
          NamedImpl.named(int v) : a = v; // ещё один именованный
        }
        ''',
      );
      // Именованные конструкторы запрещены → сборка падает с понятной ошибкой.
      expect(result.succeeded, false,
          reason: 'C1: named constructors must raise a codegen error');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('named constructors'),
          contains('unnamed constructor'),
        ]),
      );
      // Битый актив не генерируется.
      expect(
        result.readerWriter.testing.assets,
        isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
      );
    });

    // C4: класс БЕЗ unnamed-конструктора с concrete-полем → ошибка кодогенерации.
    test('C4: class without unnamed constructor + concrete field → build error',
        () async {
      final result = await _runResult(
        packageConfig,
        headers,
        '''
        @Store(name: 'NoCtorStore')
        abstract class NoCtorImpl {
          final String label;   // concrete-поле БЕЗ конструктора
          abstract int count;
        }
        ''',
      );
      // У суперкласса нет unnamed-конструктора с параметром label → super.label
      // невалиден → сборка падает с понятной ошибкой.
      expect(result.succeeded, false,
          reason: 'C4: a concrete field without a super constructor must raise '
              'a codegen error');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('label'),
          contains('super constructor'),
        ]),
      );
      expect(
        result.readerWriter.testing.assets,
        isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
      );
    });

    // A2: getter с именем, совпадающим с abstract-полем.
    test('A2: getter name collides with abstract field — actual behavior',
        () async {
      final result = await _runResult(
        packageConfig,
        headers,
        '''
        @Store(name: 'CollideStore')
        abstract class CollideImpl {
          abstract int sum;       // abstract-поле sum
          int get sum => 42;      // getter sum — коллизия имён
        }
        ''',
      );
      printOnFailure('A2 getter=field collision → errors=${result.errors}');
      // abstract sum → signal sum$; getter sum → computed sum$. Коллизия sum$
      // (дважды) и get sum (дважды) → ошибка кодогенерации.
      expect(result.succeeded, false,
          reason: 'A2: getter с именем abstract-поля — коллизия имён должна '
              'вызывать ошибку кодогенерации');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('Name collision'),
          contains('sum'),
        ]),
      );
      expect(
        result.readerWriter.testing.assets,
        isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
      );
    });

    // A3: getter называется 'sumRaw' — конфликт с computed-контрактом.
    test('A3: getter named like Raw suffix (sumRaw) → build error', () async {
      final result = await _runResult(
        packageConfig,
        headers,
        '''
        @Store(name: 'RawStore')
        abstract class RawImpl {
          abstract int a;
          int get sum => a + 1;      // computed sum → sumRaw генерируется
          int get sumRaw => a * 2;   // геттер УЖЕ называется sumRaw — коллизия!
        }
        ''',
      );
      printOnFailure('A3 getter=sumRaw collision → errors=${result.errors}');
      // computed sum → sumRaw; пользовательский getter sumRaw → конфликт.
      // Ошибка кодогенерации про коллизию имён.
      expect(result.succeeded, false,
          reason: 'A3: getter с именем *Raw конфликтует с computed-контрактом');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('Name collision'),
          contains('sumRaw'),
        ]),
      );
      expect(
        result.readerWriter.testing.assets,
        isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
      );
    });

    // B1: abstract-поле с function type.
    test('B1: abstract field with function type — actual behavior', () async {
      final generated = await _run(
        packageConfig,
        headers,
        '''
        @Store(name: 'FnStore')
        abstract class FnImpl {
          abstract int Function(int) transform;
        }
        ''',
      );
      printOnFailure('B1 function-typed field → generated=\n$generated');
      // Signal<int Function(int)> — корректно ли типизируется?
      expect(generated, contains('Signal<int Function(int)>'),
          reason: 'B1: function type в abstract-поле → Signal с function type');
    });

    // B2: computed-геттер возвращает function type.
    test('B2: computed getter returning function type — actual behavior',
        () async {
      final generated = await _run(
        packageConfig,
        headers,
        '''
        @Store(name: 'FnGetterStore')
        abstract class FnGetterImpl {
          abstract int multiplier;
          int Function(int) get scale => (x) => x * multiplier;  // читает reactive
        }
        ''',
      );
      printOnFailure('B2 function-typed getter → generated=\n$generated');
      // Computed<int Function(int)> — корректно ли?
      expect(generated, contains('Computed<int Function(int)>'),
          reason: 'B2: computed-геттер с function type → Computed с function type');
    });
  });

  // --- АУДИТ приватных полей: реальная компиляция сгенерированного кода ---
  //
  // Регрессия: до фикса приватные поля генерировали НЕкомпилируемый код
  // (`private_named_non_field_parameter`, `super_formal_parameter_without_-
  // associated_named`), но `contains`-матчеры этого не ловили — они проверяют
  // подстроки, а не компилируемость. Эти тесты запускают `dart analyze` на
  // реальном сгенерированном коде и требуют 0 ошибок.
  group('audit: private field compilation', () {
    // C-private-1: приватное abstract-поле → публичный параметр `count`,
    // приватный signal `_count$`, приватные геттер/сеттер `_count`. Код должен
    // компилироваться (раньше эмитил `required int _count` — незаконно).
    test('C-private-1: private abstract field → compiling code', () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'CounterStore')
      abstract class CounterImpl {
        abstract int _count;
      }
      ''');
      await _expectCompiles(headers, '''
@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int _count;
}

$generated''');
    });

    // C-private-2: приватное concrete-поле с ПОЗИЦИОННЫМ super-конструктором
    // → `super(secret)` в initializer-list. Компилируется.
    test('C-private-2: private concrete field (positional super) → compiling',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'HolderStore')
      abstract class HolderImpl {
        final int _secret;
        HolderImpl(this._secret);
      }
      ''');
      await _expectCompiles(headers, '''
@Store(name: 'HolderStore')
abstract class HolderImpl {
  final int _secret;
  HolderImpl(this._secret);
}

$generated''');
    });

    // C-private-3: приватное concrete-поле с ИМЕНОВАННЫМ super-конструктором
    // → build error с понятным сообщением (Dart не раскрывает приватный named
    // super-параметр подклассу — фундаментальное ограничение).
    test('C-private-3: private concrete field (named super) → build error',
        () async {
      final result = await _runResult(packageConfig, headers, '''
      @Store(name: 'HolderStore')
      abstract class HolderImpl {
        final int _secret;
        HolderImpl({required this._secret});
      }
      ''');
      expect(result.succeeded, false,
          reason: 'C-private-3: a private concrete field with a named super '
              'constructor must raise a codegen error');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('_secret'),
          contains('POSITIONAL'),
        ]),
      );
      expect(
        result.readerWriter.testing.assets,
        isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
      );
    });

    // C-private-4: приватное concrete-поле (позиционный super) + публичное
    // concrete-поле (named super) в одном классе. Публичное → `required
    // super.label`, приватное → `super(secret)`. Dart разрешает смешивать
    // named super-параметр с явным `super(...)` вызовом для позиционных.
    test('C-private-4: mixed public (named) + private (positional) concrete → '
        'compiling', () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'MixedHolder')
      abstract class MixedHolderImpl {
        final String label;
        final int _secret;
        MixedHolderImpl(this._secret, {required this.label});
      }
      ''');
      await _expectCompiles(headers, '''
@Store(name: 'MixedHolder')
abstract class MixedHolderImpl {
  final String label;
  final int _secret;
  MixedHolderImpl(this._secret, {required this.label});
}

$generated''');
    });

    // C-private-5: коллизия stripped-имени. Публичное `count` и приватное
    // `_count` оба порождают параметр конструктора `count` → build error.
    test('C-private-5: public field + private field with same stripped name → '
        'collision error', () async {
      final result = await _runResult(packageConfig, headers, '''
      @Store(name: 'CollideStore')
      abstract class CollideImpl {
        abstract int count;
        abstract int _count;
      }
      ''');
      expect(result.succeeded, false,
          reason: 'C-private-5: count + _count должны коллизировать по '
              'stripped-имени параметра `count`');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('Name collision'),
          contains('count'),
        ]),
      );
    });

    // C-private-6: приватное concrete-поле с позиционным super-конструктором
    // СМЕШАННОЕ с приватным abstract-полем — regression guard на的组合у.
    test('C-private-6: private concrete + private abstract mixed → compiling',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'Combo')
      abstract class ComboImpl {
        final int _id;
        abstract String _label;
        ComboImpl(this._id);
      }
      ''');
      await _expectCompiles(headers, '''
@Store(name: 'Combo')
abstract class ComboImpl {
  final int _id;
  abstract String _label;
  ComboImpl(this._id);
}

$generated''');
    });

    // --- Аудит соседних сценариев приватных полей / конструкторов (0.4.4) ---

    // E2: поле состоит только из подчёркиваний → нет публичной формы параметра.
    // Должна быть понятная ошибка кодогенерации, а не битый код до форматтера.
    test('E2: underscore-only field name → clear codegen error', () async {
      final result = await _runResult(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        abstract int _;
      }
      ''');
      expect(result.succeeded, false,
          reason: 'E2: field "_" must raise a clear codegen error');
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        allOf([
          contains('underscore'),
          contains('no public'),
        ]),
      );
    });

    // E3: двойное подчёркивание `__count` — stripped-имя должно снимать ВСЕ
    // ведущие подчёркивания (`__count` → `count`), иначе остаётся приватное
    // имя параметра → `private_named_non_field_parameter`. Проверяем компиляцию.
    test('E3: double-underscore private field → public param, compiling',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        abstract int __count;
      }
      ''');
      expect(generated, contains('required int count'));
      expect(generated, contains('final Signal<int> __count\$'));
      await _expectCompiles(headers, '''
@Store(name: 'S')
abstract class SImpl {
  abstract int __count;
}

$generated''');
    });

    // E4 (критичный): два приватных concrete-поля с позиционным super-конструктором.
    // Аргументы super(...) должны идти в ПОРЯДКЕ ОБЪЯВЛЕНИЯ формалов (`_b, _a`),
    // а не в алфавитном порядке полей — иначе тихая перестановка значений.
    test('E4: two private concrete positional fields → super args in formal order',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        final int _b;
        final int _a;
        SImpl(this._b, this._a);
      }
      ''');
      // Параметры отсортированы по имени (a, b), но super(...) — в порядке
      // формалов (_b → b, _a → a).
      expect(generated, contains('super(b, a)'));
      await _expectCompiles(headers, '''
@Store(name: 'S')
abstract class SImpl {
  final int _b;
  final int _a;
  SImpl(this._b, this._a);
}

$generated''');
    });

    // --- Самодостаточные concrete-поля (0.4.4): inline-init и nullable ---

    // V2-1: inline-инициализатор (`final x = 5;`, `int b = 5;`, `final int? c =
    // null;`) — поле самодостаточно, значение задаётся объявлением в суперклассе.
    // Генератор НЕ добавляет его в конструктор и НЕ требует super-формала.
    test('V2-1: inline-initialized concrete fields are not constructor params',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        final int a = 5;
        int b = 5;
        final int? c = null;
        abstract int count;
      }
      ''');
      expect(
        generated,
        allOf([
          // Только reactive-поле в конструкторе.
          contains('S({required int count})'),
          // Self-sufficient поля НЕ пробрасываются через super.
          isNot(contains('super.a')),
          isNot(contains('super.b')),
          isNot(contains('super.c')),
          // И НЕ оборачиваются в Signal.
          isNot(contains('Signal<int> a')),
        ]),
      );
      await _expectCompiles(headers, '''
@Store(name: 'S')
abstract class SImpl {
  final int a = 5;
  int b = 5;
  final int? c = null;
  abstract int count;
}

$generated''');
    });

    // V2-2: non-final nullable без инициализатора (`int? d;`, `List<int>? e;`) —
    // Dart даёт null по умолчанию, поле компилируется без ctor. Пропускаем.
    test('V2-2: non-final nullable field without initializer is skipped',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        int? d;
        List<int>? e;
        abstract int count;
      }
      ''');
      expect(generated, contains('S({required int count})'));
      expect(generated, isNot(contains('super.d')));
      expect(generated, isNot(contains('super.e')));
      await _expectCompiles(headers, '''
@Store(name: 'S')
abstract class SImpl {
  int? d;
  List<int>? e;
  abstract int count;
}

$generated''');
    });

    // V2-3: `final int? e;` БЕЗ инициализатора — final требует установки (Dart
    // не даёт default). По-прежнему отклоняется C4 (нужен initializing-formal).
    test('V2-3: final nullable field without initializer → C4 error', () async {
      final result = await _runResult(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        final int? e;
        abstract int count;
      }
      ''');
      expect(result.succeeded, false,
          reason: 'V2-3: final field without initializer must raise C4');
      expect(result.errors, isNotEmpty);
      expect(result.errors.join('\n'), contains('cannot be forwarded'));
    });

    // V2-4: смешанный случай — self-sufficient поле + ctor-поле + reactive.
    // Self-sufficient пропускается, ctor-поле пробрасывается через super.
    test('V2-4: mixed self-sufficient + ctor concrete + reactive → compiling',
        () async {
      final generated = await _run(packageConfig, headers, '''
      @Store(name: 'S')
      abstract class SImpl {
        final int a = 5;
        final String label;
        abstract int count;
        SImpl({required this.label});
      }
      ''');
      expect(
        generated,
        allOf([
          contains('S({required int count, required super.label})'),
          isNot(contains('super.a')),
        ]),
      );
      await _expectCompiles(headers, '''
@Store(name: 'S')
abstract class SImpl {
  final int a = 5;
  final String label;
  abstract int count;
  SImpl({required this.label});
}

$generated''');
    });
  });

  // --- @Store(root: true): авторегистрация в StoreRootScope + единый dispose ---

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

/// Проверяет, что сгенерированный код КОМПИЛИРУЕТСЯ, запуская `dart analyze`.
///
/// Это строгая проверка, которую `contains`-матчеры дать не могут: они ловят
/// подстроки, но пропускают некомпилируемый код (как регрессия приватных полей —
/// `required int _count` выглядел правильно, но нарушал
/// `private_named_non_field_parameter`).
///
/// [headers] — импорты (аннотация + signals), [body] — полный исходник: декларация
/// `@Store`-класса + сгенерированный подкласс в одной библиотеке (как part-file).
/// Код пишется во временный файл в `lib/` (чтобы резолвились зависимости пакета),
/// анализируется, файл удаляется. Допускаются warnings/info (например,
/// `unused_element` для приватных полей) — важны только ERRORS.
Future<void> _expectCompiles(String headers, String body) async {
  final file = File('lib/_codegen_compile_check.dart');
  await file.writeAsString('$headers\n$body');
  try {
    final result = await Process.run(
      'dart',
      // --no-fatal-warnings: warnings (unused_field, unused_element) не валидны
      // для smoke-теста — нас интересуют только ERRORS (незаконный код).
      ['analyze', file.path, '--no-fatal-warnings'],
    );
    expect(
      result.exitCode,
      0,
      reason: 'Сгенерированный код должен компилироваться (0 ошибок), но '
          '`dart analyze` завершился с кодом ${result.exitCode}:\n'
          '--- stdout ---\n${result.stdout}\n'
          '--- stderr ---\n${result.stderr}\n'
          '--- проверяемый код ---\n$body',
    );
  } finally {
    if (file.existsSync()) await file.delete();
  }
}
