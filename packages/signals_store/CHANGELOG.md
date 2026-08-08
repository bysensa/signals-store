## 0.3.0

- **Feature**: added `StoreRootScope` — the store-tree root registry with
  explicit app/test environment separation. Environment is detected
  automatically via `Platform.environment['FLUTTER_TEST']` (no manual flag):
  tests resolve a per-zone registry (auto-isolation via the test runner's
  per-test zones), the app resolves a single global registry regardless of zone
  topology (e.g. `runZonedGuarded` in `main`). Roots are held via
  `WeakReference` to avoid retain cycles; `register`/`of<T>`/`unregister`/
  `resetCurrentZone` provided.

## 0.2.1

- **Docs**: translated the README to English. No behavioral changes.

## 0.2.0

- Bumps `signals_store_annotation` to `^0.2.0` (adds the `abstract` flag used by
  the code generator). No runtime changes — `ReactiveStore` behavior is
  unchanged. Existing consumers should also upgrade
  `signals_store_generator` to `^0.2.0`.

## 0.1.0

- Initial version.
- `ReactiveStore` mixin: turns `abstract` fields into reactive `Signal`s via
  `noSuchMethod` interception, with full static typing.
- Symbol normalization cache (per store type) for cross-platform (VM/dart2js)
  `Symbol.toString()` formats.
- `dispose()` for releasing signals; `FieldInitializationError` for
  read-before-write semantics.
- `@visibleForTesting` helpers: `resetCache()`, `signalFor(Symbol)`.
