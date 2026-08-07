# signals_store_generator

Code generator for [`signals_store_annotation`](../signals_store_annotation).
Turns an `abstract` class annotated with [`@Store`][Store] into a concrete class
with reactive (`signals`-backed) fields and computed (derived) getters.

## What the generator does

For a `@Store(name: ...)` annotation on an `abstract` class it creates a single
subclass. Class members are processed in three categories:

- **`abstract` fields** (reactive) — replaced with a `Signal` backend: a
  `<field>$` field with the same visibility as the source (public field →
  `field$`, private `_field` → `_field$`), plus typed getter and setter that
  forward the value to/from the signal. The constructor parameter for a private
  field is published under its public (stripped) name — `_field` → `field`:
  Dart forbids private names on named parameters that are not
  initializing-formals. Reads/writes automatically subscribe effects (signals).
- **concrete fields** (`final X x;` or `X x;`, pass-through) — forwarded without
  a `Signal` wrapper. A public field → `required super.x` (requires a named
  initializing-formal `{required this.x}` in the super constructor). A private
  field `_x` is forwarded via an explicit `super(value)` in the initializer list
  (requires a positional initializing-formal `this._x`; a named private formal
  is not accessible to the subclass — a Dart limitation). These are stable
  references (for example, nested stores) that should not be reactive at the
  root level. **Self-sufficient concrete fields** are not forwarded at all and
  are not added to the constructor: a field with an inline initializer
  (`final int x = 5;`, `int b = 5;`) or a non-final nullable field without an
  initializer (`int? d;`, which Dart defaults to `null`) takes its value from
  the field declaration, and the generated subclass simply inherits it. A
  `late` field initialized in the body of the user-declared unnamed constructor
  is likewise preserved (the subclass calls `super()` implicitly, so the
  constructor body runs); initializing `late` fields is the user's
  responsibility, as for any `late`.
- **concrete getters** (with a body) — if the body references reactive state
  (fields, substores, `Signal` collections, other reactive getters, or reads
  `.value` on any `Signal` type), the getter becomes a `Computed` backend: a
  lazily memoized value that recomputes automatically when its dependencies
  change. Getters with no reactive references remain plain.

```dart
@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int count;
}
```

turns into (after `build_runner`):

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

### Computed getters

A concrete getter (a getter with a body) that reads reactive state
automatically becomes computed (`Computed`):

```dart
@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int a;
  abstract int b;

  int get sum => a + b;            // reads reactive a, b → Computed
  int get hundred => 100;          // no reactive refs → stays plain
}
```

generates for `sum`:

```dart
class CounterStore extends CounterImpl {
  // ... signal fields a$, b$ ...

  late final Computed<int> sum$ = computed(
    () => sumRaw,
    options: ComputedOptions<int>(name: 'CounterStore.sum'),
  );

  @override
  int get sum => sum$.value;        // memoized, reactive
  @override
  int get sumRaw => super.sum;      // raw recomputation (escape-hatch)
}
```

- `sum` — reactive: reads the `Computed` cache, recomputes when `a`/`b` change,
  subscribes effects (`Watch`, `effect`).
- `sum$` — the `Computed` object itself (for subscription, `.recompute()`).
- `sumRaw` — raw recomputation without memoization (escape-hatch for getters
  with non-reactive dependencies like `DateTime.now()`).

Reactivity is determined by types, not names: a getter is considered reactive if
its body references an abstract field, a substore (`@Store` impl), a `Signal`
collection (`MapSignal`, `ListSignal`, ...), a class with `Signal` fields
(cascade of any depth), another reactive getter/method, or reads
`.value`/`.length`/`[]`/`.where()` on any `Signal` type (including global signal
variables). Pure mutations (`sig.value = x` without a read) and untracked
accesses (`.peek()`) do not count as reactive.

## Installation

```yaml
dependencies:
  signals: ^7.0.0
  signals_store_annotation:
    path: ../../packages/signals_store_annotation   # or git/url

dev_dependencies:
  signals_store_generator:
    path: ../../packages/signals_store_generator
  build_runner: ^2.4.0
```

## Usage

1. Describe the store as an `abstract` class with `abstract` fields and annotate
   it with a single `@Store` annotation:

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

2. Run the generator:

   ```sh
   dart run build_runner build
   # for Flutter projects: flutter pub run build_runner build
   ```

3. Use the generated class — fields are reactive via `signals`:

   ```dart
   final store = CounterStore(count: 0, name: 'demo');

   effect(() => print('count = ${store.count}'));
   store.count = 5; // prints "count = 5"
   ```

## Field types

Any field type resolvable by the analyzer is supported, including nullable
(`int?`) and generics (`List<String>`). The type is preserved in the signal as
is — static typing of fields is retained.

## Nested stores

To build a global state tree (like [overmind]) one store may contain another as a
concrete field typed by the description superclass of the nested store:

```dart
@Store(name: 'SessionStore')
abstract class SessionStoreImpl {
  abstract User? currentUser;
  abstract bool isLoading;
}

@Store(name: 'AppStore')
abstract class AppStoreImpl {
  // Concrete field — stable, not reactive at the root. Its own abstract fields
  // are reactive through their own signals.
  final SessionStoreImpl session;

  // Reactive field — wrapped in a Signal.
  abstract bool isBusy;

  AppStoreImpl({required this.session});
}
```

The generator automatically rewrites the concrete field type
`SessionStoreImpl` → `SessionStore` (the implementation name), so the consumer
works with a typed substore whose fields are reactive.

[overmind]: https://overmindjs.org

## Error behavior

- `@Store` on a non-class (for example, `const value = 42;`) → codegen error:
  ``@Store can only be applied to classes``.
- `@Store` on a class with no fields → error: ``... has no fields. There is
  nothing to generate.``
- Multiple `@Store` annotations on one class → error: ``... is annotated with
  multiple @Store annotations``. Move each implementation into its own class.

[Store]: ../signals_store_annotation/lib/src/annotations.dart
