import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:source_gen/source_gen.dart';

import 'reactivity.dart';

/// {@template store_generator}
/// Генератор реализаций сторов для аннотации [Store].
///
/// Для каждой аннотации `@Store(name: ...)` на `abstract`-классе генерирует
/// класс-наследник. Поля обрабатываются по двум категориям:
///
/// - **`abstract`-поля** → реактивные через `Signal`: поле `<field>$` с той же
///   областью видимости, что и исходное (публичное поле → `field$`, приватное
///   `_field` → `_field$`), типизированные геттер и сеттер, пробрасывающие
///   значение в/из сигнала. Запись/чтение автоматически подписывает эффекты
///   (signals). Параметр конструктора для приватного поля публикуется под
///   stripped-именем (`_count` → `count`): Dart запрещает приватные имена у
///   named-параметров, не являющихся initializing-formal.
/// - **concrete-поля** (`final X x;` или `X x;`) → пробрасываются как обычные
///   поля: принимаются параметром конструктора и инициализируются напрямую.
///   Публичное поле → `required super.x` (требует named initializing-formal
///   `{required this.x}` в super-конструкторе). Приватное поле `_x` →
///   Dart запрещает `super._x`, поэтому передаётся через явный `super(value)`
///   в initializer-list (требует позиционного initializing-formal `this._x`;
///   именованный приватный формал подклассу недоступен). **Самодостаточные
///   concrete-поля** — с inline-инициализатором (`final int x = 5;`) или
///   non-final nullable без инициализатора (`int? d;` → Dart даёт null) — НЕ
///   пробрасываются и НЕ добавляются в конструктор: значение берётся из
///   объявления поля в суперклассе. `late`-поля игнорируются (их инициализация
///   — ответственность пользователя, в т.ч. через тело unnamed-конструктора).
///   Используются для вложенных сторов и прочих стабильных ссылок, которые НЕ
///   должны быть реактивными на уровне корня.
///
/// **Обобщённые параметры и абстрактные сторы.** Type parameters
/// аннотированного класса (`<T, R extends Result>`) переносятся на
/// сгенерированный стор: в декларации — с bounds, в `extends` — только имена.
/// При `@Store(abstract: true)` генерируется `abstract class` — базовый стор,
/// чью конкретную реализацию пишет пользователь.
///
/// На одном классе допускается **ровно одна** аннотация `@Store`; несколько
/// аннотаций вызывают ошибку кодогенерации. Поэтому `GeneratorForAnnotation`
/// видит лишь ПЕРВУЮ аннотацию каждого типа (`TypeChecker.firstAnnotationOf`),
/// но мы переопределяем [generate], чтобы построить карту impl→имя реализации
/// по всей библиотеке (для типизации вложенных сторов) и явно проверить
/// отсутствие дублирующих аннотаций.
/// {@endtemplate}
class StoreGenerator extends GeneratorForAnnotation<Store> {
  /// {@macro store_generator}
  const StoreGenerator();

  static const _storeChecker = TypeChecker.fromUrl(
    'package:signals_store_annotation/src/annotations.dart#Store',
  );

  static const _derivedChecker = TypeChecker.fromUrl(
    'package:signals_store_annotation/src/annotations.dart#DerivedStore',
  );

  @override
  Future<String> generate(LibraryReader library, BuildStep buildStep) async {
    // Карта: имя impl-класса → имя его реализации (и @Store, и @DerivedStore).
    //
    // Нужна для корректной типизации concrete-полей, ссылающихся на суперкласс
    // другого стора (`final SessionStoreImpl session;`). Тогда генератор должен
    // использовать имя КОНКРЕТНОЙ реализации (`SessionStore`), чтобы подстор
    // был полноценно типизирован своими реактивными полями.
    final implToStoreName = <String, String>{};
    // impl-имена классов с @Store(root: true) — валидные цели root-геттера
    // @DerivedStore. Заполняется в первом проходе, используется во втором.
    final rootImplNames = <String>{};
    for (final element in library.allElements) {
      if (element is! ClassElement) continue;
      final storeAnn = _storeChecker.firstAnnotationOf(element);
      if (storeAnn != null) {
        final reader = ConstantReader(storeAnn);
        implToStoreName[element.name!] = reader.read('name').stringValue;
        if (reader.peek('root')?.boolValue ?? false) {
          rootImplNames.add(element.name!);
        }
      }
      final derivedAnn = _derivedChecker.firstAnnotationOf(element);
      if (derivedAnn != null) {
        implToStoreName[element.name!] =
            ConstantReader(derivedAnn).read('name').stringValue;
      }
    }
    // implToStoreName.keys — имена классов, помеченных @Store/@DerivedStore.
    // Передаём в детектор реактивности как `storeImplNames`: concrete-поле,
    // типизированное таким impl-классом, реактивно как подстор.
    final storeImplNames = implToStoreName.keys.toSet();

    final values = <String>[];
    for (final element in library.allElements) {
      // Аннотации проверяем ДО фильтра ClassElement: @Store/@DerivedStore на
      // не-классе (top-level const, typedef, ...) → понятная ошибка, а не
      // молчаливый пропуск.
      final storeAnns = _storeChecker.annotationsOf(element);
      final derivedAnns = _derivedChecker.annotationsOf(element);
      if (storeAnns.isEmpty && derivedAnns.isEmpty) continue;

      if (element is! ClassElement) {
        final name = element.name;
        final kind = element.kind.displayName;
        final ann = storeAnns.isNotEmpty ? '@Store' : '@DerivedStore';
        throw InvalidGenerationSource(
          '$ann can only be applied to classes, but was found on $kind '
          '"$name".',
          element: element,
        );
      }

      // На одном классе допускается ровно одна аннотация — @Store ИЛИ
      // @DerivedStore. Несколько @Store, либо @Store+@DerivedStore вместе —
      // неоднозначность super-полей и single-responsibility.
      if (storeAnns.isNotEmpty && derivedAnns.isNotEmpty) {
        throw InvalidGenerationSource(
          'Class "${element.name}" is annotated with both @Store and '
          '@DerivedStore. Use exactly one annotation per class.',
          element: element,
        );
      }
      if (storeAnns.length > 1) {
        throw InvalidGenerationSource(
          'Class "${element.name}" is annotated with multiple @Store '
          'annotations (${storeAnns.length}). Only one @Store annotation is '
          'allowed per class. Move each implementation into its own class.',
          element: element,
        );
      }

      if (storeAnns.isNotEmpty) {
        final generated = await _generateForAnnotation(
          element,
          ConstantReader(storeAnns.single),
          implToStoreName,
          storeImplNames,
          rootImplNames,
        );
        if (generated != null) values.add(generated);
      } else {
        final generated = await _generateDerived(
          element,
          ConstantReader(derivedAnns.single),
          implToStoreName,
          storeImplNames,
          rootImplNames,
        );
        if (generated != null) values.add(generated);
      }
    }
    return values.isEmpty ? '' : values.join('\n\n');
  }

  Future<String?> _generateForAnnotation(
    Element element,
    ConstantReader annotation,
    Map<String, String> implToStoreName,
    Set<String> storeImplNames,
    Set<String> rootImplNames,
  ) async {
    final storeName = annotation.read('name').stringValue;
    final isAbstract = annotation.peek('abstract')?.boolValue ?? false;
    final isRoot = annotation.peek('root')?.boolValue ?? false;
    return _emitStoreClass(
      element,
      storeName,
      isAbstract,
      isRoot,
      implToStoreName,
      storeImplNames,
      rootImplNames,
      isDerived: false,
    );
  }

  /// Обрабатывает `@DerivedStore` — производный стор с доступом к корню.
  ///
  /// Валидирует контракт derived-стора (ровно один abstract root-геттер,
  /// типизированный `@Store(root: true)` impl'ом; поле-корень → ошибка), затем
  /// делегирует эмиссию общего тела в [_emitStoreClass] с `isDerived: true`,
  /// передавая имя члена-корня и его тип для эмиссии root-геттера.
  Future<String?> _generateDerived(
    Element element,
    ConstantReader annotation,
    Map<String, String> implToStoreName,
    Set<String> storeImplNames,
    Set<String> rootImplNames,
  ) async {
    // element гарантированно ClassElement — не-классы отброшены в generate()
    // с понятной ошибкой «can only be applied to classes».
    final clazz = element as ClassElement;
    if (!clazz.isAbstract) {
      throw InvalidGenerationSource(
        '@DerivedStore class "${element.name}" must be abstract.',
        element: element,
      );
    }

    // Поиск root-геттера: abstract-геттер экземпляра, тип ∈ rootImplNames.
    // Геттер — единственная допустимая форма объявления root (поле → ошибка
    // ниже): геттер резолвится при каждом обращении, derived видит актуальный
    // корень после пересоздания (см. спеку «Пересоздание корня»).
    final rootGetters = element.getters
        .where((g) => g.isAbstract && !g.isStatic && g.isOriginDeclaration)
        .toList();
    final rootTypedGetters = rootGetters.where((g) {
      final t = g.returnType;
      final el = t is InterfaceType ? t.element : null;
      return el != null && rootImplNames.contains(el.name);
    }).toList();
    if (rootTypedGetters.isEmpty) {
      throw InvalidGenerationSource(
        'Derived store "${element.name}" must declare exactly one abstract '
        'getter typed by a @Store(root: true) impl (e.g. '
        '"AppStoreImpl get root;" in an abstract class). Found '
        '${rootGetters.length} abstract getter(s), none typed by a root store.',
        element: element,
      );
    }
    if (rootTypedGetters.length > 1) {
      throw InvalidGenerationSource(
        'Derived store "${element.name}" declares multiple root-typed getters '
        '(${rootTypedGetters.map((g) => g.name).join(', ')}). Only one is '
        'allowed.',
        element: element,
      );
    }
    final rootMember = rootTypedGetters.single;
    final rootTypeStr = rootMember.returnType.getDisplayString();

    // Поле (не геттер), типизированное корневым impl → ясная ошибка.
    // Root обязан быть abstract-геттером: поле сегодня = Signal-поле стора,
    // а root — стабильная ссылка, резолвимая через StoreRootScope.
    for (final f in _allFields(element)) {
      final el = f.type is InterfaceType ? (f.type as InterfaceType).element : null;
      if (el != null && rootImplNames.contains(el.name)) {
        throw InvalidGenerationSource(
          'Field "${f.name}" in derived store "${element.name}" is typed by a '
          'root store. Declare root access as an abstract getter instead: '
          '"$rootTypeStr get root;" (no body, in the abstract class).', element: f,
        );
      }
    }

    final storeName = annotation.read('name').stringValue;
    return _emitStoreClass(
      element,
      storeName,
      /*isAbstract=*/ false,
      /*isRoot=*/ false,
      implToStoreName,
      storeImplNames,
      rootImplNames,
      isDerived: true,
      rootMemberName: rootMember.name!,
      rootTypeStr: rootTypeStr,
    );
  }

  /// Эмитит тело класса-стора (поля/геттеры/конструктор/коллизии/dispose).
  ///
  /// Общий эмиссор для `@Store` и `@DerivedStore`: всё, что не зависит от типа
  /// аннотации, живёт здесь. Производные-надстройки (root-геттер, имя root в
  /// reactive-базе) включаются флагом [isDerived] и параметрами
  /// [rootMemberName]/[rootTypeStr].
  ///
  /// [implToStoreName] / [storeImplNames] — карта impl→имя реализации и множество
  /// impl-имён (для типизации подсторов и реактивности). [rootImplNames] —
  /// множество impl-имён корневых сторов (нужно только для валидации в
  /// [_generateDerived], здесь транзитом).
  Future<String?> _emitStoreClass(
    Element element,
    String storeName,
    bool isAbstract,
    bool isRoot,
    Map<String, String> implToStoreName,
    Set<String> storeImplNames,
    Set<String> rootImplNames, {
    bool isDerived = false,
    String? rootMemberName,
    String? rootTypeStr,
  }) async {
    // Store применим только к классам.
    if (element is! ClassElement) {
      final name = element.name;
      final kind = element.kind.displayName;
      throw InvalidGenerationSource(
        '@Store can only be applied to classes, but was found on $kind '
        '"$name".',
        element: element,
      );
    }

    // --- Валидация C1: именованные конструкторы запрещены ---
    // Генератор создаёт unnamed-конструктор автоматически, и этого достаточно.
    // Именованные конструкторы не могут инициализировать abstract-поля
    // (Signal-поля), поэтому бессмысленны и потенциально сбивают с толку.
    // Unnamed-конструктор разрешён — он нужен для инициализации concrete-полей
    // через super.x.
    final namedCtors = element.constructors
        .where((c) => c.isOriginDeclaration && !c.isFactory && c.name != 'new')
        .toList();
    if (namedCtors.isNotEmpty) {
      final names = namedCtors.map((c) => c.name).join(', ');
      throw InvalidGenerationSource(
        'Class "${element.name}" declares named constructors ($names), which '
        'are not supported by @Store. The generator creates the unnamed '
        'constructor automatically, and that is sufficient — a store holds only '
        'data. Named constructors cannot initialize abstract (Signal) fields. '
        'Remove the named constructors; to initialize concrete fields, use the '
        'unnamed constructor.',
        element: element,
      );
    }

    // Единая валидация сигнатуры пользовательского dispose() — общий хелпер,
    // покрывающий и @Store, и @DerivedStore. Бросает понятную ошибку, если
    // dispose объявлен не как no-argument void method.
    _validateDisposeSignature(element);

    // Дублирующее определение реализации с тем же именем в одной библиотеке
    // дало бы compile error у потребителя — это нормально, лишних проверок не
    // нужно.

    // Разделяем поля на реактивные (abstract) и pass-through (concrete).
    final allFields = _allFields(element);
    // Computed-кандидаты считаются заранее — для derived-проверки пустоты:
    // derived без полей валиден, если есть concrete-геттеры помимо root.
    final concreteGetters = _concreteGetters(element);
    if (allFields.isEmpty && (!isDerived || concreteGetters.isEmpty)) {
      throw InvalidGenerationSource(
        'Class "${element.name}" annotated with @Store/@DerivedStore has no '
        'fields${isDerived ? ' and no concrete getters' : ''}. There is nothing '
        'to generate.',
        element: element,
      );
    }
    final reactiveFields = allFields.where((f) => f.isAbstract).toList();
    final plainFields = allFields.where((f) => !f.isAbstract).toList();

    final superName = element.name!;
    // Type parameters класса переносятся на сгенерированный стор: в декларации
    // — с bounds (`<T, R extends Result>`), в `extends` — только имена
    // (`<T, R>`), как того требует Dart.
    final declTypeParams = _typeParamsDeclaration(element);
    final superTypeArgs = _typeParamNames(element);
    final signalFieldDecls = <String>[];
    final ctorParams = <String>[];
    final ctorInits = <String>[];
    final accessors = <String>[];

    // Реактивные поля: Signal-backed геттер/сеттер.
    for (final f in reactiveFields) {
      final typeStr = _typeStringFor(f.type, implToStoreName);
      // Abstract-поле всегда имеет имя; null возможен только у синтетических
      // безымянных элементов, которых здесь быть не может.
      final fieldName = f.name!;
      // Имя ПАРАМЕТРА конструктора: для приватного поля `_count` — публичное
      // `count` (Dart запрещает приватные named-параметры, не являющиеся
      // initializing-formal). Для публичного — как есть.
      final paramName = _ctorParamName(f);
      // Имя поля-сигнала наследует область видимости исходного поля: для
      // публичного `name` → `name$`, для приватного `_count` → `_count$`.
      // Просто добавляем суффикс `$` к имени — префикс `_` приватного поля
      // сохраняется автоматически.
      final signalField = '$fieldName\$';

      // Поле-сигнал: `final Signal<String> name$;` (видимость — как у поля).
      signalFieldDecls.add('  final Signal<$typeStr> $signalField;');

      // Параметр конструктора и инициализатор сигнала. Параметр публикуется под
      // stripped-именем для приватных полей, но форвардит значение в приватный
      // signal `_field$`.
      ctorParams.add('required $typeStr $paramName');
      ctorInits.add(
        '$signalField = Signal<$typeStr>($paramName, '
        "options: SignalOptions<$typeStr>(name: '$storeName.$fieldName'))",
      );

      // Геттер и сеттер, делегирующие в сигнал.
      accessors.addAll([
        '  @override\n  $typeStr get $fieldName => $signalField.value;',
        '  @override\n  set $fieldName($typeStr value) => '
            '$signalField.value = value;',
      ]);
    }

    // Pass-through поля: принимаются конструктором и инициализируются напрямую
    // в поле суперкласса.
    //
    // - **Публичное concrete-поле** → `required super.<field>`: Dart поддерживает
    //   super-параметр, инициализирующий поле суперкласса напрямую. Требует
    //   named initializing-formal `this.<field>` в unnamed-конструкторе базового
    //   класса.
    // - **Приватное concrete-поле** `_field` → Dart ЗАПРЕЩАЕТ `super._field`
    //   (`super_formal_parameter_without_associated_named`), а также запрещает
    //   приватные named-параметры, не являющиеся initializing-formal. Поэтому
    //   приватное поле пробрасывается через ПУБЛИЧНЫЙ параметр (stripped-имя
    //   `_field` → `field`) и ЯВНЫЙ вызов `super(<value>)` в initializer-list.
    //   Для этого super-конструктор должен объявлять поле как ПОЗИЦИОННЫЙ
    //   initializing-formal `this._field` (именованный приватный формал
    //   недоступен подклассу — фундаментальное ограничение Dart).
    //
    // --- Валидация C4: super.x требует unnamed-конструктора суперкласса ---
    // Для каждого concrete-поля unnamed-конструктор суперкласса должен иметь
    // initializing-formal `this.<field>`. Для приватного поля дополнительно
    // требуется, чтобы формал был ПОЗИЦИОННЫМ (не named). Без этого — compile
    // error у потребителя. Проверяем заранее и бросаем понятную ошибку.
    final superFormals = <String, FormalParameterElement>{};
    // Позиционные формалы super-конструктора В ПОРЯДКЕ ОБЪЯВЛЕНИЯ (не по имени).
    // Критично для E4: `super(a, b)` передаёт аргументы позиционно, поэтому
    // порядок должен совпадать с порядком формалов `SImpl(this._b, this._a)`,
    // а не с алфавитной сортировкой полей. Иначе — тихая перестановка значений.
    final orderedPositionalFormals = <FormalParameterElement>[];
    for (final p in element.unnamedConstructor?.formalParameters ??
        const <FormalParameterElement>[]) {
      if (p.isInitializingFormal) {
        // Ключ — ИМЯ ПОЛЯ. В analyzer 12+ `p.name` для приватного формала
        // `this._secret` — это ПУБЛИЧНОЕ имя параметра `secret` (то, что видит
        // вызывающий), а не имя поля. Имя поля берём через
        // `FieldFormalParameterElement.field.name`. Fallback на `p.name` для
        // публичных полей, где они совпадают.
        final fieldName = p is FieldFormalParameterElement
            ? (p.field?.name ?? p.name)
            : p.name;
        if (fieldName != null) superFormals[fieldName] = p;
        if (!p.isNamed) orderedPositionalFormals.add(p);
      }
    }
    // Имя поля → публичное имя параметра конструктора (для позиционного super).
    // Заполняется при обходе plainFields (только приватные positional-поля).
    final fieldToPositionalParam = <String, String>{};
    for (final f in plainFields) {
      final fieldName = f.name!;
      // Самодостаточное concrete-поле (inline-init `final x = 5;` / `int b = 5;`,
      // или non-final nullable без инициализатора `int? d;` → Dart даёт null)
      // НЕ требует super-формала и НЕ добавляется в конструктор: значение
      // задаётся объявлением поля в суперклассе, подкласс его просто наследует.
      if (_isSelfSufficientField(f)) continue;
      final typeStr = _typeStringFor(f.type, implToStoreName);
      final formal = superFormals[fieldName];
      if (formal == null) {
        throw InvalidGenerationSource(
          'Concrete field "$fieldName" of class "${element.name}" cannot be '
          'forwarded through the super constructor: the superclass has no '
          'unnamed constructor with an initializing-formal parameter '
          '"this.$fieldName". Add an unnamed constructor with an '
          'initializing-formal (public field — named: '
          '"${element.name}({required this.$fieldName})"; private field — '
          'positional: "${element.name}(this.$fieldName)"), or make the field '
          'abstract (reactive).',
          element: f,
        );
      }
      if (_isPrivateField(f)) {
        // Приватное concrete-поле: Dart НЕ позволяет `super._private`. Требуем
        // ПОЗИЦИОННЫЙ initializing-formal в super-конструкторе (именованный
        // приватный формал подклассу недоступен).
        if (formal.isNamed) {
          throw InvalidGenerationSource(
            'Concrete field "$fieldName" of class "${element.name}" is private, '
            'and the super constructor declares it as a NAMED '
            'initializing-formal "{required this.$fieldName}". Dart does not '
            'allow a subclass to pass a private named value to the super '
            'constructor (`super_formal_parameter_without_associated_named`). '
            'Make the parameter POSITIONAL: "${element.name}(this.$fieldName);", '
            'or rename the field to public (drop the `_` prefix), or make it '
            'abstract (reactive).',
            element: f,
          );
        }
        // Публичный параметр подкласса → позиционная передача в super-конструктор.
        final paramName = _ctorParamName(f);
        ctorParams.add('required $typeStr $paramName');
        fieldToPositionalParam[fieldName] = paramName;
      } else {
        // Публичное поле: `required super.fieldName` пробрасывает значение
        // в поле суперкласса без дополнительной логики. Тип берётся из объявления
        // суперкласса, поэтому impl→implementation-переписывание здесь не нужно.
        //
        // `super.fieldName` как named-параметр требует, чтобы formal в
        // super-конструкторе был ИМЕНОВАННЫМ (`{required this.fieldName}`).
        // Позиционный formal (`this.fieldName`) не раскрывает named super-param
        // подклассу (`super_formal_parameter_without_associated_named`).
        if (!formal.isNamed) {
          throw InvalidGenerationSource(
            'Concrete field "$fieldName" of class "${element.name}" is declared '
            'in the super constructor as a POSITIONAL initializing-formal '
            '"this.$fieldName", but the generator emits '
            '`required super.$fieldName` (a named super parameter) — this is '
            'only valid for a named formal. Make the parameter NAMED: '
            '"${element.name}({required this.$fieldName});", or make the field '
            'abstract (reactive).',
            element: f,
          );
        }
        ctorParams.add('required super.$fieldName');
      }
    }

    // Формируем позиционные аргументы super(...) В ПОРЯДКЕ ОБЪЯВЛЕНИЯ формалов
    // super-конструктора (E4). Каждый позиционный формал super-конструктора,
    // соответствующий concrete-полю стора, получает значение своего параметра.
    // Позиционный формал, НЕ соответствующий полю стора (например, лишний
    // `this.extra` без поля `extra`), не может быть передан — валидируем это.
    final positionalSuperArgs = <String>[
      for (final formal in orderedPositionalFormals)
        if (fieldToPositionalParam.containsKey(formal.name))
          fieldToPositionalParam[formal.name]!
        else
          throw InvalidGenerationSource(
            'The super constructor of "${element.name}" declares a positional '
            'initializing-formal "this.${formal.name}", but the class has no '
            'concrete field named "${formal.name}". Every positional '
            'initializing-formal of the super constructor must correspond to a '
            'concrete field of the @Store class (positional super arguments '
            'cannot be skipped). Add the field "${formal.name}", or make the '
            'formal named.',
            element: element,
          ),
    ];

    // Computed-геттеры: concrete getters (с телом), которые ссылаются на
    // реактивные свойства стора. Детектор (см. reactivity.dart) определяет,
    // какие из них реактивны; для них генерируется контракт
    // `sum` (через computed) + `sum$` (Computed-поле) + `sumRaw` (сырой расчёт).
    final computedFieldDecls = <String>[];
    final computedGetters = <String>[];
    final plainGetters = <String>[];
    // concreteGetters уже собран выше (нужен для проверки пустоты derived).
    if (isDerived) {
      // Страховка: abstract root-геттер сюда и так не попадает (он abstract),
      // но если пользователь назвал concrete-геттер именем root — выкидываем,
      // иначе genератор переопределил бы его как super-делегат.
      concreteGetters.removeWhere((g) => g.name == rootMemberName);
    }
    var reactiveNames = const <String>{};
    // Имена concrete-геттеров, ставших Computed (для точечного диспоза в
    // dispose — только реальные Computed-поля, без дублирования abstract-полей
    // и без root-геттера, у которого нет Computed-поля).
    final computedGetterNames = <String>{};
    if (concreteGetters.isNotEmpty) {
      // Для derived: имя root-геттера — реактивное (его тип ∈ rootImplNames ⊂
      // storeImplNames). Геттеры, читающие `root.*`, становятся computed.
      // Передаём root в базу фикс-пойнта детектора — он не знает про геттеры,
      // только про поля.
      final extraReactive = isDerived ? {rootMemberName!} : const <String>{};
      reactiveNames = await computeReactiveGetters(
        clazz: element,
        storeImplNames: storeImplNames,
        extraReactiveNames: extraReactive,
      );
      // Имена concrete-геттеров, ставших Computed (для точечного диспоза в
      // dispose — только реальные Computed-поля, без дублирования abstract-полей
      // и без root-геттера, у которого нет Computed-поля).
      for (final g in concreteGetters) {
        final getterName = g.name!;
        final returnType = _typeStringFor(g.returnType, implToStoreName);
        final computedField = '$getterName\$';
        final rawGetter = '${getterName}Raw';
        if (reactiveNames.contains(getterName)) {
          computedGetterNames.add(getterName);
          // Computed-поле создаётся через `late final`: `super.getterName`
          // недоступен в initializer-list (Dart запрещает `super` там), а в
          // ленивом инициализаторе `this`/`super` доступны.
          computedFieldDecls.add(
            '  late final Computed<$returnType> $computedField = computed('
            '() => $rawGetter, '
            "options: ComputedOptions<$returnType>(name: '$storeName."
            "$getterName'));",
          );
          // Реактивный геттер: читает значение computed (мемоизировано).
          computedGetters.add(
            '  @override\n  $returnType get $getterName => '
            '$computedField.value;',
          );
          // Сырой расчёт: делегирует в исходную логику суперкласса, без
          // мемоизации. Escape-hatch для геттеров с не-reactive зависимостями.
          computedGetters.add(
            '  @override\n  $returnType get $rawGetter => '
            'super.$getterName;',
          );
        } else {
          // Не-реактивный getter: переопределяется как тривиальный делегат в
          // суперкласс (чтобы сгенерированный класс не стал abstract).
          plainGetters.add(
            '  @override\n  $returnType get $getterName => '
            'super.$getterName;',
          );
        }
      }
    }

    // --- Валидация коллизий генерируемых имён (A2, A3) ---
    // Генератор создаёт имена из независимых источников: abstract-поле `sum` →
    // Signal `sum$` + getter/setter `sum`; reactive getter `sum` → Computed
    // `sum$` + getter `sum` + raw `sumRaw`. Если два источника порождают одно
    // имя — compile error у потребителя (duplicate field/getter). Детектируем
    // до эмиссии и бросаем понятную ошибку.
    _checkNameCollisions(
      element,
      storeName,
      reactiveFields,
      plainFields,
      concreteGetters,
      reactiveNames,
    );

    final classKeyword = isAbstract ? 'abstract class' : 'class';
    final declParams =
        declTypeParams.isEmpty ? '' : '<${declTypeParams.join(', ')}>';
    final superArgs =
        superTypeArgs.isEmpty ? '' : '<${superTypeArgs.join(', ')}>';

    final buffer = StringBuffer()
      ..writeln('/// @Store-generated реализация стора «$storeName».')
      ..writeln('///')
      ..writeln(
        '/// Реактивные (abstract) поля [${element.name}] обёрнуты в [Signal];',
      )
      ..writeln('/// concrete-поля пробрасываются как есть.')
      ..writeln('$classKeyword $storeName$declParams extends '
          '$superName$superArgs {');

    // Конструктор: публичные concrete-поля идут как `super.x`, приватные
    // concrete-поля — через явный `super(<values>)` в initializer-list (Dart
    // запрещает `super._private`), реактивные — с явным инициализатором сигнала.
    //
    // Порядок в initializer-list: `super(...)` должен идти ПОСЛЕДНИМ (Dart требует,
    // чтобы super-вызов был последним в initializer-list — `super_invocation_not_
    // last`). Signal-инициализаторы полей текущего класса идут перед ним.
    final allInits = <String>[
      ...ctorInits,
      if (positionalSuperArgs.isNotEmpty)
        'super(${positionalSuperArgs.join(', ')})',
    ];
    // Тело конструктора: для root-стора — авторегистрация в StoreRootScope.
    // `this` доступен в теле (после initializer-list); signals уже созданы.
    // `;` ставится только когда нет тела: после `{ ... }` точка с запятой
    // незаконна (function-body не terminating-ся `;`).
    final ctorBody = isRoot ? ' { StoreRootScope.register(this); }' : '';
    // Параметры конструктора — именованные. При пустом списке эмитим `()`,
    // а не `({})` (последнее — синтаксическая ошибка). Возникает для derived-
    // сторов без собственных полей (только computed над root) и для @Store,
    // чьи concrete-поля самодостаточны.
    final paramsPart =
        ctorParams.isEmpty ? '()' : '({${ctorParams.join(', ')}})';
    buffer
      ..write('  $storeName$paramsPart')
      ..write(allInits.isEmpty
          ? (ctorBody.isEmpty ? ';' : ctorBody)
          : ' : ${allInits.join(', ')}${ctorBody.isEmpty ? ';' : ctorBody}')
      ..writeln();

    // Поля-сигналы (только реактивные).
    if (signalFieldDecls.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(signalFieldDecls.join('\n'));
    }

    // Геттеры/сеттеры реактивных полей.
    if (accessors.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(accessors.join('\n'));
    }

    // Root-геттер для derived-стора: резолвит корень при каждом обращении
    // через StoreRootScope.of<T>() — НЕ late final, поэтому свежесозданный
    // derived всегда видит актуальный корень после пересоздания (см. спеку
    // «Пересоздание корня»). of<T>() читает List/Expando (не сигналы), ложных
    // зависимостей в computed не создаёт.
    if (isDerived) {
      buffer.writeln();
      buffer.writeln('  @override');
      buffer.writeln('  $rootTypeStr get $rootMemberName => '
          'StoreRootScope.of<$rootTypeStr>();');
    }

    // Computed-поля (late final Computed<T> x$ = computed(...)).
    if (computedFieldDecls.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(computedFieldDecls.join('\n'));
    }

    // Computed-геттеры (x → computed.value, xRaw → super.x) и plain getters
    // (→ super.x) — переопределения concrete getters суперкласса.
    if (computedGetters.isNotEmpty || plainGetters.isNotEmpty) {
      buffer.writeln();
      buffer.writeln([...computedGetters, ...plainGetters].join('\n'));
    }

    // dispose() — единая механика для @Store и @DerivedStore.
    // Диспозит Signal/Computed-поля; для root-стора снимает регистрацию в
    // StoreRootScope. Если суперкласс уже объявил concrete `dispose()`,
    // генерируем @override + super.dispose(). Валидация сигнатуры
    // пользовательского dispose (non-void/параметры) — общий хелпер
    // _validateDisposeSignature, вызывается выше единым местом (покрывает и
    // @Store, и @DerivedStore).
    final disposeBuffer = StringBuffer();
    final hasConcreteDispose = element.methods.any(
      (m) => m.name == 'dispose' && m.isOriginDeclaration && !m.isStatic &&
             !m.isAbstract,
    );
    if (hasConcreteDispose) disposeBuffer.writeln('  @override');
    disposeBuffer.write('  void dispose() {');
    if (hasConcreteDispose) disposeBuffer.write(' super.dispose();');
    disposeBuffer.writeln();
    for (final f in reactiveFields) {
      disposeBuffer.writeln('    ${f.name}\$.dispose();');
    }
    // Диспозим только реальные Computed-геттеры (не весь reactiveNames, куда
    // входят abstract-поля — они диспозятся выше — и для derived имя root,
    // у которого нет Computed-поля). Раньше здесь был двойной диспоз полей.
    for (final g in computedGetterNames) {
      disposeBuffer.writeln('    $g\$.dispose();');
    }
    if (isRoot) disposeBuffer.writeln('    StoreRootScope.unregister(this);');
    disposeBuffer.writeln('  }');
    buffer
      ..writeln()
      ..write(disposeBuffer.toString());

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Валидирует сигнатуру пользовательского `dispose()`, если он объявлен в
  /// [element] как origin (не унаследованный, не static) метод.
  ///
  /// dispose обязан быть no-argument void-методом: генератор эмитит
  /// `@override void dispose() { ... super.dispose(); }`, что совместимо только
  /// с такой сигнатурой. Non-void возврат или наличие параметров → понятная
  /// ошибка кодогенерации. Общий хелпер для `@Store` и `@DerivedStore`: вызывается
  /// из [_emitStoreClass] единым местом, поэтому валидация покрывает оба типа
  /// аннотаций без дублирования.
  void _validateDisposeSignature(ClassElement element) {
    MethodElement? dispose;
    for (final m in element.methods) {
      if (m.name == 'dispose' && m.isOriginDeclaration && !m.isStatic) {
        dispose = m;
        break;
      }
    }
    if (dispose == null) return;
    final badSig = dispose.returnType is! VoidType ||
        dispose.formalParameters.isNotEmpty;
    if (badSig) {
      throw InvalidGenerationSource(
        'dispose() in "${element.name}" must be a no-argument void method.',
        element: dispose,
      );
    }
  }

  /// Детектирует коллизии генерируемых имён (баги A2, A3).
  ///
  /// Генератор создаёт имена из независимых источников:
  /// - abstract-поле `sum` → Signal `sum$`, getter/setter `sum`;
  /// - reactive getter `sum` → Computed `sum$`, getter `sum`, raw `sumRaw`;
  /// - concrete-поле `x` → `super.x` (имя не эмитится, но участвует в контракте).
  /// - приватное поле `_count` → публичный ПАРАМЕТР конструктора `count`
  ///   (stripped-имя): конфликтует с публичным полем `count`, дающим тот же
  ///   параметр `count` в том же конструкторе.
  ///
  /// Если два источника порождают одно имя (например, abstract-поле `sum` и
  /// getter `sum` оба → `sum$` и `sum`), потребитель получит compile error
  /// (duplicate field/getter). Детектируем до эмиссии и бросаем понятную ошибку.
  void _checkNameCollisions(
    ClassElement element,
    String storeName,
    List<FieldElement> reactiveFields,
    List<FieldElement> plainFields,
    List<GetterElement> concreteGetters,
    Set<String> reactiveNames,
  ) {
    // Имя → описание источника, который его породил.
    final nameToSource = <String, String>{};

    void checkName(String name, String source, Element sourceElement) {
      final existing = nameToSource[name];
      if (existing != null) {
        throw InvalidGenerationSource(
          'Name collision in "$storeName": $source and $existing both produce '
          'the same name "$name". Rename one of them (for example, a field or '
          'a getter) to avoid duplication in the generated code.',
          element: sourceElement,
        );
      }
      nameToSource[name] = source;
    }

    // Abstract-поля: signal-поле `<name>$` + getter/setter `<name>`. Для
    // приватного поля дополнительно регистрируем stripped-имя параметра
    // конструктора (`_count` → `count`): оно публично и конфликтует с любым
    // публичным полем `count`. Публичное поле отдельно не регистрируем — его
    // параметр и геттер это один контракт (имя совпадает намеренно).
    for (final f in reactiveFields) {
      final fieldName = f.name!;
      checkName(fieldName, 'abstract field "$fieldName" (getter/setter)', f);
      checkName('$fieldName\$', 'abstract field "$fieldName" (Signal field)', f);
      if (_isPrivateField(f)) {
        final paramName = _ctorParamName(f);
        checkName(paramName, 'constructor parameter "$paramName" '
            '(private field "$fieldName")', f);
      }
    }

    // Concrete-поля: имя участвует в контракте (super.x), но не эмитится как
    // поле. Всё равно проверяем на коллизию с computed-именами (геттер с тем
    // же именем породит конфликт override). Для приватного поля дополнительно —
    // stripped-имя параметра (как у abstract).
    for (final f in plainFields) {
      final fieldName = f.name!;
      checkName(fieldName, 'concrete field "$fieldName" (super parameter)', f);
      // Самодостаточное поле не создаёт параметра конструктора — stripped-имя
      // параметра для него регистрировать не нужно (нет коллизии параметра).
      if (_isPrivateField(f) && !_isSelfSufficientField(f)) {
        final paramName = _ctorParamName(f);
        checkName(paramName, 'constructor parameter "$paramName" '
            '(private field "$fieldName")', f);
      }
    }

    // Concrete-геттеры: getter `<name>`; для reactive — Computed `<name>$` и
    // raw-геттер `<name>Raw`.
    for (final g in concreteGetters) {
      final getterName = g.name!;
      if (reactiveNames.contains(getterName)) {
        checkName('$getterName\$', 'computed getter "$getterName" (Computed field)', g);
        checkName('${getterName}Raw', 'computed getter "$getterName" (raw getter)', g);
      }
      checkName(getterName, 'getter "$getterName"', g);
    }
  }

  /// Все concrete-геттеры класса (геттеры с телом — не abstract, не static,
  /// не synthetic).
  ///
  /// Это кандидаты на computed: детектор `computeReactiveGetters` определяет,
  /// какие из них реактивны (ссылаются на reactive-поля/подсторы/signals).
  /// Реактивные → `Computed`; прочие → тривиально переопределяются как
  /// `super.x` (чтобы сгенерированный класс не стал abstract).
  List<GetterElement> _concreteGetters(ClassElement clazz) {
    return clazz.getters
        .where((g) => !g.isAbstract && !g.isStatic && g.isOriginDeclaration)
        .toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  }

  /// Все поля класса-описания: и abstract (реактивные), и concrete
  /// (pass-through).
  ///
  /// `abstract String name;` даёт [FieldElement] с `isAbstract == true`.
  /// `final SessionStore session;` или `int x;` — concrete.
  ///
  /// Исключаются поля, не являющиеся состоянием экземпляра стора:
  /// - синтетические (неявные геттеры/сеттеры, унаследованные от Object);
  /// - `static`-поля — константы/счётчики уровня класса, а не экземпляра:
  ///   они не должны становиться параметрами конструктора;
  /// - `late`-поля — инициализируются вручную позже, у суперкласса нет
  ///   соответствующего параметра конструктора, поэтому `super.x` невозможен.
  ///
  /// Сортируем по имени для детерминированного вывода.
  List<FieldElement> _allFields(ClassElement clazz) {
    return clazz.fields
        .where((f) => f.isOriginDeclaration && !f.isStatic && !f.isLate)
        .toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  }

  /// Строковое представление type parameters класса для ДЕКЛАРАЦИИ
  /// сгенерированного стора — с bounds.
  ///
  /// Для `class Foo<T, R extends Result>` возвращает `['T', 'R extends Result']`.
  /// bounds рендерятся через [DartType.getDisplayString], что сохраняет
  /// nullable-суффикс и вложенные обобщения.
  List<String> _typeParamsDeclaration(ClassElement clazz) {
    return [
      for (final p in clazz.typeParameters)
        p.bound == null
            ? p.name!
            : '${p.name} extends ${p.bound!.getDisplayString()}',
    ];
  }

  /// Имена type parameters класса (без bounds) — для подстановки в `extends`.
  ///
  /// Для `class Foo<T, R extends Result>` возвращает `['T', 'R']`: суперкласс
  /// конкретизируется теми же параметрами, что объявлены у наследника.
  List<String> _typeParamNames(ClassElement clazz) {
    return [for (final p in clazz.typeParameters) p.name!];
  }

  /// Строковое представление типа поля для кодогенерации.
  ///
  /// Если тип поля — суперкласс другого стора в этой же библиотеке
  /// (`SessionStoreImpl`, помеченный `@Store(name: 'SessionStore')`),
  /// возвращает имя КОНКРЕТНОЙ реализации (`SessionStore`). Это нужно как для
  /// реактивных, так и для concrete-полей: потребитель должен видеть
  /// типизированный подстор.
  ///
  /// Type-аргументы сохраняются и обрабатываются рекурсивно: для
  /// `BoxImpl<int>` (где `BoxImpl` — стор) возвращается `Box<int>`; для
  /// `Map<String, InnerStoreImpl>` внутренний impl-тип тоже rewrite'ится на
  /// имя реализации. Если type-аргумент сам не является стором, он рендерится
  /// через `getDisplayString()`.
  ///
  /// Для всех прочих типов (включая `Map<String, Todo>`, `int?`, импортируемые
  /// классы) возвращает `getDisplayString()` как есть. Суффикс nullable-ности
  /// (`?`) сохраняется.
  String _typeStringFor(DartType type, Map<String, String> implToStoreName) {
    final element = type.element;
    if (element is ClassElement) {
      final storeName = implToStoreName[element.name];
      if (storeName != null) {
        final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
        // type-аргументы generic-стора (`BoxImpl<int>` → `Box<int>`).
        // Рекурсивно rewrite'им каждый аргумент, чтобы вложенные impl-типы тоже
        // получили имя реализации. Для не-generic стора (`InnerStoreImpl`)
        // typeArguments пуст → возвращаем просто имя (как раньше).
        final args = type is InterfaceType ? type.typeArguments : const <DartType>[];
        final base = args.isEmpty
            ? storeName
            : '$storeName<${[
                for (final a in args) _typeStringFor(a, implToStoreName),
              ].join(', ')}>';
        return nullable ? '$base?' : base;
      }
    }
    return type.getDisplayString();
  }

  /// Имя параметра конструктора, который принимает значение поля.
  ///
  /// Для публичного поля — как есть. Для приватного `_count` — публичное `count`
  /// (без префикса `_`): Dart запрещает приватные имена у named-параметров,
  /// не являющихся initializing-formal (`private_named_non_field_parameter`), и
  /// запрещает `super._private` даже в той же библиотеке. Поэтому сгенерированный
  /// конструктор принимает ЗДЕСЬ публичное имя и форвардит значение в приватный
  /// signal/геттер/сеттер (или позиционный super-конструктор).
  ///
  /// Signal-поле, геттер и сеттер при этом остаются приватными (`_count$`, `_count`)
  /// — приватность исходного поля сохраняется в контракте стора.
  ///
  /// Снимаются ВСЕ ведущие подчёркивания (`__count` → `count`, не `_count`) —
  /// иначе оставшееся приватное имя снова нарушит `private_named_non_field_parameter`.
  /// Результат обязан быть валидным публичным идентификатором: непустым и не
  /// начинающимся с `_`. Поле `_` или `__` (только подчёркивания) — дегенеративное
  /// имя без публичной формы → понятная ошибка кодогенерации.
  String _ctorParamName(FieldElement f) {
    final name = f.name!;
    final stripped = name.replaceFirst(RegExp(r'^_+'), '');
    if (stripped.isEmpty) {
      throw InvalidGenerationSource(
        'Field "$name" consists only of underscores and has no public '
        'constructor-parameter form. Rename it to a field with a non-underscore '
        'suffix (e.g. "_count").',
        element: f,
      );
    }
    return stripped;
  }

  /// Приватное ли поле (имя начинается с `_` — library-private в Dart).
  bool _isPrivateField(FieldElement f) => f.name!.startsWith('_');

  /// Самодостаточное concrete-поле: не требует параметра конструктора и не
  /// пробрасывается через super-формал — его значение задаётся в объявлении
  /// поля суперкласса, а подкласс его просто наследует.
  ///
  /// Два случая (вариант 2):
  /// - **inline-инициализатор**: `final int x = 5;`, `int b = 5;`,
  ///   `final int? c = null;` — значение задано явно.
  /// - **non-final nullable без инициализатора**: `int? d;` — Dart
  ///   автоматически инициализирует в `null`, поле компилируется и без ctor.
  ///
  /// Исключения: `final` без инициализатора (`final int? e;`) — требует
  /// установки (Dart не даёт default), поэтому НЕ самодостаточно и валидируется
  /// C4. `late`/`static` исключены из `_allFields` заранее, здесь не встречаются.
  bool _isSelfSufficientField(FieldElement f) {
    if (f.hasInitializer) return true;
    final isNullable =
        f.type.nullabilitySuffix == NullabilitySuffix.question;
    return isNullable && !f.isFinal;
  }
}
