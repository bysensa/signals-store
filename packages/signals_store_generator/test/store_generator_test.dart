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
