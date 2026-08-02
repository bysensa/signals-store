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
        contains('Signal<String> _name\$'),
        contains("name: 'FirstSomeStore.name'"),
        contains('String get name => _name\$.value;'),
        contains('set name(String value) => _name\$.value = value;'),
        contains('FirstSomeStore({required String name})'),
      ]),
    );
  });

  test('two @Store annotations → two concrete classes', () async {
    final generated = await _run(
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
    expect(
      generated,
      allOf([
        // Первый стор.
        contains('class FirstSomeStore extends SomeStoreImpl'),
        contains("name: 'FirstSomeStore.name'"),
        // Второй стор.
        contains('class SecondSomeStore extends SomeStoreImpl'),
        contains("name: 'SecondSomeStore.name'"),
      ]),
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
        contains('Signal<int> _count\$'),
        contains('int get count => _count\$.value;'),
        contains("name: 'CounterStore.count'"),
        // name.
        contains('Signal<String> _name\$'),
        contains('String get name => _name\$.value;'),
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
        contains('Signal<int?> _maybe\$'),
        contains('required int? maybe'),
        contains('int? get maybe => _maybe\$.value;'),
        contains('set maybe(int? value) => _maybe\$.value = value;'),
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
        contains('Signal<List<String>> _items\$'),
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
        isNot(contains('_stable\$')),
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
        contains('Signal<String> _reactive\$'),
        contains('@override'),
        contains('String get reactive => _reactive\$.value;'),
      ]),
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
        contains('Signal<int> _value\$'),
      ]),
    );
    // Генератор НЕ должен эмитить InvalidType для поля, ссылающегося на
    // ещё-не-существующее имя реализации.
    expect(generated, isNot(contains('InvalidType')));
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
        contains('Signal<T> _value\$'),
        contains('required T value'),
        contains('T get value => _value\$.value;'),
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
        contains('Signal<T> _value\$'),
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
        contains('Signal<T> _value\$'),
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
