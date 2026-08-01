// ignore_for_file: lines_longer_than_80_chars, depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/sdk/build_sdk_summary.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:build/build.dart';
import 'package:build_runner/src/bootstrap/build_process_state.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// Готовит окружение для интеграционных тестов генератора под `flutter test`.
///
/// **Проблема.** Резолвер `build_runner` определяет пути к Dart SDK из
/// `Platform.resolvedExecutable`. Под `flutter test` это `flutter_tester`
/// (engine binary), а не `dart` — резолвер ищет SDK в каталоге engine и
/// падает с `PathNotFoundException` (или `Isolate.packageConfig`).
///
/// **Решение в два шага.**
///
/// 1. Подменяем `buildProcessState.{packageConfigUri,dartSdkPath}` через
///    `deserializeAndSet` — резолвер берёт package config из файла, а не из
///    `Isolate.packageConfigSync` (недоступен под `flutter test`).
///
/// 2. Предгенерируем кэш SDK-сводки `.dart_tool/build_resolvers/sdk.sum` с
///    корректным путём к flutter-bundled Dart SDK и `.deps`, который
///    совпадает с тем, что резолвер вычислит во время теста. При наличии
///    валидного кэша резолвер пропускает свой (сломанный) путь пересборки
///    сводки и использует кэш.
///
/// Вызывать ОДИН раз перед тестами (`setUpAll`).
Future<void> configureBuildProcessStateForTests() async {
  final workspaceRoot = _findWorkspaceRoot();
  final packageConfigUri =
      File(p.join(workspaceRoot, '.dart_tool', 'package_config.json'))
          .uri
          .toString();
  final dartSdkPath = _findDartSdkPath();

  // Шаг 1: подменяем packageConfigUri/dartSdkPath ДО первого обращения
  // геттеров, чтобы `Isolate.packageConfigSync` не вызывался.
  buildProcessState.deserializeAndSet(
    '{"packageConfigUri": ${jsonEncode(packageConfigUri)}, '
    '"dartSdkPath": ${jsonEncode(dartSdkPath)}}',
  );

  // Шаг 2: обеспечиваем валидный кэш SDK-сводки.
  // Кэш ищется относительно CWD (каталог пакета при `flutter test`),
  // а НЕ корня воркспейса — поэтому кладём его в CWD.
  await _ensureSdkSummaryCache(dartSdkPath: dartSdkPath);
}

/// Загружает package_config.json воркспейса.
Future<PackageConfig> loadWorkspacePackageConfig() async {
  final workspaceRoot = _findWorkspaceRoot();
  final configFile =
      File(p.join(workspaceRoot, '.dart_tool', 'package_config.json'));
  return loadPackageConfigUri(configFile.uri);
}

/// Создаёт [TestReaderWriter] с предзагруженными источниками внешних пакетов.
///
/// `testBuilder` по умолчанию видит только источники из `sourceAssets`. Чтобы
/// резолвер мог раскрыть `package:signals_store_annotation` (и `package:signals`)
/// в тестовом входе, копируем их `lib`-исходники с диска в in-memory reader.
/// Пакеты-«мишени» теста (`a`) остаются задавать через `sourceAssets`.
///
/// [flattenOutput] = `true` делает скрытые part-выходы `SharedPartBuilder`'а
/// доступными для чтения по их логическому `AssetId` (иначе они лежат под
/// `.dart_tool/build/generated` и нечитаемы напрямую).
///
/// [dependencyPackages] — список имён пакетов, чьи источники нужно загрузить.
TestReaderWriter createDependencyReader(
  PackageConfig packageConfig, {
  List<String> dependencyPackages = const [
    'signals_store_annotation',
    'signals',
  ],
  bool flattenOutput = true,
}) {
  final reader = TestReaderWriter(flattenOutput: flattenOutput);
  for (final packageName in dependencyPackages) {
    final pkg = packageConfig[packageName];
    if (pkg == null) continue;
    final libDir = Directory.fromUri(pkg.packageUriRoot);
    if (!libDir.existsSync()) continue;
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.relative(entity.path, from: libDir.path);
      final assetId = AssetId(packageName, p.join('lib', relative));
      reader.testing.writeString(assetId, entity.readAsStringSync());
    }
  }
  return reader;
}

/// Каталог воркспейса (где лежит `.dart_tool`).
String _findWorkspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, '.dart_tool', 'package_config.json'))
        .existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('Не найден .dart_tool/package_config.json воркспейса. '
      'Запустите `flutter pub get` в корне.');
}

/// Путь к Dart SDK, с которым работает текущий `flutter`.
///
/// Под `flutter test` `Platform.resolvedExecutable` — это
/// `<flutter>/bin/cache/artifacts/engine/<arch>/flutter_tester`. SDK лежит
/// в `<flutter>/bin/cache/dart-sdk`. Поднимаемся вверх, пока не найдём
/// каталог `dart-sdk`, в котором есть `lib/_internal/libraries.dart`.
String _findDartSdkPath() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 10; i++) {
    final candidate = Directory(p.join(dir.path, 'dart-sdk'));
    if (_isValidDartSdk(candidate.path)) {
      return candidate.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // Фолбэк: переменная окружения.
  final envSdk = Platform.environment['FLUTTER_DART_SDK'];
  if (envSdk != null && _isValidDartSdk(envSdk)) return envSdk;
  throw StateError('Не удалось определить путь к Dart SDK Flutter по '
      'Platform.resolvedExecutable=${Platform.resolvedExecutable}. '
      'Установите FLUTTER_DART_SDK=<путь к dart-sdk>.');
}

/// Признак валидного Dart SDK: содержит `libraries.dart` в одном из
/// стандартных расположений analyzer'а.
bool _isValidDartSdk(String path) {
  final locations = [
    p.join(path, 'lib', '_internal', 'sdk_library_metadata', 'lib',
        'libraries.dart'),
    p.join(path, 'lib', '_internal', 'libraries.dart'),
  ];
  return locations.any((loc) => File(loc).existsSync());
}

/// Гарантирует наличие `.dart_tool/build_resolvers/sdk.sum` + `.deps`,
/// валидных для текущего SDK и пакета analyzer/build_runner.
///
/// Кэш размещается относительно [Directory.current] (CWD), т.к. именно по
/// этому пути его ищет `build_runner` во время теста.
///
/// Формат `.deps` повторяет внутренний формат `build_runner`'a:
/// `{"sdk": Platform.version, "analyzer": <lib root>, "build_runner": <lib root>}`.
Future<void> _ensureSdkSummaryCache({required String dartSdkPath}) async {
  final cacheDir = p.join(Directory.current.path, '.dart_tool', 'build_resolvers');
  final summaryPath = p.join(cacheDir, 'sdk.sum');
  final depsPath = '$summaryPath.deps';

  // currentDeps должен совпадать с тем, что резолвер вычислит в тесте.
  final analyzerPath = _packageLibRoot('analyzer');
  final buildRunnerPath = _packageLibRoot('build_runner');
  final currentDeps = <String, Object?>{
    'sdk': Platform.version,
    'analyzer': analyzerPath,
    'build_runner': buildRunnerPath,
  };

  final summaryFile = File(summaryPath);
  final depsFile = File(depsPath);

  // Если кэш валиден — ничего не делаем.
  if (summaryFile.existsSync() && depsFile.existsSync()) {
    try {
      final previous =
          jsonDecode(await depsFile.readAsString()) as Map<String, Object?>;
      if (_depsMatch(previous, currentDeps)) return;
    } catch (_) {
      // Повреждённый кэш — пересоберём.
    }
  }

  await Directory(cacheDir).create(recursive: true);
  final resourceProvider = PhysicalResourceProvider.INSTANCE;
  final summaryBytes = await buildSdkSummary(
    resourceProvider: resourceProvider,
    sdkPath: dartSdkPath,
  );
  await summaryFile.writeAsBytes(summaryBytes, flush: true);
  await depsFile.writeAsString(jsonEncode(currentDeps), flush: true);
}

bool _depsMatch(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Корневой каталог пакета (каталог-родитель `lib`) через
/// package_config.json воркспейса.
///
/// Повторяет вычисление `build_runner`'а в `sdk_summary.dart`:
/// `packageConfig.resolve(package:X/)` → `<root>/lib`,
/// `p.dirname(...)` → `<root>` (без `lib`).
String _packageLibRoot(String packageName) {
  final workspaceRoot = _findWorkspaceRoot();
  final configFile =
      File(p.join(workspaceRoot, '.dart_tool', 'package_config.json'));
  final config = jsonDecode(configFile.readAsStringSync())
      as Map<String, Object?>;
  final packages = config['packages'] as List;
  for (final pkg in packages) {
    final map = pkg as Map<String, Object?>;
    if (map['name'] == packageName) {
      final rootUri = map['rootUri'] as String;
      final root = rootUri.startsWith('file:')
          ? Uri.parse(rootUri).toFilePath()
          : p.fromUri(rootUri);
      // rootUri указывает на корень пакета; dirname(lib) == root.
      return p.normalize(root);
    }
  }
  throw StateError('Пакет $packageName не найден в package_config.json');
}
