## 0.3.1

- **Docs**: document `@Store(root: true)` and `@DerivedStore` in the README.

## 0.3.0

- **Feature**: added `@Store(root: true)` flag — the store auto-registers itself
  in `StoreRootScope` on construction and becomes a valid target for a derived
  store's root getter.
- **Feature**: added `@DerivedStore` annotation — a full store with root access
  via a bodyless root getter (e.g. `AppStoreImpl get root;`).

## 0.2.1

- **Docs**: translated the README to English. No behavioral changes.

## 0.2.0

- **Abstract stores**: added `abstract` flag to `@Store`
  (`@Store(name: ..., abstract: true)`). When set, the generator emits an
  `abstract class` instead of a concrete one — useful for generic base stores
  whose concrete implementation is written by the consumer.
- **Breaking**: the generator no longer supports multiple `@Store` annotations
  on a single class. Each annotated class must carry at most one `@Store`;
  a second annotation now fails code generation.

## 0.1.0

- Initial version.
- `@Store({required String name})` annotation for describing reactive stores.
