# signals_store_generator

Генератор кода для [`signals_store_annotation`](../signals_store_annotation).
Превращает `abstract`-класс, помеченный аннотацией [`@Store`][Store], в один
или несколько конкретных классов с реактивными (`signals`-бэкенд) полями.

## Что делает генератор

Для каждой аннотации `@Store(name: ...)` на `abstract`-классе создаётся
класс-наследник. Поля обрабатываются по двум категориям:

- **`abstract`-поля** (реактивные) — заменяются на `Signal`-бэкенд: приватное
  поле `_<field>$`, конструктор с `required`-параметром и типизированные
  геттер/сеттер, пробрасывающие значение в/из сигнала. Чтение/запись
  автоматически подписывает эффекты (signals).
- **concrete-поля** (`final X x;` или `X x;`, pass-through) — пробрасываются
  как `required super.x`-параметр конструктора без `Signal`-обёртки. Это
  стабильные ссылки (например, вложенные сторы), которые не должны быть
  реактивными на уровне корня.

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

  @override
  String get name => _name$.value;
  @override
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

## Вложенные сторы

Для построения глобального дерева состояния (как в [overmind]) один стор может
содержать другой как concrete-поле, типизированное суперклассом-описанием
вложенного стора:

```dart
@Store(name: 'SessionStore')
abstract class SessionStoreImpl {
  abstract User? currentUser;
  abstract bool isLoading;
}

@Store(name: 'AppStore')
abstract class AppStoreImpl {
  // Concrete-поле — стабильно, не реактивно на корне. Его собственные
  // abstract-поля реактивны через свои сигналы.
  final SessionStoreImpl session;

  // Реактивное поле — обёрнуто в Signal.
  abstract bool isBusy;

  AppStoreImpl({required this.session});
}
```

Генератор автоматически переписывает тип concrete-поля `SessionStoreImpl` →
`SessionStore` (имя реализации), чтобы потребитель работал с типизированным
подстором, чьи поля реактивны.

[overmind]: https://overmindjs.org

## Поведение при ошибках

- `@Store` на не-классе (например, `const value = 42;`) → ошибка кодогенерации:
  `@Store применим только к классам`.
- `@Store` на классе без полей → ошибка: `... не содержит полей. Нечего
  генерировать.`

[Store]: ../signals_store_annotation/lib/src/annotations.dart
