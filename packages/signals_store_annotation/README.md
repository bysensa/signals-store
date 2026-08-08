# signals_store_annotation

Annotations for the reactive stores of [`signals_store`](../signals_store) and
their [code generator](../signals_store_generator).

## Installation

```yaml
dependencies:
  signals_store_annotation:
    path: ../../packages/signals_store_annotation  # or git/url
```

## Usage

The [`@Store`][Store] annotation marks an `abstract` class as a store
description: its `abstract` fields (getter + setter) are turned by the code
generator into reactive `Signal` backends.

```dart
import 'package:signals_store_annotation/signals_store_annotation.dart';

@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int count;
  abstract String name;
}
```

Exactly one `@Store` annotation is allowed per class; multiple annotations
raise a codegen error.

### Root stores: `@Store(root: true)`

Mark a store as the **root** of a store tree. The generated constructor
auto-registers the instance in [`StoreRootScope`](../signals_store) (and its
`dispose()` unregisters it), so any code can resolve it by type — no manual
wiring:

```dart
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  final SessionStoreImpl session;
  AppStoreImpl({required this.session});
}
```

### Derived stores: `@DerivedStore`

A derived store is a **full store with access to the root** — its own reactive
state plus computed getters that read the root. Declare the root as a bodyless
getter (no `abstract` keyword — Dart forbids it on members):

```dart
@DerivedStore(name: 'TodoDetailsStore')
abstract class TodoDetailsStoreImpl {
  AppStoreImpl get root;                       // generated via StoreRootScope.of
  abstract String todoId;                      // own Signal-backed state
  Todo? get todo => root.projects.todos[todoId]; // computed (reads root)
}
```

The generator emits the root getter as `get root => StoreRootScope.of<
AppStoreImpl>()` — a getter (not a cached field), so a derived store always
sees the **current** root even after the root is re-created. Derived stores
are created on demand anywhere (e.g. as screen state) and disposed via the
generated `dispose()`.

Exactly one `@DerivedStore` per class; `@Store` and `@DerivedStore` on the
same class are both rejected.

## Related packages

- [`signals_store_generator`](../signals_store_generator) — the code generator
  that produces store implementations.
- [`signals_store`](../signals_store) — the runtime `ReactiveStore` (an
  alternative to codegen based on `noSuchMethod`).

[Store]: lib/src/annotations.dart
