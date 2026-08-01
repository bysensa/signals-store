## 0.1.0

- Initial version.
- `ReactiveStore` mixin: turns `abstract` fields into reactive `Signal`s via
  `noSuchMethod` interception, with full static typing.
- Symbol normalization cache (per store type) for cross-platform (VM/dart2js)
  `Symbol.toString()` formats.
- `dispose()` for releasing signals; `FieldInitializationError` for
  read-before-write semantics.
- `@visibleForTesting` helpers: `resetCache()`, `signalFor(Symbol)`.
