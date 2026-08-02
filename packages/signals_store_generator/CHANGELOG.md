## 0.1.1

- **Concrete (pass-through) fields**: fields declared with a concrete type
  (`final SessionStoreImpl session;`) are now passed through to the generated
  class as `required super.<field>` parameters instead of being wrapped in a
  `Signal`. Use these for nested substores and other stable references whose
  reactivity comes from their own fields, not from a root-level signal.
- **Nested store type rewrite**: when a concrete field is typed with the impl
  class of another `@Store` (`final SessionStoreImpl session;`), the generator
  emits the concrete implementation name (`SessionStore`). This gives consumers
  a fully-typed substore with reactive fields.
- `@override` is now added to the generated reactive getters/setters (they
  override the abstract accessors declared in the impl class).
- Generator error message updated: a `@Store` class without any fields reports
  «не содержит полей» instead of «не содержит abstract-полей» (concrete-only
  classes are now valid).
- Added generator tests for concrete-field pass-through, mixed
  abstract/concrete classes, and nested-store type rewrite.

## 0.1.0

- Initial version.
- `StoreGenerator` (`source_gen` + `build_runner`) that turns an
  `abstract`-class annotated with one or more `@Store(name: ...)` into concrete
  subclasses with `Signal`-backed fields.
- Multiple `@Store` annotations per class produce multiple implementations.
- `SharedPartBuilder` registered via `build.yaml` (writes `.g.dart` through
  `combining_builder`).
- Preserves field types incl. nullable and generic (`int?`, `List<String>`).
