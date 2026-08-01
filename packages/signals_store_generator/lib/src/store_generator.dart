import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:source_gen/source_gen.dart';

/// {@template store_generator}
/// Генератор реализаций сторов для аннотации [Store].
///
/// Для каждой аннотации `@Store(name: ...)` на `abstract`-классе генерирует
/// конкретный класс-наследник, в котором каждое `abstract`-поле (геттер+сеттер)
/// заменяется на `Signal`-бэкенд: приватное поле `_<field>$`, геттер и сеттер,
/// пробрасывающие значение в/из сигнала.
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
    final values = <String>[];
    for (final element in library.allElements) {
      // Берём все аннотации @Store элемента, а не только первую.
      for (final annotation in _storeChecker.annotationsOf(element)) {
        final generated = _generateForAnnotation(
          element,
          ConstantReader(annotation),
        );
        if (generated != null) values.add(generated);
      }
    }
    return values.isEmpty ? '' : values.join('\n\n');
  }

  String? _generateForAnnotation(Element element, ConstantReader annotation) {
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

    final fields = _abstractFields(element);
    if (fields.isEmpty) {
      throw InvalidGenerationSource(
        'Класс «${element.name}», помеченный @Store, не содержит '
        'abstract-полей. Нечего генерировать.',
        element: element,
      );
    }

    final superName = element.name!;
    final fieldDecls = <String>[];
    final ctorParams = <String>[];
    final ctorInits = <String>[];
    final accessors = <String>[];

    for (final f in fields) {
      final typeStr = f.type.getDisplayString();
      // Abstract-поле всегда имеет имя; null возможен только у синтетических
      // безымянных элементов, которых здесь быть не может.
      final fieldName = f.name!;
      final signalField = '_$fieldName\$';

      // Поле-сигнал: `final Signal<String> _name$;`
      fieldDecls.add('  final Signal<$typeStr> $signalField;');

      // Параметр конструктора и инициализатор сигнала.
      ctorParams.add('required $typeStr $fieldName');
      ctorInits.add(
        '$signalField = Signal<$typeStr>($fieldName, '
        "options: SignalOptions<$typeStr>(name: '$storeName.$fieldName'))",
      );

      // Геттер и сеттер, делегирующие в сигнал.
      accessors.addAll([
        '  $typeStr get $fieldName => $signalField.value;',
        '  set $fieldName($typeStr value) => $signalField.value = value;',
      ]);
    }

    final buffer = StringBuffer()
      ..writeln('/// @Store-generated реализация стора «$storeName».')
      ..writeln('///')
      ..writeln('/// Каждое поле [${element.name}] реактивно через [Signal].')
      ..writeln('class $storeName extends $superName {');

    // Конструктор.
    buffer
      ..write('  $storeName({${ctorParams.join(', ')}})')
      ..write(' : ${ctorInits.join(', ')};')
      ..writeln();

    // Поля-сигналы.
    buffer.writeln(fieldDecls.join('\n'));
    buffer.writeln();

    // Геттеры/сеттеры.
    buffer.writeln(accessors.join('\n'));

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Abstract-поля класса — кандидаты на кодогенерацию.
  ///
  /// `abstract String name;` даёт [FieldElement] с `isAbstract == true`:
  /// его геттер и сеттер abstract и не имеют тела. Поля с конкретной
  /// реализацией (`final x = 1;`) игнорируются.
  ///
  /// Сортируем по имени для детерминированного вывода.
  List<FieldElement> _abstractFields(ClassElement clazz) {
    final fields = clazz.fields.where((f) => f.isAbstract).toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return fields;
  }
}
