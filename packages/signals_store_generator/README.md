# signals_store_generator

Генератор кода для [`signals_store_annotation`](../signals_store_annotation).
Превращает `abstract`-класс, помеченный аннотацией [`@Store`][Store], в
конкретный класс с реактивными (`signals`-бэкенд) полями и вычисляемыми
(computed) геттерами.

## Что делает генератор

Для аннотации `@Store(name: ...)` на `abstract`-классе создаётся единственный
класс-наследник. Члены класса обрабатываются по трём категориям:

- **`abstract`-поля** (реактивные) — заменяются на `Signal`-бэкенд: поле
  `<field>$` с той же областью видимости, что и исходное (публичное поле →
  `field$`, приватное `_field` → `_field$`), конструктор с `required`-параметром
  и типизированные геттер/сеттер, пробрасывающие значение в/из сигнала.
  Чтение/запись автоматически подписывает эффекты (signals).
- **concrete-поля** (`final X x;` или `X x;`, pass-through) — пробрасываются
  как `required super.x`-параметр конструктора без `Signal`-обёртки. Это
  стабильные ссылки (например, вложенные сторы), которые не должны быть
  реактивными на уровне корня.
- **concrete-геттеры** (с телом) — если тело ссылается на реактивное состояние
  (поля, подсторы, `Signal`-коллекции, другие reactive-геттеры, или чтение
  `.value` на любом `Signal`-типе), геттер становится `Computed`-бэкенд: ленивое
  мемоизированное значение, автоматически пересчитываемое при изменении
  зависимостей. Геттеры без реактивных ссылок остаются обычными.

```dart
@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int count;
}
```

превращается (после `build_runner`) в:

```dart
class CounterStore extends CounterImpl {
  CounterStore({required int count})
      : count$ = Signal<int>(
          count,
          options: SignalOptions<int>(name: 'CounterStore.count'),
        );

  final Signal<int> count$;

  @override
  int get count => count$.value;
  @override
  set count(int value) => count$.value = value;
}
```

### Computed-геттеры

Concrete-геттер (геттер с телом), который читает реактивное состояние,
автоматически становится вычисляемым (`Computed`):

```dart
@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int a;
  abstract int b;

  int get sum => a + b;            // читает reactive a, b → Computed
  int get hundred => 100;          // нет reactive-ссылок → остаётся обычным
}
```

генерирует для `sum`:

```dart
class CounterStore extends CounterImpl {
  // ... signal-поля a$, b$ ...

  late final Computed<int> sum$ = computed(
    () => sumRaw,
    options: ComputedOptions<int>(name: 'CounterStore.sum'),
  );

  @override
  int get sum => sum$.value;        // мемоизировано, реактивно
  @override
  int get sumRaw => super.sum;      // сырой пересчёт (escape-hatch)
}
```

- `sum` — реактивный: читает кэш `Computed`, пересчитывается при изменении
  `a`/`b`, подписывает эффекты (`Watch`, `effect`).
- `sum$` — сам объект `Computed` (для подписки, `.recompute()`).
- `sumRaw` — сырой пересчёт без мемоизации (escape-hatch для геттеров с
  не-reactive зависимостями вроде `DateTime.now()`).

Реактивность определяется по типам, а не по именам: геттер считается reactive,
если его тело упоминает abstract-поле, подстор (`@Store` impl), `Signal`-коллекцию
(`MapSignal`, `ListSignal`, ...), класс с `Signal`-полями (каскад любой глубины),
другой reactive-геттер/метод, или читает `.value`/`.length`/`[]`/`.where()` на
любом `Signal`-типе (включая глобальные signal-переменные). Чистые мутации
(`sig.value = x` без чтения) и untracked-доступы (`.peek()`) реактивностью не
считаются.

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
   единственной аннотацией `@Store`:

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
- Несколько аннотаций `@Store` на одном классе → ошибка: `... помечен
  несколькими аннотациями @Store`. Разнесите разные реализации по отдельным
  классам.

[Store]: ../signals_store_annotation/lib/src/annotations.dart
