# signals_store

A reactive store built on the [`signals`](https://pub.dev/packages/signals)
package v7. Turns a class's `abstract` fields into reactive signals by
intercepting `noSuchMethod` — no boilerplate, with full static typing.

## Installation

```yaml
dependencies:
  signals_store:
    path: ../../packages/signals_store  # or git/url
```

## Quick start

`ReactiveStore` is exposed through the package's public barrel file; `effect`
comes from the `signals` package.

```dart
import 'package:signals_store/signals_store.dart'; // ReactiveStore
import 'package:signals/signals.dart';             // effect

abstract class _CounterImpl {
  abstract int count;
  abstract String name;
}

class CounterStore extends _CounterImpl with ReactiveStore {
  CounterStore({required int count, required String name}) {
    this.count = count;
    this.name = name;
  }
}

void main() {
  final store = CounterStore(count: 0, name: 'demo');

  // Writes and reads are reactive via signals.
  store.count = 5;
  print(store.count); // 5

  // Subscribe via the signals API:
  effect(() => print('count changed: ${store.count}'));
  store.count = 10; // prints "count changed: 10"
}
```

In Flutter, call `dispose()` from `State.dispose()`:

```dart
class _MyWidgetState extends State<MyWidget> {
  final store = CounterStore(count: 0, name: '');

  @override
  void dispose() {
    store.dispose(); // mandatory!
    super.dispose();
  }
}
```

## Type safety

Fields are **fully statically typed**. `abstract int count` declares a typed
getter and setter, so the compiler checks both reads and writes:

```dart
final int c = store.count;   // OK
store.count = 'oops';        // ❌ compile error: invalid_assignment
```

Additionally, the abstract getter performs an implicit cast of the returned
value to the declared type — this gives a **runtime type-check** for free, even
if the value was written through an untyped path (a serializer, a reflection
mapper).

## Limitations

### 1. Symbol-normalization cache

`ReactiveStore` caches the result of `Symbol` normalization globally, keyed by
`runtimeType`. This is deterministic and optimal for production apps, but:

- **Overriding `runtimeType`** in a subclass is not supported — the cache may
  break or merge entries of different types. Do not override `runtimeType`.
- **Flutter hot-reload** registers a new `Type` on every reload, which causes
  bounded cache growth (~10–20 entries per dev session). To reset it in tests
  or under heavy hot-reload:

  ```dart
  ReactiveStore.resetCache(); // @visibleForTesting
  ```

### 2. Only mutable `abstract` fields are supported

`noSuchMethod` intercepts both the getter and the setter. Therefore:

- ❌ `abstract final int x` — does not work: `final` has no setter, so it cannot
  be initialized in the constructor → compile error.
- ❌ Computed (derived) fields are not supported by this approach. For computed
  values, use `signals` directly (`computed(...)`) outside `ReactiveStore`.

```dart
// ✅ Correct:
abstract class _Impl { abstract int count; }

// ❌ Wrong:
abstract class _Bad { abstract final int x; }  // compile error with ReactiveStore
```

### 3. Hot-path performance

`noSuchMethod` + 2 Map lookups on every read/write. Acceptable for UI state,
but tight for hot loops (lists of 10k+ elements). For hot paths consider code
generation (`signals_store_generator`).

### 4. `dispose()` is the caller's responsibility

`ReactiveStore` does not integrate with the Flutter lifecycle automatically. You
must call `dispose()`, otherwise the signals will leak. It is idempotent and
safe to call repeatedly.

### 5. Signal names in DevTools

Signals are named with the plain field name (`count`), not `Symbol("count")` —
for readability in DevTools and logs.

## Testing

```bash
# VM tests (default):
flutter test packages/signals_store/test/

# dart2js smoke (requires node):
bash packages/signals_store/scripts/dart2js_smoke.sh

# dart2js full (requires Chrome, for CI):
flutter test packages/signals_store/test/ --platform chrome
```

## License

See the root LICENSE.
