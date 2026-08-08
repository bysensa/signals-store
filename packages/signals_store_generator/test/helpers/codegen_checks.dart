// ignore_for_file: lines_longer_than_80_chars, depend_on_referenced_packages

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:signals_store_generator/src/builder.dart';
import 'package:test/test.dart';

import 'flutter_test_harness.dart';

/// Пустые [BuilderOptions] для тестов — generator не параметризуется.
const testBuilderOptions = BuilderOptions({});

/// Общий заголовок входной библиотеки. `signals` импортируется, т.к.
/// сгенерированный код ссылается на `Signal`/`SignalOptions` (сам генератор
/// их не резолвит — только типы полей, но проверка компилируемости
/// сгенерированного кода — отдельная задача).
const codegenHeaders = '''
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:signals_store/signals_store.dart';
import 'package:signals/signals.dart';
''';

/// Запускает builder и возвращает сгенерированную часть как строку.
///
/// `SharedPartBuilder` пишет в `<source>.store_generator.g.part`, а не в
/// финальный `.g.dart` (последний собирается `combining_builder`'ом, который
/// не запускается в изолированном `testBuilder`). Поэтому читаем именно part.
///
/// Бросает проверку, если сборка не удалась или актив не сгенерирован —
/// для позитивных кейсов это и есть искомое поведение.
Future<String> runBuilder(
  PackageConfig packageConfig,
  String headers,
  String body,
) async {
  final result = await runBuilderResult(packageConfig, headers, body);
  expect(result.succeeded, true,
      reason: 'Ожидалась успешная сборка, но получили ошибки:\n'
          '${result.errors.join('\n')}');
  // SharedPartBuilder пишет скрытый part-файл; берём единственный output.
  expect(result.outputs, hasLength(1),
      reason: 'Ожидался ровно один сгенерированный актив.');
  return result.readerWriter.readAsString(result.outputs.single);
}

/// Низкоуровневый запуск: возвращает полный результат сборки.
Future<TestBuilderResult> runBuilderResult(
  PackageConfig packageConfig,
  String headers,
  String body,
) {
  return testBuilder(
    storeBuilder(testBuilderOptions),
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
/// **CWD-независимость (фикс CI):** раньше временный файл писался в
/// ОТНОСИТЕЛЬНЫЙ путь `lib/_codegen_compile_check.dart`, что падало с
/// `PathNotFoundException`, когда `flutter test packages/...` запускался из
/// корня воркспейса (CWD = корень, `lib/` там нет). Теперь файл пишется по
/// АБСОЛЮТНОМУ пути от workspace root, а `dart analyze` запускается с
/// `workingDirectory` = пакет генератора (где есть `lib/` и корректный
/// package_config через подъём к воркспейсу). Внешний процесс надёжен:
/// `dart analyze` сам резолвит пакеты и сообщает ошибки (в отличие от
/// in-memory `AnalysisContextCollection`, который под flutter tester давал
/// пустые diagnostics — эмпирически отклонено).
///
/// [headers] — импорты (аннотация + signals), [body] — полный исходник: декларация
/// `@Store`-класса + сгенерированный подкласс в одной библиотеке. Код пишется во
/// временный файл в `lib/` пакета, анализируется, файл удаляется. Допускаются
/// warnings/info (например, `unused_element`) — важны только ERRORS.
Future<void> expectCompiles(String headers, String body) async {
  final workspaceRoot = _findWorkspaceRoot();
  final pkgDir = p.join(workspaceRoot, 'packages', 'signals_store_generator');
  final libDir = p.join(pkgDir, 'lib');
  final file = File(p.join(libDir, '_codegen_compile_check.dart'));
  await file.writeAsString('$headers\n$body');
  try {
    final result = await Process.run(
      'dart',
      // --no-fatal-warnings: warnings (unused_field, unused_element) не валидны
      // для smoke-теста — нас интересуют только ERRORS (незаконный код).
      ['analyze', file.path, '--no-fatal-warnings'],
      // Запускаем из каталога пакета: package_config.json найдётся при подъёме
      // к воркспейсу, независимо от CWD вызывающего (локально или CI).
      workingDirectory: pkgDir,
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

/// Каталог воркспейса (где лежит `.dart_tool/package_config.json`).
String _findWorkspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, '.dart_tool', 'package_config.json')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('Не найден .dart_tool/package_config.json воркспейса.');
}
