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

## Related packages

- [`signals_store_generator`](../signals_store_generator) — the code generator
  that produces store implementations.
- [`signals_store`](../signals_store) — the runtime `ReactiveStore` (an
  alternative to codegen based on `noSuchMethod`).

[Store]: lib/src/annotations.dart
