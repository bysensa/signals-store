// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:signals_store_generator/src/reactivity.dart';
import 'package:test/test.dart';

import 'helpers/flutter_test_harness.dart';

/// Тесты детектора реактивности [computeReactiveGetters].
///
/// Резолвим Dart-источник через `AnalysisContextCollection` (поверх временной
/// директории) и вызываем детектор на `ClassElement` — это проверяет **логику**
/// определения реактивности на реальном analyzer, а не на моках.
///
/// Источник обязан содержать ровно один `@Store`-класс (он и тестируется);
/// вспомогательные классы-подсторы (`SessionStoreImpl` и т.п.) можно объявлять
/// рядом — детектор получает имена impl-классов `@Store` как `storeImplNames`,
/// моделируем это в тесте явно.

late String _tempDir;
late String _dartSdkPath;
int _fileCounter = 0;

void main() {
  setUpAll(() async {
    await configureBuildProcessStateForTests();
    _dartSdkPath = _findDartSdkPath();
    _tempDir = Directory.systemTemp
        .createTempSync('signals_reactivity_test_')
        .path;
    // Превращаем временную директорию в полноценный пакет с зависимостью от
    // `signals`, иначе типы MapSignal/Signal не резолвятся analyzer'ом и
    // детектор не сможет отличить их от обычных классов.
    await File(p.join(_tempDir, 'pubspec.yaml')).writeAsString('''
name: reactivity_test_pkg
environment:
  sdk: ^3.12.0
dependencies:
  signals: ^7.0.0
''');
    final result = await Process.run(
      'flutter',
      ['pub', 'get'],
      workingDirectory: _tempDir,
    );
    if (result.exitCode != 0) {
      throw StateError('flutter pub get во временной директории упал:\n'
          '${result.stderr}');
    }
  });

  tearDownAll(() async {
    final dir = Directory(_tempDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  // ---- Базовый случай: геттер ссылается на abstract-поля ----

  test('getter referencing abstract fields → computed', () async {
    final reactive = await _detect(r'''
abstract class CounterImpl {
  abstract int a;
  abstract int b;
  int get sum => a + b;          // ← зависит от a, b
}
''');
    expect(reactive, containsAll(['a', 'b', 'sum']));
  });

  // ---- Skip-сценарий: геттер БЕЗ обращений к reactive-именам ----

  test('getter with no reactive references → stays plain', () async {
    final reactive = await _detect(r'''
abstract class MixedImpl {
  final String label;            // concrete-поле, НЕ стор
  MixedImpl({required this.label});
  int get hundred => 100;        // ← нет reactive-обращений
  String get upper => label.toUpperCase(); // label ∉ reactive
}
''', storeImplNames: {});
    // hundred и upper не ссылаются ни на abstract-поля, ни на подсторы.
    expect(reactive, isNot(contains('hundred')));
    expect(reactive, isNot(contains('upper')));
    expect(reactive, isNot(contains('label')));
  });

  // ---- Skip-сценарий: геттер «просто возвращает signal.value» ----

  test('getter returning externalSignal.value → computed (signal read)', () async {
    // Чтение `.value` на signal реактивно само по себе (G12): геттер,
    // читающий глобальный/внешний signal через .value, становится computed.
    final reactive = await _detect(r'''
import 'package:signals/signals.dart';

final externalSignal = signal(0);

abstract class PassImpl {
  int get direct => externalSignal.value; // чтение .value на signal → reactive
}
''', storeImplNames: {});
    expect(reactive, contains('direct'),
        reason: 'Чтение .value на signal реактивно → computed');
  });

  // ---- Взаимные ссылки между getters (фикс-пойнт) ----

  test('getter referencing another reactive getter → computed (fixpoint)',
      () async {
    final reactive = await _detect(r'''
abstract class ChainImpl {
  abstract int a;
  int get base => a;             // ← зависит от a → reactive
  int get mid => base * 2;       // ← зависит от base → reactive (через фикс-пойнт)
  int get top => mid + 1;        // ← зависит от mid  → reactive
  int get untouched => 7;        // ← нет reactive-обращений
}
''');
    expect(reactive, containsAll(['a', 'base', 'mid', 'top']));
    expect(reactive, isNot(contains('untouched')));
  });

  // ---- Подстор: доступ к полям вложенного стора ----

  test('getter referencing substore fields → computed', () async {
    final reactive = await _detect(r'''
abstract class AppImpl {
  final SessionStoreImpl session;  // подстор (тип ∈ storeImplNames)
  AppImpl({required this.session});
  bool get authed => session.currentUser; // ← корень 'session' реактивен
}

abstract class SessionStoreImpl {
  abstract dynamic currentUser;
}
''', storeImplNames: {'SessionStoreImpl'}, targetClass: 'AppImpl');
    expect(reactive, containsAll(['session', 'authed']));
  });

  // ---- Цепочка через подстор глубже одного уровня ----

  test('deep chain through substore (ui.filter.sortBy) → computed', () async {
    final reactive = await _detect(r'''
abstract class RootImpl {
  final UiStoreImpl ui;           // подстор
  RootImpl({required this.ui});
  int get sortIndex => ui.filter.sortBy; // корень 'ui' реактивен
}

abstract class UiStoreImpl {
  final FilterStoreImpl filter;
  UiStoreImpl({required this.filter});
}

abstract class FilterStoreImpl {
  abstract int sortBy;
}
''', storeImplNames: {'UiStoreImpl', 'FilterStoreImpl'}, targetClass: 'RootImpl');
    expect(reactive, contains('sortIndex'));
  });

  // ---- Signal-коллекции (MapSignal, ListSignal, ...) — авто-детекция по типу ----

  test('MapSignal field → reactive (auto-detected by type)', () async {
    // projects: MapSignal<K,V> — concrete-поле с типом-подтипом Signal.
    // Детектор распознаёт его через typeSystem.isSubtypeOf, без явного указания.
    final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class Project {}

abstract class ProjectsImpl {
  final MapSignal<String, Project> projects;  // ← тип ⊂ Signal
  ProjectsImpl({required this.projects});
  int get count => projects.length;           // обращение к projects → реактивно
}
''', storeImplNames: {});
    expect(reactive, containsAll(['projects', 'count']));
  });

  test('ListSignal field with filter/aggregation → reactive', () async {
    final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class Todo {}

abstract class TodosImpl {
  final ListSignal<Todo> todos;
  TodosImpl({required this.todos});
  int get activeCount =>
      todos.where((t) => true).length;  // обращение к todos-сигналу
}
''', storeImplNames: {});
    expect(reactive, containsAll(['todos', 'activeCount']));
  });

  // ---- Каскад: пользовательский класс с Signal внутри ----

  test('class containing Signal field → reactive (deep cascade)', () async {
    // UserRepo — обычный класс (не @Store), но содержит Signal-поле count.
    // Доступ repo.count.value реактивен → repo реактивен → геттер computed.
    final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class UserRepo {
  final Signal<int> count;          // ← есть Signal-поле → UserRepo реактивен
  UserRepo(this.count);
}

abstract class CascadeImpl {
  final UserRepo repo;              // ← тип UserRepo реактивен (каскад)
  CascadeImpl({required this.repo});
  int get doubled => repo.count.value * 2;  // обращение к repo → реактивно
}
''', storeImplNames: {});
    expect(reactive, containsAll(['repo', 'doubled']));
  });

  test('class WITHOUT Signal fields → stays non-reactive', () async {
    // Logger — обычный класс без Signal-полей. Доступ к нему НЕ реактивен.
    final reactive = await _detect(r'''
class Logger {
  final String name;
  Logger(this.name);
  void log(String msg) {}
}

abstract class PlainImpl {
  final Logger logger;              // ← тип не реактивен (нет Signal внутри)
  PlainImpl({required this.logger});
  String get tag => logger.name;    // обращение к logger → НЕ реактивно
}
''', storeImplNames: {});
    expect(reactive, isNot(contains('logger')));
    expect(reactive, isNot(contains('tag')));
  });

  test('cyclic types A{B} B{A} → no infinite recursion', () async {
    // Защита от циклов: ни A, ни B не содержат Signal → оба не реактивны.
    // Цикл должен быть безопасно разорван через visited-set.
    final reactive = await _detect(r'''
class A { final B b; A(this.b); }
class B { final A a; B(this.a); }

abstract class CycleImpl {
  final A a;                        // циклический тип без Signal
  CycleImpl({required this.a});
  int get x => 42;                  // нет обращений к reactive
}
''', storeImplNames: {});
    expect(reactive, isNot(contains('a')));
    expect(reactive, isNot(contains('x')));
  });

  // ---- DateTime.now() и обращения к типам не делают геттер reactive ----

  test('DateTime.now() reference → stays plain', () async {
    final reactive = await _detect(r'''
abstract class ClockImpl {
  int get millis => DateTime.now().millisecond; // DateTime — тип, не свойство
}
''');
    expect(reactive, isNot(contains('millis')));
  });

  // ===========================================================================
  // АУДИТ КОРРЕКТНОСТИ — проверка гипотез о некорректной работе алгоритма.
  // Каждый тест документирует ФАКТИЧЕСКОЕ поведение (не желаемое).
  // ===========================================================================

  group('audit: edge cases', () {
    // H1 [NEGATIVE]: this.a — обращение через явный this.
    test('H1: explicit this.a access — actual behavior', () async {
      final reactive = await _detect(r'''
abstract class ThisImpl {
  abstract int a;
  int get x => this.a;            // явный this
  int get y => a;                 // неявный (контроль)
}
''');
      // Документируем фактическое поведение (debug-вывод ниже покажет детали).
      // Ожидаем, что y ∈ reactive (контроль). Для x — проверим фактом.
      printOnFailure('H1 this.a → reactive=$reactive');
      expect(reactive, contains('y')); // контроль работает
      // Если x не вошёл — это баг H1 (this.a не детектируется).
      expect(reactive, contains('x'),
          reason: 'H1: this.a должно детектироваться как обращение к a');
    });

    // H2 [NEGATIVE]: implements Signal (не extends).
    test('H2: class implementing Signal interface — actual behavior', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

// Пользовательский "signal", реализующий интерфейс ReadonlySignal.
class CustomReactive implements ReadonlySignal<int> {
  @override
  int get value => 0;
  @override
  Object? get debugName => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

abstract class ImplImpl {
  final CustomReactive custom;
  ImplImpl({required this.custom});
  int get v => custom.value;      // custom — CustomReactive, implements ReadonlySignal
}
''', storeImplNames: {});
      printOnFailure('H2 implements Signal → reactive=$reactive');
      // Документируем: должен ли быть reactive? По семантике — да (это signal).
      expect(reactive, contains('custom'),
          reason: 'H2: класс implements Signal должен считаться реактивным');
    });

    // H3 [NEGATIVE]: поля из mixin.
    test('H3: class using mixin with Signal field — actual behavior', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

mixin Reactivity {
  final Signal<int> hidden = Signal(0);
}

class WithMixin with Reactivity {}

abstract class MixinImpl {
  final WithMixin wm;
  MixinImpl({required this.wm});
  int get v => wm.hidden.value;
}
''', storeImplNames: {});
      printOnFailure('H3 mixin Signal field → reactive=$reactive');
      // Документируем: должен ли быть reactive? По семантике — да (mixin
      // добавляет Signal-поле, доступ к нему реактивен).
      expect(reactive, contains('wm'),
          reason: 'H3: WithMixin (с Signal из mixin) должен быть реактивен');
      expect(reactive, contains('v'),
          reason: 'H3: геттер, обращающийся к wm.hidden.value → computed');
    });

    // H4 [POSITIVE]: класс с Signal-полем, но геттер читает не-reactive часть.
    test('H4: getter reads non-reactive field of reactive class', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class Logger {
  final Signal<bool> verbose;     // ← есть Signal → Logger реактивен
  final String name;              // ← не-reactive
  Logger({required this.verbose, required this.name});
}

abstract class OverImpl {
  final Logger logger;
  OverImpl({required this.logger});
  String get tag => logger.name;  // читает ТОЛЬКО name, не verbose
}
''', storeImplNames: {});
      printOnFailure('H4 reads non-reactive part → reactive=$reactive');
      // ФАКТ: tag станет computed, т.к. logger реактивен, хоть читается name.
      // Это false POSITIVE (избыточная мемоизация) — безвредно, но неэффективно.
      expect(reactive, contains('tag'));
    });

    // H5 [POSITIVE]: геттер-фабрика, возвращающая Signal.
    test('H5: class with getter returning Signal (factory)', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class Factory {
  Signal<int> get make => Signal(0);  // геттер ВОЗВРАЩАЕТ новый Signal
}

abstract class FacImpl {
  final Factory factory;
  FacImpl({required this.factory});
  int get v => 42;
}
''', storeImplNames: {});
      printOnFailure('H5 factory getter returning Signal → reactive=$reactive');
      // ФАКТ: factory реактивен (в каскаде returnType=Signal), хотя make
      // — фабрика, а не реактивное свойство. Избыточное computed.
      expect(reactive, contains('factory'));
    });
  });

  // ===========================================================================
  // АУДИТ 2 — непроверенные сценарии (слои A-D).
  // Каждый тест фиксирует ФАКТИЧЕСКОЕ поведение.
  // ===========================================================================

  group('audit2: untested scenarios', () {
    // G1: helper-метод без target — обращение через локальный метод класса.
    test('G1: getter delegating to helper method', () async {
      final reactive = await _detect(r'''
abstract class HelperImpl {
  abstract int a;
  abstract int b;
  int get total => _sum();           // делегирует в helper
  int _sum() => a + b;               // helper читает reactive a, b
}
''');
      printOnFailure('G1 helper method → reactive=$reactive');
      // total не упоминает a/b напрямую — только _sum(). _sum — MethodInvocation
      // без target. Ожидаем: total должен стать computed (т.к. _sum реактивен
      // через свои обращения). Но _sum — НЕ getter, это метод → не в getters.
      expect(reactive, contains('total'),
          reason: 'G1: total делегирует в _sum, читающий reactive a,b');
    });

    // G2a: поле-подстор без геттера — попадает ли в базу reactive?
    test('G2a: substore field alone is in reactive base', () async {
      final reactive = await _detect(r'''
abstract class SubImpl {
  abstract dynamic currentUser;
}
abstract class BaseImpl {
  final SubImpl session;
  BaseImpl({required this.session});
}
''', storeImplNames: {'SubImpl'}, targetClass: 'BaseImpl');
      printOnFailure('G2a substore-only → reactive=$reactive');
      expect(reactive, contains('session'),
          reason: 'G2a: поле-подстор session (SubImpl ∈ storeImplNames) '
              'должно быть в reactive-базе');
    });

    // G2: null-safe доступ session?.currentUser.
    test('G2: null-safe access session?.field', () async {
      final reactive = await _detect(r'''
abstract class SubImpl {
  abstract dynamic currentUser;
}
abstract class NullSafeImpl {
  final SubImpl session;
  NullSafeImpl({required this.session});
  bool get x => session?.currentUser != null;
}
''', storeImplNames: {'SubImpl'}, targetClass: 'NullSafeImpl');
      printOnFailure('G2 null-safe → reactive=$reactive');
      expect(reactive, contains('x'),
          reason: 'G2: session?.currentUser — корень session реактивен');
    });

    // G3: spread в коллекции.
    test('G3: spread in collection literal', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
class T {}
abstract class SpreadImpl {
  final ListSignal<T> items;
  SpreadImpl({required this.items});
  List<T> get all => [...items];     // spread читает items
}
''', storeImplNames: {});
      printOnFailure('G3 spread → reactive=$reactive');
      expect(reactive, contains('all'),
          reason: 'G3: [...items] читает reactive items');
    });

    // G4: интерполяция строки.
    test('G4: string interpolation with reactive field', () async {
      final reactive = await _detect(r'''
abstract class StrImpl {
  abstract int a;
  String get label => 'count=$a';   // интерполяция читает a
}
''');
      printOnFailure('G4 interpolation → reactive=$reactive');
      expect(reactive, contains('label'),
          reason: 'G4: интерполяция читает reactive a');
    });

    // G5: generic-класс с параметром типа в Signal-поле.
    test('G5: generic class with Signal<T> field', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class Box<T> {
  final Signal<T> value;            // Signal с type-param T
  Box(this.value);
}

abstract class GenImpl {
  final Box<int> box;
  GenImpl({required this.box});
  int get v => box.value.value;     // обращение к box → реактивно?
}
''', storeImplNames: {});
      printOnFailure('G5 generic Signal<T> → reactive=$reactive');
      expect(reactive, contains('box'),
          reason: 'G5: Box<int> содержит Signal<T> → реактивен');
    });

    // G6: nullable Signal.
    test('G6: nullable Signal field', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

abstract class NullableImpl {
  final Signal<int>? maybe;         // nullable Signal
  NullableImpl({required this.maybe});
  int get v => maybe?.value ?? 0;
}
''', storeImplNames: {});
      printOnFailure('G6 nullable Signal → reactive=$reactive');
      expect(reactive, contains('maybe'),
          reason: 'G6: Signal<int>? — реактивный тип');
    });

    // G8: геттер и поле с одним именем (коллизия).
    test('G8: getter shadowing field with same name', () async {
      final reactive = await _detect(r'''
abstract class CollideImpl {
  abstract int a;
  int get a => a + 1;               // getter a перекрывает поле a
}
''');
      printOnFailure('G8 name collision → reactive=$reactive');
      // Документируем фактическое поведение — не упадёт ли детектор?
      expect(reactive, contains('a'),
          reason: 'G8: коллизия имя/геттер — детектор не должен падать');
    });

    // G9: block-body геттер с локальной переменной.
    test('G9: block-body getter with local var', () async {
      final reactive = await _detect(r'''
abstract class BlockImpl {
  abstract int a;
  abstract int b;
  int get sum {
    final temp = a;
    return temp + b;
  }
}
''');
      printOnFailure('G9 block-body → reactive=$reactive');
      expect(reactive, contains('sum'),
          reason: 'G9: block-body читает reactive a, b');
    });

    // G10: обращение к reactive внутри замыкания (callback).
    test('G10: reactive access inside closure callback', () async {
      final reactive = await _detect(r'''
abstract class ClosureImpl {
  abstract List<int> nums;
  int get doubledSum {
    return nums.map((e) => e * 2).fold(0, (p, e) => p + e);
  }
}
''');
      printOnFailure('G10 closure → reactive=$reactive');
      expect(reactive, contains('doubledSum'),
          reason: 'G10: nums читается (через map/fold) — реактивно');
    });

    // G11: вызов МЕТОДА подстора-@Store, метод читает reactive поля.
    //     total => counter.computeTotal(), где computeTotal() => a + b.
    test('G11: call method of @Store substore that reads reactive', () async {
      final reactive = await _detect(r'''
abstract class CounterImpl {
  abstract int a;
  abstract int b;
  int computeTotal() => a + b;      // метод читает reactive a, b
}
abstract class AppImpl {
  final CounterImpl counter;        // подстор (@Store impl)
  AppImpl({required this.counter});
  int get total => counter.computeTotal();  // вызов МЕТОДА подстора
}
''', storeImplNames: {'CounterImpl'}, targetClass: 'AppImpl');
      printOnFailure('G11 substore method → reactive=$reactive');
      // total обращается к counter (корень). counter реактивен как подстор
      // (CounterImpl ∈ storeImplNames) → total должно стать computed.
      expect(reactive, contains('counter'),
          reason: 'G11: поле-подстор counter реактивен');
      expect(reactive, contains('total'),
          reason: 'G11: геттер, вызывающий метод подстора → computed');
    });

    // G11b: тот же сценарий, но подстор — ОБЫЧНЫЙ класс (не @Store),
    //       инкапсулирующий реактивность. Это проверяет, ловит ли каскад
    //       реактивность через МЕТОДЫ (а не только поля/getters).
    test('G11b: call method of plain class wrapping reactive — actual behavior',
        () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';

class Counter {
  final Signal<int> a;              // Signal-поле → Counter реактивен (каскад)
  final Signal<int> b;
  Counter(this.a, this.b);
  int computeTotal() => a.value + b.value;  // метод читает signals
}

abstract class AppImpl {
  final Counter counter;            // тип Counter реактивен (Signal внутри)
  AppImpl({required this.counter});
  int get total => counter.computeTotal();
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G11b plain class method → reactive=$reactive');
      // Здесь counter реактивен через каскад (Counter содержит Signal-поля).
      // total => counter.computeTotal() — обращение к counter → reactive.
      expect(reactive, contains('total'),
          reason: 'G11b: counter реактивен → total computed');
    });

    // G12: вызов СОБСТВЕННОГО метода класса, который читает ГЛОБАЛЬНЫЙ signal.
    //      Подстора/реактивного поля НЕТ — только глобальная реактивная
    //      переменная, доступная через .value. Это сценарий из вопроса.
    test('G12: own method reading global signal via .value', () async {
      // G12a (контроль): геттер САМ читает .value глобального signal.
      final direct = await _detect(r'''
import 'package:signals/signals.dart';
final globalCount = signal(10);
abstract class AppImpl {
  int get total => globalCount.value * 2;    // напрямую .value
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G12a direct .value → reactive=$direct');
      expect(direct, contains('total'),
          reason: 'G12a контроль: прямой .value на signal → computed');

      // G12 (основной): через метод-посредник.
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalCount = signal(10);
abstract class AppImpl {
  int _helper() => globalCount.value * 2;   // читает глобальный signal
  int get total => _helper();               // вызывает этот метод
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G12 via method → reactive=$reactive');
      expect(reactive, contains('total'),
          reason: 'G12: _helper читает globalCount.value → total computed');
    });

    // =================================================================
    // Аналоги G12 — другие реактивные операции на Signal-объектах.
    // (Эмпирически подтверждено: .length, [], .where() реактивны;
    //  .peek(), .previousValue — намеренно НЕ реактивны.)
    // =================================================================

    // G13: globalMap.length — MapSignal через .length (НЕ .value).
    test('G13: global MapSignal.length is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalMap = mapSignal<String, int>({});
abstract class AppImpl {
  int get count => globalMap.length;        // .length на MapSignal
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G13 MapSignal.length → reactive=$reactive');
      expect(reactive, contains('count'),
          reason: 'G13: .length на MapSignal реактивен');
    });

    // G14: globalMap['key'] — MapSignal через индекс.
    test('G14: global MapSignal index access is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalMap = mapSignal<String, int>({'a': 1});
abstract class AppImpl {
  int get val => globalMap['a'] ?? 0;       // [] индекс на MapSignal
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G14 MapSignal[] → reactive=$reactive');
      expect(reactive, contains('val'),
          reason: 'G14: [] индекс на MapSignal реактивен');
    });

    // G15: globalList.where() — ListSignal через метод коллекции.
    test('G15: global ListSignal.where is reactive', () async {
      // G15a (контроль): прямой .length на ListSignal (без цепочки).
      final direct = await _detect(r'''
import 'package:signals/signals.dart';
final globalList = listSignal<int>([1, 2, 3]);
abstract class AppImpl {
  int get n => globalList.length;   // прямой .length на ListSignal
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G15a direct ListSignal.length → reactive=$direct');
      expect(direct, contains('n'),
          reason: 'G15a: прямой .length на ListSignal реактивен');

      // G15 (основной): цепочка globalList.where().length.
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalList = listSignal<int>([1, 2, 3]);
abstract class AppImpl {
  int get active => globalList.where((x) => x > 1).length;  // .where на ListSignal
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G15 chain ListSignal.where().length → reactive=$reactive');
      expect(reactive, contains('active'),
          reason: 'G15: .where() на ListSignal реактивен (в цепочке)');
    });

    // G16: signal.peek() — АНТИПАТТЕРН, НЕ должен стать computed.
    test('G16: signal.peek() is NOT reactive (stays plain)', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalSig = signal(10);
abstract class AppImpl {
  int get peeked => globalSig.peek();       // намеренно untracked
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G16 signal.peek() → reactive=$reactive');
      expect(reactive, isNot(contains('peeked')),
          reason: 'G16: .peek() намеренно не реактивен → остаётся обычным');
    });

    // =================================================================
    // Разные signal-типы из библиотеки (не только коллекции).
    // Эмпирически подтверждено: AsyncSignal, FutureSignal, TrackedSignal,
    // StreamSignal, IterableSignal — все реактивны через .value / операции.
    // Проверяем, что детектор (через _isSignalType) их распознаёт.
    // =================================================================

    // G17: AsyncSignal — .value (AsyncState) и .value.isLoading.
    test('G17: AsyncSignal .value and .value.isLoading are reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalAsync = asyncSignal<int>(AsyncState.loading());
abstract class AppImpl {
  bool get loading => globalAsync.value.isLoading;  // цепочка .value.isLoading
  dynamic get state => globalAsync.value;           // прямой .value
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G17 AsyncSignal → reactive=$reactive');
      expect(reactive, containsAll(['loading', 'state']),
          reason: 'G17: AsyncSignal.value и .value.isLoading реактивны');
    });

    // G18: FutureSignal — .value (AsyncState).
    test('G18: FutureSignal .value is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalFuture = futureSignal<int>(() async => 5);
abstract class AppImpl {
  bool get loading => globalFuture.value.isLoading;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G18 FutureSignal → reactive=$reactive');
      expect(reactive, contains('loading'),
          reason: 'G18: FutureSignal.value реактивен');
    });

    // G19: TrackedSignal — .value.
    test('G19: TrackedSignal .value is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalTracked = trackedSignal<int>(0);
abstract class AppImpl {
  int get val => globalTracked.value;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G19 TrackedSignal → reactive=$reactive');
      expect(reactive, contains('val'),
          reason: 'G19: TrackedSignal.value реактивен');
    });

    // G20: StreamSignal — .value (AsyncState).
    test('G20: StreamSignal .value is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
import 'dart:async';
final globalStream = streamSignal<int>(() => Stream<int>.empty());
abstract class AppImpl {
  bool get loading => globalStream.value.isLoading;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G20 StreamSignal → reactive=$reactive');
      expect(reactive, contains('loading'),
          reason: 'G20: StreamSignal.value реактивен');
    });

    // G21: IterableSignal — .length (как коллекция, но не List/Map/Set).
    test('G21: IterableSignal .length is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalIt = iterableSignal<int>([1, 2, 3]);
abstract class AppImpl {
  int get count => globalIt.length;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G21 IterableSignal → reactive=$reactive');
      expect(reactive, contains('count'),
          reason: 'G21: IterableSignal.length реактивен');
    });

    // G22: SetSignal — .length (множество, не Map/List).
    test('G22: SetSignal .length is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalSet = setSignal<int>({1, 2, 3});
abstract class AppImpl {
  int get count => globalSet.length;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G22 SetSignal → reactive=$reactive');
      expect(reactive, contains('count'),
          reason: 'G22: SetSignal.length реактивен');
    });

    // G23: QueueSignal — .length (очередь).
    test('G23: QueueSignal .length is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
import 'dart:collection';
final globalQueue = queueSignal<int>(Queue<int>());
abstract class AppImpl {
  int get count => globalQueue.length;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G23 QueueSignal → reactive=$reactive');
      expect(reactive, contains('count'),
          reason: 'G23: QueueSignal.length реактивен');
    });

    // G24: ReadonlySignal — базовый реактивный контракт.
    test('G24: ReadonlySignal .value is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
ReadonlySignal<int> globalRo = signal(10);
abstract class AppImpl {
  int get val => globalRo.value;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G24 ReadonlySignal → reactive=$reactive');
      expect(reactive, contains('val'),
          reason: 'G24: ReadonlySignal.value реактивен');
    });

    // =================================================================
    // Тонкие случаи: подсвойства AsyncState, мутации, untracked.
    // Эмпирически: .hasValue реактивен; чистая мутация (write) — НЕ реактивна.
    // =================================================================

    // G25: AsyncState.hasValue через цепочку .value.hasValue.
    test('G25: AsyncState.hasValue (chained) is reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalAsync = asyncSignal<int>(AsyncState.data(42));
abstract class AppImpl {
  bool get ready => globalAsync.value.hasValue;  // цепочка .value.hasValue
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G25 AsyncState.hasValue → reactive=$reactive');
      expect(reactive, contains('ready'),
          reason: 'G25: .value.hasValue реактивен');
    });

    // G26: MapSignal.isEmpty, .containsKey, .keys — другие операции коллекции.
    test('G26: MapSignal.isEmpty / containsKey / keys are reactive', () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalMap = mapSignal<String, int>({'a': 1});
abstract class AppImpl {
  bool get empty => globalMap.isEmpty;
  bool get hasA => globalMap.containsKey('a');
  int get keyCount => globalMap.keys.length;
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G26 Map ops → reactive=$reactive');
      expect(reactive, containsAll(['empty', 'hasA', 'keyCount']),
          reason: 'G26: isEmpty, containsKey, keys.length реактивны');
    });

    // G27: ЧИСТАЯ мутация — геттер только пишет в signal (m.value = x).
    //      Эмпирически это НЕ реактивно (мутация не регистрирует зависимость
    //      чтения). Детектор НЕ должен делать такой геттер computed.
    test('G27: pure mutation (write only) is NOT reactive — actual behavior',
        () async {
      final reactive = await _detect(r'''
import 'package:signals/signals.dart';
final globalSig = signal(0);
abstract class AppImpl {
  int get setter {
    globalSig.value = 5;   // только МУТАЦИЯ (write), без чтения
    return 42;
  }
}
''', storeImplNames: {}, targetClass: 'AppImpl');
      printOnFailure('G27 pure mutation → reactive=$reactive');
      // Документируем ФАКТИЧЕСКОЕ поведение детектора. Эмпирически мутация
      // не реактивна, но детектор может её засчитать (false positive).
      expect(reactive, isNot(contains('setter')),
          reason: 'G27: чистая мутация (write) не реактивна → не computed');
    });
  });

  // ===========================================================================
  // АУДИТ 3 — потоки данных (dataflow) через аргументы вызовов.
  //
  // Сценарий: геттер передаёт reactive-значение как АРГУМЕНТ в helper-метод,
  // который сам по себе не реактивен (параметр — не свойство стора).
  //   int get formatted => _fmt(balance);   // balance reactive
  //   String _fmt(double v) => ...;          // v — параметр, не reactive
  // Логически formatted реактивен (зависит от balance), но детектор анализирует
  // тела независимо и не отслеживает поток аргументов → formatted остаётся plain.
  // Эти тесты фиксируют целевое поведение (после реализации dataflow) и/или
  // текущее ограничение.
  // ===========================================================================

  group('audit3: dataflow through call arguments', () {
    // D1: геттер передаёт reactive-поле как аргумент в helper-метод.
    test('D1: getter passing reactive field as helper argument — target behavior',
        () async {
      final reactive = await _detect(r'''
abstract class DataflowImpl {
  abstract double balance;
  String get formatted => _fmt(balance);   // balance (reactive) → аргумент
  String _fmt(double v) => '${v.toStringAsFixed(2)}';  // v — параметр
}
''', storeImplNames: {}, targetClass: 'DataflowImpl');
      printOnFailure('D1 dataflow field→arg → reactive=$reactive');
      // Целевое поведение (после реализации dataflow): formatted становится
      // computed, т.к. в вызове _fmt(balance) аргумент balance реактивен.
      // _fmt НЕ становится computed (это метод, не геттер), но учитывается
      // в фикс-пойнте: раз formatted передаёт reactive-аргумент в _fmt, и _fmt
      // выполняется в контексте formatted → formatted реактивен.
      expect(reactive, contains('formatted'),
          reason: 'D1: formatted передаёт reactive balance как аргумент → '
              'должен стать computed (dataflow)');
    });

    // D2: геттер передаёт НЕ-reactive аргумент → остаётся plain.
    test('D2: getter passing non-reactive argument stays plain', () async {
      final reactive = await _detect(r'''
abstract class PlainArgImpl {
  final String label;
  PlainArgImpl({required this.label});
  String get upper => _fmt(label);   // label — concrete-поле, не reactive
  String _fmt(String s) => s.toUpperCase();
}
''', storeImplNames: {}, targetClass: 'PlainArgImpl');
      printOnFailure('D2 non-reactive arg → reactive=$reactive');
      expect(reactive, isNot(contains('upper')),
          reason: 'D2: label не reactive → upper остаётся plain');
    });

    // D3: цепочка dataflow — геттер передаёт reactive в helper, который
    //     передаёт его дальше в другой helper.
    test('D3: chained dataflow through nested helper calls', () async {
      final reactive = await _detect(r'''
abstract class ChainDataflowImpl {
  abstract int a;
  String get outer => _mid(a);          // a (reactive) → _mid
  String _mid(int v) => _inner(v);      // v → _inner (поток a)
  String _inner(int v) => v.toString();
}
''', storeImplNames: {}, targetClass: 'ChainDataflowImpl');
      printOnFailure('D3 chained dataflow → reactive=$reactive');
      expect(reactive, contains('outer'),
          reason: 'D3: поток a через цепочку _mid→_inner → outer computed');
    });

    // D4: dataflow через computed-геттер (не поле) как аргумент.
    test('D4: getter passing another computed as argument', () async {
      final reactive = await _detect(r'''
abstract class ComputedArgImpl {
  abstract int a;
  int get sum => a + 1;                 // sum — computed (читает a)
  String get report => _fmt(sum);       // sum (computed) → аргумент _fmt
  String _fmt(int v) => '=$v';
}
''', storeImplNames: {}, targetClass: 'ComputedArgImpl');
      printOnFailure('D4 computed as arg → reactive=$reactive');
      expect(reactive, containsAll(['sum', 'report']),
          reason: 'D4: sum computed → report (через dataflow sum) computed');
    });

    // D5: dataflow через подстор (поле подстора как аргумент).
    test('D5: getter passing substore field as argument', () async {
      final reactive = await _detect(r'''
abstract class SubImpl {
  abstract double amount;
}
abstract class SubArgImpl {
  final SubImpl savings;
  SubArgImpl({required this.savings});
  String get label => _fmt(savings.amount);  // savings.amount (reactive) → arg
  String _fmt(double v) => v.toStringAsFixed(2);
}
''', storeImplNames: {'SubImpl'}, targetClass: 'SubArgImpl');
      printOnFailure('D5 substore arg → reactive=$reactive');
      expect(reactive, contains('label'),
          reason: 'D5: savings.amount (подстор) как аргумент → label computed');
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Пишет `source` во временный файл, резолвит через `AnalysisContextCollection`
/// и вызывает детектор на первом `abstract`-классе источника.
///
/// [storeImplNames] моделирует результат, который в генераторе получается
/// из карты `implToStoreName.keys` (имена impl-классов, помеченных `@Store`).
/// Concrete-поле, типизированное таким классом, реактивно как подстор.
/// *Signal-коллекции* (MapSignal, ListSignal, ...) и классы с Signal внутри
/// определяются детектором автоматически через тип — передавать их не нужно.
Future<Set<String>> _detect(
  String source, {
  Set<String>? storeImplNames,
  String? targetClass,
}) async {
  // Каждый вызов — изолированная поддиректория со своим pubspec и
  // package_config (через symlink на общий .dart_tool).
  final dir = Directory(p.join(_tempDir, 'case_${_fileCounter++}'));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'pubspec.yaml')).writeAsString(
    'name: case_pkg\nenvironment:\n  sdk: ^3.12.0\ndependencies:\n  signals: ^7.0.0\n',
  );
  await Link(p.join(dir.path, '.dart_tool'))
      .create(p.join(_tempDir, '.dart_tool'));
  final file = File(p.join(dir.path, 'store.dart'));
  await file.writeAsString(source);

  final collection = AnalysisContextCollection(
    includedPaths: [dir.path],
    sdkPath: _dartSdkPath,
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );
  final context = collection.contexts.single;
  final session = context.currentSession;
  final resolved = await session.getResolvedUnit(file.path);
  if (resolved is! ResolvedUnitResult) {
    throw StateError('Не удалось зарезолвить unit: $resolved');
  }
  // Целевой класс: явно указанный [targetClass], иначе первый abstract-класс.
  final candidates = resolved.unit.declarations
      .whereType<ClassDeclaration>()
      .where((c) => c.abstractKeyword != null || c.name.toString() == targetClass);
  final ClassDeclaration clazz;
  if (targetClass != null) {
    clazz = candidates.firstWhere(
      (c) => c.name.toString() == targetClass,
      orElse: () => throw StateError('Класс $targetClass не найден в источнике'),
    );
  } else {
    clazz = candidates.first;
  }
  final fragment = clazz.declaredFragment;
  if (fragment == null) {
    throw StateError('ClassDeclaration без declaredFragment: ${clazz.name}');
  }
  final element = fragment.element;
  return computeReactiveGetters(
    clazz: element,
    storeImplNames: storeImplNames ?? const {},
  );
}

/// Путь к Dart SDK, с которым работает текущий `flutter`.
///
/// Тот же алгоритм, что в `flutter_test_harness._findDartSdkPath`: поднимаемся
/// вверх от `Platform.resolvedExecutable` (под `flutter test` это
/// `flutter_tester`), пока не найдём каталог `dart-sdk` с `libraries.dart`.
String _findDartSdkPath() {
  bool isValid(String path) =>
      File(p.join(path, 'version')).existsSync() &&
      File(p.join(path, 'bin', 'dart')).existsSync();

  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 10; i++) {
    final candidate = p.join(dir.path, 'dart-sdk');
    if (isValid(candidate)) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  final envSdk = Platform.environment['FLUTTER_DART_SDK'];
  if (envSdk != null && isValid(envSdk)) return envSdk;
  throw StateError('Не удалось определить путь к Dart SDK по '
      'Platform.resolvedExecutable=${Platform.resolvedExecutable}. '
      'Установите FLUTTER_DART_SDK=<путь к dart-sdk>.');
}
