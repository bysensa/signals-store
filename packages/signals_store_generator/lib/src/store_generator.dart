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
/// конкретный класс-наследник. Поля обрабатываются по двум категориям:
///
/// - **`abstract`-поля** → реактивные через `Signal`: приватное поле
///   `_<field>$`, типизированные геттер и сеттер, пробрасывающие значение
///   в/из сигнала. Запись/чтение автоматически подписывает эффекты (signals).
/// - **concrete-поля** (`final X x;` или `X x;`) → пробрасываются как обычные
///   поля: принимаются параметром конструктора и инициализируются напрямую.
///   Используются для вложенных сторов и прочих стабильных ссылок, которые
///   НЕ должны быть реактивными на уровне корня.
///
/// Несколько аннотаций `@Store` на одном классе порождают несколько реализаций.
/// По умолчанию `GeneratorForAnnotation` видит лишь ПЕРВУЮ аннотацию каждого
/// типа (`TypeChecker.firstAnnotationOf`), поэтому мы переопределяем [generate]
/// и обходим ВСЕ аннотации `@Store` у каждого элемента.
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
    //
    // Если на impl-классе несколько `@Store`-аннотаций — берём первую
    // (однозначный выбор по умолчанию).
    final implToStoreName = <String, String>{};
    for (final element in library.allElements) {
      if (element is! ClassElement) continue;
      final annotations = _storeChecker.annotationsOf(element);
      if (annotations.isEmpty) continue;
      final firstName =
          ConstantReader(annotations.first).read('name').stringValue;
      implToStoreName[element.name!] = firstName;
    }

    final values = <String>[];
    for (final element in library.allElements) {
      // Берём все аннотации @Store элемента, а не только первую.
      for (final annotation in _storeChecker.annotationsOf(element)) {
        final generated = _generateForAnnotation(
          element,
          ConstantReader(annotation),
          implToStoreName,
        );
        if (generated != null) values.add(generated);
      }
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

    final buffer = StringBuffer()
      ..writeln('/// @Store-generated реализация стора «$storeName».')
      ..writeln('///')
      ..writeln(
        '/// Реактивные (abstract) поля [${element.name}] обёрнуты в [Signal];',
      )
      ..writeln('/// concrete-поля пробрасываются как есть.')
      ..writeln('class $storeName extends $superName {');

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
  /// (pass-through), кроме синтетических (унаследованных от Object).
  ///
  /// `abstract String name;` даёт [FieldElement] с `isAbstract == true`.
  /// `final SessionStore session;` или `int x;` — concrete.
  ///
  /// Сортируем по имени для детерминированного вывода.
  List<FieldElement> _allFields(ClassElement clazz) {
    return clazz.fields.where((f) => !f.isSynthetic).toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  }

  /// Строковое представление типа поля для кодогенерации.
  ///
  /// Если тип поля — суперкласс другого стора в этой же библиотеке
  /// (`SessionStoreImpl`, помеченный `@Store(name: 'SessionStore')`),
  /// возвращает имя КОНКРЕТНОЙ реализации (`SessionStore`). Это нужно как для
  /// реактивных, так и для concrete-полей: потребитель должен видеть
  /// типизированный подстор.
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
        return nullable ? '$storeName?' : storeName;
      }
    }
    return type.getDisplayString();
  }
}
