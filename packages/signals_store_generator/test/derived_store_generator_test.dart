// ignore_for_file: lines_longer_than_80_chars

import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

import 'helpers/codegen_checks.dart';
import 'helpers/flutter_test_harness.dart';

/// Тесты генератора для `@DerivedStore`.
///
/// Derived-стор = полноценный стор + доступ к корню через
/// `StoreRootScope.of<T>()`. Проверяем: root-геттер, собственные Signal-поля,
/// computed-геттеры (читающие root), dispose (общий фрагмент), и валидации
/// (нет root-геттера, root типизирован не-root стором, @Store+@DerivedStore
/// на одном классе). Сюда же отнесены отложенные из Task 5 тесты:
/// super.dispose() с concrete dispose в impl и негативный тест на плохую
/// сигнатуру dispose().
void main() {
  late final PackageConfig packageConfig;

  setUpAll(() async {
    await configureBuildProcessStateForTests();
    packageConfig = await loadWorkspacePackageConfig();
  });

  const headers = codegenHeaders;

  // --- Позитивные: root-геттер, собственное состояние, computed ---

  test('derived store: root getter resolves via StoreRootScope.of', () async {
    final generated = await runBuilder(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'CounterDerived')
abstract class CounterDerivedImpl {
  AppStoreImpl get root;
  int get doubled => root.count * 2;
}
''');
    expect(
      generated,
      allOf([
        contains('class CounterDerived extends CounterDerivedImpl'),
        // root — геттер (не late final): резолв при каждом обращении, derived
        // всегда видит актуальный корень (см. спеку «Пересоздание корня»).
        contains('AppStoreImpl get root => StoreRootScope.of<AppStoreImpl>()'),
        isNot(contains('late final AppStoreImpl root')),
        // doubled читает root.count → реактивен → Computed.
        contains('Computed<int> doubled\$'),
        contains('int get doubledRaw => super.doubled'),
      ]),
    );
    await expectCompiles(headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'CounterDerived')
abstract class CounterDerivedImpl {
  AppStoreImpl get root;
  int get doubled => root.count * 2;
}

$generated''');
  });

  test('derived store: own abstract field becomes Signal + ctor param', () async {
    final generated = await runBuilder(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'TodoDetailsStore')
abstract class TodoDetailsStoreImpl {
  AppStoreImpl get root;
  abstract String todoId;
  int get len => root.count + todoId.length;
}
''');
    expect(
      generated,
      allOf([
        // Собственное состояние — параметр создания экрана.
        contains('TodoDetailsStore({required String todoId})'),
        contains('Signal<String> todoId\$'),
        // len читает root + todoId → Computed.
        contains('Computed<int> len\$'),
      ]),
    );
  });

  test('derived store: no own fields, only computed reading root → valid',
      () async {
    // Derived без собственных полей валиден, если есть геттер(ы) помимо root.
    // Спека: «для derived — без полей валиден, если есть геттеры помимо root».
    final generated = await runBuilder(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
  int get doubled => root.count * 2;
}
''');
    expect(
      generated,
      allOf([
        contains('class D extends DImpl'),
        contains('AppStoreImpl get root => StoreRootScope.of<AppStoreImpl>()'),
        contains('Computed<int> doubled\$'),
      ]),
    );
  });

  // --- Пересоздание корня: root — геттер (не late final) ---

  test('derived store: root is a getter (not late final) → sees re-registered '
      'root', () async {
    final generated = await runBuilder(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
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
    await expectCompiles(headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
  int get doubled => root.count * 2;
}

$generated''');
  });

  // --- dispose (общий фрагмент из Task 5; для derived — без unregister) ---

  test('derived store: dispose() disposes signals and computed, no unregister',
      () async {
    final generated = await runBuilder(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
  abstract int a;
  int get doubled => a * 2;
}
''');
    // Generated output содержит ОБА класса (AppStore + D). AppStore (root)
    // вызывает unregister, D (derived) — нет. Поэтому unregister встречается
    // ровно ОДИН раз (только в AppStore), а не в dispose-блоке D.
    final unregisterCount =
        'StoreRootScope.unregister'.allMatches(generated).length;
    expect(
      generated,
      allOf([
        contains('void dispose()'),
        contains('a\$.dispose()'),
        contains('doubled\$.dispose()'),
        contains('class D extends DImpl'),
      ]),
    );
    expect(unregisterCount, 1,
        reason: 'unregister только в AppStore; derived D не вызывает его');
  });

  test('derived store: concrete dispose() in impl → super.dispose() first',
      () async {
    // Поведенческий тест (отложен из Task 5): impl объявляет concrete dispose —
    // генератор эмитит @override + super.dispose() ПЕРВЫМ, затем диспоз сигналов.
    final generated = await runBuilder(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
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
        // super.dispose() вызывается первым — сигналы ещё живы.
        contains('super.dispose();'),
        contains('a\$.dispose()'),
      ]),
    );
  });

  // --- Валидации (FN-критичные) ---

  test('validation: derived without root getter → build error', () async {
    final result = await runBuilderResult(packageConfig, headers, '''
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
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('validation: derived root getter typed by non-root store → build error',
      () async {
    final result = await runBuilderResult(packageConfig, headers, '''
@Store(name: 'Leaf')
abstract class LeafImpl {
  abstract int x;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  LeafImpl get root;
  abstract int a;
}
''');
    expect(result.succeeded, false);
    // Сообщение указывает, что тип root-геттера не помечен root: true.
    expect(result.errors.join('\n'), contains('root: true'));
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('validation: @Store and @DerivedStore on one class → build error',
      () async {
    final result = await runBuilderResult(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@Store(name: 'S')
@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), contains('both'));
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('validation: root typed as a field (not getter) → build error',
      () async {
    // Поле, типизированное корневым impl → ясная ошибка «объявите как геттер».
    final result = await runBuilderResult(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  abstract AppStoreImpl root;
  abstract int a;
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), contains('getter'));
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('validation: derived with two root-typed getters → build error',
      () async {
    final result = await runBuilderResult(packageConfig, headers, '''
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  abstract int count;
}

@DerivedStore(name: 'D')
abstract class DImpl {
  AppStoreImpl get root;
  AppStoreImpl get other;
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), anyOf(contains('multiple'), contains('two')));
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  // --- Отложенные из Task 5: негативный тест на плохую сигнатуру dispose ---

  test('validation: dispose() with parameters → build error', () async {
    // Отложен из Task 5: dispose с параметрами → понятная ошибка кодогенерации.
    final result = await runBuilderResult(packageConfig, headers, '''
@Store(name: 'S')
abstract class SImpl {
  abstract int a;
  void dispose(int flag) {
    // bad signature
  }
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), allOf([
      contains('dispose'),
      contains('no-argument'),
    ]));
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });

  test('validation: dispose() with non-void return → build error', () async {
    final result = await runBuilderResult(packageConfig, headers, '''
@Store(name: 'S')
abstract class SImpl {
  abstract int a;
  int dispose() {
    return 0;
  }
}
''');
    expect(result.succeeded, false);
    expect(result.errors.join('\n'), contains('void'));
    expect(
      result.readerWriter.testing.assets,
      isNot(contains(AssetId('a', 'lib/store.store_generator.g.part'))),
    );
  });
}
