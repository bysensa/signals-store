// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Имена типов из `dart:core`, которые гарантированно **не** реактивны.
///
/// Обрезают рекурсию [isReactiveType]: иначе спуск в поля `List<E>`, `Map<K,V>`
/// или `Object` уводил бы анализ в core-библиотеку. `Signal` сюда не входит —
/// он реактивен по определению.
const _nonReactiveCoreTypes = <String>{
  'bool',
  'double',
  'int',
  'num',
  'String',
  'Symbol',
  'Type',
  'Object',
  'Null',
  'void',
  'dynamic',
  'Never',
  'Future',
  'Stream',
  'Iterable',
  'Iterator',
  'List',
  'Set',
  'Map',
  'MapEntry',
  'DateTime',
  'Duration',
  'Uri',
  'Enum',
};

/// {@template is_reactive_type}
/// Является ли тип реактивным — единый признак для всех сценариев.
///
/// Тип `T` реактивен, если выполняется хотя бы одно:
/// 1. `T` — подтип `Signal` (`Signal<T>`, `MapSignal<K,V>`, `ListSignal<E>`,
///    `Computed<T>`, `TrackedSignal`, ...). Проверяется через
///    `typeSystem.isSubtypeOf` — устойчиво к появлению новых signals-типов.
/// 2. `T` — `@Store` impl-класс (имя ∈ [storeImplNames]).
/// 3. `T` — пользовательский класс, у которого есть хотя бы одно реактивное
///    поле или геттер (каскад на любую глубину). Защита от циклов типов —
///    через `visited`.
///
/// Примитивы и коллекции `dart:core` (см. [_nonReactiveCoreTypes]) всегда
/// не-реактивны — обрезают рекурсию, не уводя анализ в core-библиотеку.
/// {@endtemplate}
bool isReactiveType(
  DartType type,
  Set<String> storeImplNames, {
  Set<String> visited = const {},
}) {
  // 1. core-примитивы и базовые коллекции — точно не реактивны (обрезаем).
  final element = type is InterfaceType ? type.element : null;
  if (element != null && _nonReactiveCoreTypes.contains(element.name)) {
    return false;
  }

  // 2. Подтип Signal → реактивен (MapSignal, ListSignal, Computed, и т.д.).
  //    Один критерий для всех signals-типов, включая будущие и пользовательские
  //    реализации `implements Signal` — без списка имён.
  if (element != null && _isSignalType(type)) {
    return true;
  }

  // 3. @Store impl-класс → реактивен (подстор).
  if (element != null && storeImplNames.contains(element.name)) {
    return true;
  }

  // 4. Каскад: рекурсивный анализ полей класса (любая глубина).
  //    InterfaceElement — общий предок ClassElement и MixinElement, чтобы
  //    корректно обрабатывать поля из mixins (H3): MixinElement НЕ является
  //    ClassElement, но имеет .fields/.getters/.mixins.
  if (element is InterfaceElement) {
    return _classHasReactiveMember(element, storeImplNames, visited);
  }

  return false;
}

/// Проверяет, есть ли в классе/mixin (включая его mixins) хотя бы один
/// реактивный член: поле или геттер.
///
/// Mixin-поля (`class W with M {}`, где в `M` есть `Signal`) не всегда входят
/// в `ClassElement.fields`, поэтому обходим `mixins` явно (H3). Суперкласс
/// опускаем — `Object` не реактивен, а пользовательские базовые классы
/// покрываются рекурсивным `isReactiveType` над типами их полей.
bool _classHasReactiveMember(
  InterfaceElement element,
  Set<String> storeImplNames,
  Set<String> visited,
) {
  final name = element.name;
  if (name == null) return false;
  if (visited.contains(name)) return false; // защита от циклов типов
  final nextVisited = {...visited, name};

  // Поля самого класса/mixin.
  for (final field in element.fields) {
    if (field.isStatic || !field.isOriginDeclaration || field.isLate) continue;
    if (isReactiveType(field.type, storeImplNames, visited: nextVisited)) {
      return true;
    }
  }
  // Геттеры тоже могут быть реактивными (int get x => _sig.value).
  for (final getter in element.getters) {
    if (getter.isAbstract || getter.isStatic || !getter.isOriginDeclaration) continue;
    // Геттер реактивен, если его тип возврата реактивен (упрощённая проверка —
    // без анализа тела, иначе возможны циклы через getter-ссылки).
    if (isReactiveType(
      getter.returnType,
      storeImplNames,
      visited: nextVisited,
    )) {
      return true;
    }
  }
  // Поля из вложенных mixins: `class W with M {}` — поля M могут не входить
  // в W.fields. MixinElement — отдельный тип, не ClassElement.
  for (final mixinType in element.mixins) {
    if (_classHasReactiveMember(
      mixinType.element,
      storeImplNames,
      nextVisited,
    )) {
      return true;
    }
  }

  return false;
}

/// Признак: `type` — подтип `Signal` (или сам `Signal`).
///
/// Признак: `type` — `Signal` или его подтип (через `extends` ИЛИ `implements`).
///
/// Обходит ВСЮ иерархию типа: `superclass` и все `interfaces` (BFS). Это
/// покрывает `class MySignal implements ReadonlySignal` (H2), а не только
/// прямое наследование `extends Signal`.
///
/// Сравнение по имени вместо `isSubtypeOf` намеренное: нам не нужно
/// каноническое представление типа (его сложно получить без typeProvider),
/// достаточно убедиться, что в иерархии есть reactive-интерфейс из пакета
/// `signals`. Риск коллизии имен минимален (импорты различают).
///
/// `ReadonlySignal` включён, т.к. это базовый реактивный контракт в signals:
/// `class Signal<T> with ReadonlySignal<T>`, и пользовательский
/// `class X implements ReadonlySignal` — тоже реактивен (H2).
bool _isSignalType(DartType type) {
  if (type is! InterfaceType) return false;
  final visited = <String>{};
  final queue = <InterfaceType>[type];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    final name = current.element.name;
    if (name == null) continue;
    if (_reactiveTypeNames.contains(name)) return true;
    if (!visited.add(name)) continue; // защита от циклов в иерархии
    final sup = current.superclass;
    if (sup != null) queue.add(sup);
    queue.addAll(current.interfaces);
    // mixin-ы тоже часть иерархии (Signal uses ReadonlySignal as mixin).
    queue.addAll(current.mixins);
  }
  return false;
}

/// Имена реактивных контрактов из пакета `signals`, которые считаем признаком
/// реактивности типа при обходе иерархии в [_isSignalType].
const _reactiveTypeNames = <String>{'Signal', 'ReadonlySignal'};

/// {@template reactivity_intro}
/// Определение реактивности concrete-геттеров.
///
/// Concrete-геттер (геттер с телом) в `@Store`-классе превращается в `Computed`
/// **тогда и только тогда**, когда в его теле есть обращение к реактивному имени
/// стора. Реактивные имена — это:
///
/// 1. **abstract-поля** (`abstract int a;`) — обёрнуты в `Signal`;
/// 2. **concrete-поля-подсторы** (`final SessionStoreImpl session;`, тип — impl
///    другого `@Store`) — доступ к их полям реактивен через их собственные
///    signals;
/// 3. **concrete-геттеры**, чьи тела сами ссылаются на реактивные имена
///    (транзитивное замыкание через фикс-пойнт).
///
/// Concrete-поля **не-стор** (`final String label;`), литералы, обращения к
/// типам (`DateTime.now()`) и параметрам — **не** реактивны.
/// {@endtemplate}
///
/// {@template reactivity_algorithm}
/// Алгоритм — итеративное насыщение (фикс-пойнт):
///
/// 1. База: `reactive = abstract-поля ∪ concrete-поля-подсторы`.
/// 2. Повторять, пока множество растёт: геттер `g` добавляется в `reactive`,
///    если его тело упоминает хотя бы одно имя из `reactive`.
/// 3. Все геттеры из `reactive` → `Computed`; прочие — остаются обычными.
///
/// Сложность O(n²) по числу геттеров (n — единицы на стор), на практике
/// стабилизируется за 1-2 итерации.
/// {@endtemplate}
///
/// Асинхронность: резолвинг AST-тел геттеров через `session` требует
/// `Future` (см. [_getterReferencedRoots]). Фикс-пойнт над собранной картой —
/// уже синхронный.
///
/// [storeImplNames] — имена impl-классов, помеченных `@Store` в этой
/// библиотеке (карта `implToStoreName.keys` из генератора). Нужны для
/// [isReactiveType]: concrete-поле, типизированное таким impl-классом,
/// реактивно как подстор.
Future<Set<String>> computeReactiveGetters({
  required ClassElement clazz,
  required Set<String> storeImplNames,
  Set<String> extraReactiveNames = const {},
}) async {
  // 1. База реактивных имён.
  //    - abstract-поля (обёрнуты в Signal).
  //    - concrete-поля с реактивным типом: @Store impl-подстор, *Signal-коллекция
  //      (MapSignal, ListSignal, ...), или пользовательский класс с Signal
  //      внутри (каскад, см. isReactiveType).
  //    - [extraReactiveNames] — дополнительные реактивные имена, не являющиеся
  //      полями класса (для @DerivedStore: имя root-геттера; его тип ∈ rootImplNames
  //      ⊂ storeImplNames, но геттеры в базу полей не входят). Геттеры, читающие
  //      эти имена, становятся computed существующим фикс-пойнтом.
  //    Геттеры сюда добавит фикс-пойнт.
  final reactive = <String>{
    for (final f in _instanceFields(clazz))
      if (f.isAbstract || isReactiveType(f.type, storeImplNames)) f.name!,
    ...extraReactiveNames,
  };

  final getters = _concreteGetters(clazz).toList();
  final methods = _concreteMethods(clazz).toList();
  if (getters.isEmpty && methods.isEmpty) return reactive;

  // 2. Анализируем тело каждого геттера И метода (async-проход).
  //    Методы участвуют в фикс-пойнте как промежуточные reactive-имена:
  //    если `_sum()` читает reactive a,b → `_sum` реактивен → геттер,
  //    делегирующий в `_sum()`, тоже становится computed (G1).
  final analysisByMember = <String, _BodyAnalysis>{};
  for (final g in getters) {
    analysisByMember[g.name!] = await _analyzeBody(g, storeImplNames);
  }
  for (final m in methods) {
    analysisByMember[m.name!] = await _analyzeBody(m, storeImplNames);
  }

  // 3. Фикс-пойнт: пока множество растёт (чистая синхронная логика).
  //    Член реактивен, если:
  //    - его тело ссылается на уже-reactive имя (поле/подстор/геттер/метод), ИЛИ
  //    - его тело содержит `signal.value` (чтение .value на Signal-типе — G12).
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in analysisByMember.entries) {
      final memberName = entry.key;
      if (reactive.contains(memberName)) continue;
      final analysis = entry.value;
      final referencesReactive = analysis.roots.any(reactive.contains);
      if (referencesReactive || analysis.hasSignalAccess) {
        reactive.add(memberName);
        changed = true;
      }
    }
  }

  return reactive;
}

/// Все concrete-методы класса (методы с телом — не abstract).
///
/// Нужны для фикс-пойнта: геттер может делегировать в helper-метод
/// (`int get total => _sum();`), который сам читает reactive-поля. Метод
/// становится промежуточным reactive-именем — но НЕ генерируется как Computed
/// (только геттеры). См. G1 в аудите корректности.
Iterable<MethodElement> _concreteMethods(ClassElement clazz) {
  return clazz.methods.where(
    (m) => !m.isAbstract && !m.isStatic && m.isOriginDeclaration,
  );
}

/// Все concrete-геттеры класса (геттеры с телом — не abstract).
///
/// `GetterElement` (подтип `PropertyAccessorElement`) с `isGetter == true` и
/// `isAbstract == false`. `static`/`synthetic`-геттеры игнорируются (не
/// состояние экземпляра стора — аналогично полям в [_instanceFields]).
Iterable<GetterElement> _concreteGetters(ClassElement clazz) {
  return clazz.getters.where(
    (a) => !a.isAbstract && !a.isStatic && a.isOriginDeclaration,
  );
}

/// Instance-поля класса, не-synthetic, не-static, не-late.
///
/// Совпадает с фильтром `_allFields` в `store_generator.dart` — чтобы база
/// реактивных имён была консистентна с полями, которые генератор превращает
/// в signals.
Iterable<FieldElement> _instanceFields(ClassElement clazz) {
  return clazz.fields.where((f) => f.isOriginDeclaration && !f.isStatic && !f.isLate);
}

/// Результат анализа тела геттера/метода на реактивность.
class _BodyAnalysis {
  _BodyAnalysis(this.roots, this.hasSignalAccess);

  /// Корневые имена обращений (см. [_analyzeBody]).
  final Set<String> roots;

  /// True, если в теле есть обращение к выражению типа Signal/ReadonlySignal
  /// (кроме untracked) — `.value`, `.length`, `[]`, `.where()` и т.д.
  /// Это реактивность, не связанная с полями стора (G12-G15).
  final bool hasSignalAccess;
}

/// Извлекает множество «корней» всех обращений в теле геттера/метода.
///
/// «Корень» — это базовое имя, которое разработчик использует в исходном коде:
/// `a`, `session` (из `session.currentUser`), `ui` (из `ui.filter.sortBy`),
/// `sum` (из `sum * 2`), `label` (из `label.toUpperCase()`).
///
/// Типы (`DateTime`), литералы и параметры отсекаются на этапе проверки
/// `staticElement` (см. [_referencedRootOf]). Возвращает пустое множество,
/// если AST-тело недоступно (например, член без сессии).
Future<_BodyAnalysis> _analyzeBody(
  ExecutableElement member,
  Set<String> storeImplNames,
) async {
  final body = await _resolvedBodyNode(member);
  if (body == null) return _BodyAnalysis(<String>{}, false);
  final collector = _RootCollector(storeImplNames);
  body.accept(collector);
  return _BodyAnalysis(collector.roots, collector.hasSignalAccess);
}

/// Получает AST-узел тела (function body) геттера или метода через resolved
/// library.
///
/// Analyzer 8.x: `session.getResolvedLibraryByElement` (experimental, async)
/// возвращает sealed `SomeResolvedLibraryResult`; успешный случай —
/// [ResolvedLibraryResult]. Через `getFragmentDeclaration(element.firstFragment)`
/// получаем `FragmentDeclarationResult`, чей `.node` — это `MethodDeclaration`
/// для геттера/метода (его `.body` и есть искомое тело).
Future<FunctionBody?> _resolvedBodyNode(ExecutableElement member) async {
  final session = member.session;
  if (session == null) return null;
  final result = await session.getResolvedLibraryByElement(member.library);
  if (result is! ResolvedLibraryResult) return null;
  final declaration = result.getFragmentDeclaration(member.firstFragment);
  final node = declaration?.node;
  if (node is MethodDeclaration) return node.body;
  return null;
}

/// {@template root_collector}
/// AST-визитор, собирающий корневые имена всех обращений в поддереве.
///
/// Наследуется от [GeneralizingAstVisitor]: он автоматически рекурсивно
/// обходит детей через `visitNode`. Мы переопределяем только узлы-обращения,
/// а для остальных `visitNode` продолжит рекурсию.
///
/// Из visit-методов обращений мы **не** вызываем `super` — это запрещает
/// визитору спускаться ВНУТРЬ уже обработанного обращения (корень цепочки
/// обработан целиком: `session.currentUser` → только `session`).
/// {@endtemplate}
class _RootCollector extends GeneralizingAstVisitor<void> {
  _RootCollector(this.storeImplNames);

  /// Имена impl-классов, помеченных `@Store`. Нужны для поточечной проверки
  /// полей подстора (FP-4): `config.label` где `label` — concrete pass-through.
  final Set<String> storeImplNames;

  final roots = <String>{};

  /// True, если в теле есть обращение к выражению типа Signal/ReadonlySignal
  /// (или подтипу), кроме явных untracked-доступов. Это реактивность, не
  /// связанная с полями стора — глобальные signal-переменные и любые операции
  /// на них: `.value`, `.length`, `[]`, `.where()` (G12-G15).
  ///
  /// Не взводится для `.peek()` и `.previousValue` — намеренно untracked (G16).
  bool hasSignalAccess = false;

  /// Имена свойств/методов на Signal, которые НЕ устанавливают реактивную
  /// зависимость (чтение без трекинга). См. документацию signals.
  static const _untrackedAccessors = <String>{
    'peek',
    'previousValue',
  };

  /// Проверяет обращение к выражению [target] с именем [accessor]:
  /// если тип target — Signal-подтип, а accessor не untracked → реактивно.
  /// Не учитывается, если всё выражение-обращение является LHS присваивания
  /// (мутация сигнала не устанавливает зависимость чтения — G27).
  void _checkSignalAccess(Expression? target, String accessor) {
    if (_untrackedAccessors.contains(accessor)) return;
    final type = target?.staticType;
    if (type != null && _isSignalType(type)) {
      hasSignalAccess = true;
    }
  }

  /// Определяет, реактивно ли чтение конкретного поля [fieldName] у выражения
  /// типа [targetType], когда targetType — @Store-подстор.
  ///
  /// Решает FP-4: геттер вида `config.label`, где `config` — подстор, а
  /// `label` — concrete pass-through поле (не Signal, не abstract). Раньше
  /// детектор считал весь подстор реактивным и делал геттер computed
  /// избыточно. Теперь проверяем КОНКРЕТНОЕ поле:
  /// - abstract-поле → реактивно (обёрнуто в Signal);
  /// - concrete-поле с Signal-типом → реактивно;
  /// - concrete-поле с @Store impl типом → реактивно (вложенный подстор);
  /// - concrete-поле с user-классом, содержащим Signal → реактивно (каскад);
  /// - прочее concrete-поле → НЕ реактивно (FP-4 исключён).
  ///
  /// Возвращает `true`, если поле реактивно ИЛИ если targetType НЕ подстор
  /// (в этом случае реактивность определяется другими правилами, не здесь).
  bool _isReactiveFieldAccess(DartType? targetType, String fieldName) {
    if (targetType is! InterfaceType) return true;
    final element = targetType.element;
    // Только для @Store-подсторов делаем поточечную проверку поля. Для прочих
    // типов (Signal-коллекции, user-классы) реактивность определяется вне.
    if (!storeImplNames.contains(element.name)) return true;
    // Ищем конкретное поле по имени в @Store-классе.
    final field = _findField(element, fieldName);
    if (field == null) return true; // геттер или унаследованное — консервативно реактивно
    // abstract-поле → обёрнуто в Signal → реактивно.
    if (field.isAbstract) return true;
    // concrete-поле → реактивно, только если его тип реактивен.
    return isReactiveType(field.type, storeImplNames);
  }

  /// Ищет instance-поле по имени в классе (не static, не synthetic, не late).
  FieldElement? _findField(InterfaceElement clazz, String name) {
    for (final f in clazz.fields) {
      if (f.isStatic || !f.isOriginDeclaration || f.isLate) continue;
      if (f.name == name) return f;
    }
    return null;
  }

  /// True, если [node] — левая часть присваивания (`node = ...`, `node ??= ...`
  /// и т.п.), то есть это КОНТЕКСТ ЗАПИСИ, а не чтения.
  ///
  /// Используется, чтобы не считать реактивным доступ к signal, который только
  /// мутируется (G27: `sig.value = 5;`). Мутация не регистрирует зависимость.
  bool _isWriteTarget(Expression node) {
    final parent = node.parent;
    if (parent is AssignmentExpression) {
      return identical(parent.leftHandSide, node);
    }
    // `++sig.value`, `sig.value += x` — compound-assignment/postfix тоже запись.
    // Они реализованы через AssignmentExpression, так что проверка выше covers их.
    return false;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = _referencedRootOf(node);
    if (name != null) roots.add(name);
    // НЕ вызываем super: SimpleIdentifier — лист.
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // `globalCount.value` / `globalMap.length` где тип prefix — Signal:
    // любое свойство (кроме untracked) реактивно (G12, G13). Но если это LHS
    // присваивания (`sig.value = x`) — это мутация, не чтение (G27).
    if (!_isWriteTarget(node)) {
      _checkSignalAccess(node.prefix, node.identifier.name);
    }
    // `session.currentUser` / `config.label` → корень prefix, НО только если
    // читаемое поле реактивно. Для @Store-подстора проверяем конкретное поле
    // (FP-4: `config.label` где label — concrete pass-through → не реактивно).
    final name = _referencedRootOf(node.prefix);
    if (name != null &&
        _isReactiveFieldAccess(node.prefix.staticType, node.identifier.name)) {
      roots.add(name);
    }
    // НЕ спускаемся в `.identifier`.
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    // `xxx.value` / `xxx.length` где тип xxx — Signal: реактивно (G12, G13).
    // Но если это LHS присваивания (`sig.value = x`) — мутация, не чтение (G27).
    if (!_isWriteTarget(node)) {
      _checkSignalAccess(node.target, node.propertyName.name);
    }
    // `this.a` → корень propertyName (имя поля текущего класса), т.к. this
    // указывает на сам стор и не несёт реактивной информации.
    if (node.target is ThisExpression) {
      roots.add(node.propertyName.name);
      return;
    }
    // `ui.filter.sortBy` / `config.label` → корень через рекурсию по target,
    // НО только если читаемое поле реактивно. Для @Store-подстора проверяем
    // конкретное поле (FP-4: concrete pass-through поле → не реактивно).
    final name = _referencedRootOf(node.target);
    if (name != null &&
        _isReactiveFieldAccess(node.target?.staticType, node.propertyName.name)) {
      roots.add(name);
    }
    // Спускаемся в target для цепочек: `a.b.sig.value` — target может сам
    // быть PropertyAccess с Signal-типом, и его нужно проверить (G15-аналог).
    node.target?.accept(this);
    // НЕ спускаемся в propertyName.
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    // `globalMap['key']` / `globalList[0]` где тип target — Signal-коллекция:
    // индексный доступ реактивен (G14). Сам target обходится ниже через
    // общий механизм (SimpleIdentifier → roots).
    final targetType = node.target?.staticType;
    if (targetType != null && _isSignalType(targetType)) {
      hasSignalAccess = true;
    }
    // index и target обходятся через общий механизм посетителей.
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // `globalList.where(...)` / `signal.peek()` где тип target — Signal:
    // вызов метода реактивен, КРОМЕ untracked (.peek).
    final target = node.target;
    if (target != null) {
      _checkSignalAccess(target, node.methodName.name);
      final name = _referencedRootOf(target);
      if (name != null) roots.add(name);
      // Спускаемся в target: для цепочки `globalList.where().length` внешний
      // PropertyAccess(.length) имеет target=MethodInvocation(.where) с типом
      // Iterable (не Signal), и только внутренний target globalList — Signal.
      // Без рекурсии в target мы бы пропустили его (G15).
      target.accept(this);
      // НЕ спускаемся в methodName/argumentList.
      return;
    }
    // Голый вызов без target: `_sum()`, `helper(x)`. methodName может быть
    // reactive-именем (helper-метод, читающий reactive — см. G1). Проверяем
    // через staticElement: метод экземпляра этого класса → учитываем.
    final element = node.methodName.element;
    if (element is MethodElement) {
      roots.add(node.methodName.name);
    }
    // Аргументы вызова: `helper(balance)` — balance (reactive) передаётся как
    // аргумент. Чтение balance в позиции аргумента реактивно (dataflow: значение
    // вычисляется и передаётся), поэтому обходим argumentList явно. По умолчанию
    // визитор НЕ обходит их (мы не вызываем super), и reactive-аргументы терялись.
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
  }
}

/// Извлекает корневое имя из узла выражения, проверяя, что это обращение
/// к ЗНАЧЕНИЮ (полю/геттеру экземпляра), а не к типу/параметру/функции.
///
/// Принимает nullable: `target` у `PropertyAccess`/`MethodInvocation` и
/// `prefix` могут быть `null` в отдельных формах записи.
///
/// Возвращает `null` для:
/// - `null`-узла (нет target);
/// - типов (`DateTime` в `DateTime.now()` — `element` это `ClassElement`);
/// - параметров метода (`ParameterElement` — не свойство стора);
/// - импорт-префиксов (`PrefixElement`);
/// - функций/классов верхнего уровня;
/// - голого вызова (`foo()` без target → MethodInvocation.target == null).
String? _referencedRootOf(Expression? node) {
  if (node == null) return null;
  if (node is SimpleIdentifier) {
    final element = node.element;
    // Только геттеры/поля экземпляра считаются обращениями к свойствам стора.
    if (element is PropertyAccessorElement || element is FieldElement) {
      return node.name;
    }
    return null;
  }
  if (node is PrefixedIdentifier) return _referencedRootOf(node.prefix);
  if (node is PropertyAccess) return _referencedRootOf(node.target);
  if (node is MethodInvocation) return _referencedRootOf(node.target);
  return null;
}
