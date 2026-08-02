## 0.3.0

- **Breaking**: signal fields now inherit the visibility of their source field.
  A public `abstract int count;` produces a public `count$` signal field
  (previously always `_count$`); a private `abstract int _count;` produces
  `_count$`. Consumers that referenced the previously-private signal fields by
  name within the generated library need to update to the new names. Generated
  getters/setters and the public API surface (the overridden accessors) are
  unaffected.
- Added generator tests for visibility preservation across public, private, and
  mixed-field classes.

## 0.2.0

- **Generic stores**: type parameters of the annotated class
  (`<T, R extends Result>`) are now carried over to the generated store — with
  bounds in the class declaration and without bounds in the `extends` clause
  (`class GenericStore<T, R extends Result> extends SomeStore<T, R>`).
- **Abstract stores**: `@Store(abstract: true)` produces an `abstract class`
  instead of a concrete one, enabling generic base stores whose concrete
  implementation is hand-written by the consumer.
- **Breaking**: multiple `@Store` annotations on a single class are no longer
  supported. Each `abstract`-class must carry at most one `@Store`; a second
  annotation now fails code generation with an explicit error. Split different
  implementations across separate classes.
- **Bugfix**: `static` fields are now ignored — they no longer leak into the
  generated constructor as spurious `super.x` parameters (`static const max`
  is class-level metadata, not instance state).
- **Bugfix**: `late` fields are now ignored — they cannot be `super.x`
  pass-through parameters (the superclass has no matching constructor
  parameter) and are not reactive abstract accessors.
- **Bugfix**: reactive fields typed with a generic store now keep their type
  arguments during the impl → implementation rewrite
  (`abstract BoxImpl<int> box;` → `Signal<Box<int>>`, previously `Signal<Box>`).
- Added generator tests for generic type parameters, bounded generics, the
  `abstract` flag, the multiple-annotation error, generic-store-typed fields,
  and `static`/`late` field handling.
- Bumps `signals_store_annotation` to `^0.2.0`.

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
