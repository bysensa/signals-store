import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:source_gen/source_gen.dart';

/// {@template store_generator}
/// Генератор реализаций сторов для аннотации [Store].
///
/// Для каждой аннотации `@Store(name: ...)` на `abstract`-классе генерирует
/// класс-наследник. Поля обрабатываются по двум категориям:
///
/// - **`abstract`-поля** → реактивные через `Signal`: приватное поле
///   `_<field>$`, типизированные геттер и сеттер, пробрасывающие значение
///   в/из сигнала. Запись/чтение автоматически подписывает эффекты (signals).
/// - **concrete-поля** (`final X x;` или `X x;`) → пробрасываются как обычные
///   поля: принимаются параметром конструктора и инициализируются напрямую.
///   Используются для вложенных сторов и прочих стабильных ссылок, которые
///   НЕ должны быть реактивными на уровне корня.
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

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    // Карта: имя impl-класса → имя его @Store-реализации.
    //
    // Нужна для корректной типизации concrete-полей, ссылающихся на суперкласс
    // другого стора (`final SessionStoreImpl session;`). Тогда генератор должен
    // использовать имя КОНКРЕТНОЙ реализации (`SessionStore`), чтобы подстор
    // был полноценно типизирован своими реактивными полями.
    final implToStoreName = <String, String>{};
    for (final element in library.allElements) {
      if (element is! ClassElement) continue;
      final annotations = _storeChecker.annotationsOf(element);
      if (annotations.isEmpty) continue;
      implToStoreName[element.name!] =
          ConstantReader(annotations.first).read('name').stringValue;
    }

    final values = <String>[];
    for (final element in library.allElements) {
      final annotations = _storeChecker.annotationsOf(element);
      if (annotations.isEmpty) continue;
      // На одном классе допускается ровно одна аннотация `@Store` — несколько
      // реализаций на одном описании запрещены (неоднозначность super-полей и
      // single-responsibility).
      if (annotations.length > 1) {
        final name = element.name;
        throw InvalidGenerationSource(
          'Класс «$name» помечен несколькими аннотациями @Store '
          '(${annotations.length}). Допускается только одна аннотация @Store '
          'на класс. Разнесите разные реализации по отдельным классам.',
          element: element,
        );
      }
      final generated = _generateForAnnotation(
        element,
        ConstantReader(annotations.single),
        implToStoreName,
      );
      if (generated != null) values.add(generated);
    }
    return values.isEmpty ? '' : values.join('\n\n');
  }

  String? _generateForAnnotation(
    Element element,
    ConstantReader annotation,
    Map<String, String> implToStoreName,
  ) {
    // Store применим только к классам.
    if (element is! ClassElement) {
      final name = element.name;
      final kind = element.kind.displayName;
      throw InvalidGenerationSource(
        '@Store применим только к классам, но найден $kind «$name».',
        element: element,
      );
    }

    final storeName = annotation.read('name').stringValue;
    // `abstract: true` → генерируем `abstract class` (например, обобщённый
    // базовый стор, чью конкретную реализацию пишет пользователь). По умолчанию
    // `false` — конкретный класс.
    final isAbstract = annotation.peek('abstract')?.boolValue ?? false;

    // Дублирующее определение реализации с тем же именем в одной библиотеке
    // дало бы compile error у потребителя — это нормально, лишних проверок не
    // нужно.

    // Разделяем поля на реактивные (abstract) и pass-through (concrete).
    final allFields = _allFields(element);
    if (allFields.isEmpty) {
      throw InvalidGenerationSource(
        'Класс «${element.name}», помеченный @Store, не содержит полей. '
        'Нечего генерировать.',
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
      final signalField = '_$fieldName\$';

      // Поле-сигнал: `final Signal<String> _name$;`
      signalFieldDecls.add('  final Signal<$typeStr> $signalField;');

      // Параметр конструктора и инициализатор сигнала.
      ctorParams.add('required $typeStr $fieldName');
      ctorInits.add(
        '$signalField = Signal<$typeStr>($fieldName, '
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
    // в поле суперкласса (через `super.<field>` если возможно, иначе через
    // super-конструктор). Здесь используем `super.field` — Dart поддерживает
    // initializing-formal/super-параметр, который инициализирует поле
    // суперкласса напрямую.
    for (final f in plainFields) {
      final fieldName = f.name!;
      // super-параметр: `required super.fieldName` пробрасывает значение
      // в поле суперкласса без дополнительной логики. Тип берётся из объявления
      // суперкласса, поэтому impl→implementation-переписывание здесь не нужно.
      ctorParams.add('required super.$fieldName');
    }

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

    // Конструктор: super-параметры (concrete) идут как `super.x`,
    // реактивные — с явным инициализатором сигнала.
    buffer
      ..write('  $storeName({${ctorParams.join(', ')}})')
      ..write(ctorInits.isEmpty ? ';' : ' : ${ctorInits.join(', ')};')
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

    buffer.writeln('}');

    return buffer.toString();
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
        .where((f) => !f.isSynthetic && !f.isStatic && !f.isLate)
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
}
