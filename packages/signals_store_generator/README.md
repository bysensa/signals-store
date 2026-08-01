# signals_store_generator

Генератор кода для [`signals_store_annotation`](../signals_store_annotation).
Превращает `abstract`-класс, помеченный аннотацией [`@Store`][Store], в один
или несколько конкретных классов с реактивными (`signals`-бэкенд) полями.

## Что делает генератор

Для каждой аннотации `@Store(name: ...)` на `abstract`-классе создаётся
класс-наследник, где каждое `abstract`-поле (геттер + сеттер) заменяется на
`Signal`-бэкенд: приватное поле `_<field>$`, конструктор с `required`-параметром
и типизированные геттер/сеттер, пробрасывающие значение в/из сигнала.

```dart
@Store(name: 'FirstSomeStore')
@Store(name: 'SecondSomeStore')
abstract class SomeStoreImpl {
  abstract String name;
}
```

превращается (после `build_runner`) в:

```dart
class FirstSomeStore extends SomeStoreImpl {
  FirstSomeStore({required String name})
      : _name$ = Signal<String>(
          name,
          options: SignalOptions<String>(name: 'FirstSomeStore.name'),
        );

  final Signal<String> _name$;

  String get name => _name$.value;
  set name(String value) => _name$.value = value;
}

// ... и аналогично SecondSomeStore
```

## Установка

```yaml
dependencies:
  signals: ^7.0.0
  signals_store_annotation:
    path: ../../packages/signals_store_annotation   # или git/url

dev_dependencies:
  signals_store_generator:
    path: ../../packages/signals_store_generator
  build_runner: ^2.4.0
```

## Использование

1. Опишите стор как `abstract`-класс с `abstract`-полями и пометьте его
   аннотацией `@Store` (одной или несколькими):

   ```dart
   import 'package:signals/signals.dart';
   import 'package:signals_store_annotation/signals_store_annotation.dart';

   part 'my_store.g.dart';

   @Store(name: 'CounterStore')
   abstract class CounterImpl {
     abstract int count;
     abstract String name;
   }
   ```

2. Запустите генератор:

   ```sh
   dart run build_runner build
   # для Flutter-проектов: flutter pub run build_runner build
   ```

3. Используйте сгенерированный класс — поля реактивны через `signals`:

   ```dart
   final store = CounterStore(count: 0, name: 'demo');

   effect(() => print('count = ${store.count}'));
   store.count = 5; // печатает "count = 5"
   ```

## Типы полей

Поддерживаются любые типы полей, разрешаемые анализатором, включая
nullable (`int?`) и дженерики (`List<String>`). Тип сохраняется в сигнале как
есть — статическая типизация полей сохраняется.

## Поведение при ошибках

- `@Store` на не-классе (например, `const value = 42;`) → ошибка кодогенерации:
  `@Store применим только к классам`.
- `@Store` на классе без `abstract`-полей → ошибка: `... не содержит
  abstract-полей. Нечего генерировать.`

[Store]: ../signals_store_annotation/lib/src/annotations.dart
