## 0.4.2

- **Bugfix (FP-4)**: a getter reading a concrete pass-through field of a
  `@Store` substore (e.g. `String get tag => config.label;` where `label` is
  concrete, not abstract/Signal) is no longer made `Computed`. Previously the
  detector treated the whole substore as reactive without distinguishing which
  field was read. Now it checks the specific field: only abstract fields
  (Signal-backed) or fields with a reactive type count as reactive. Concrete
  pass-through fields (`String`, `int`, ...) leave the accessing getter plain.
  Access to abstract substore fields (e.g. `savings.amount`) correctly remains
  `Computed`. Added a regression test.

## 0.4.1

- **Bugfix**: reactivity flowing through call arguments is now detected. A
  getter that passes a reactive value as an argument to a helper method
  (e.g. `String get x => _fmt(balance);`) now becomes a `Computed`. Previously
  the AST visitor did not traverse `MethodInvocation.argumentList` for bare
  (target-less) calls, so the read of the reactive argument was lost and the
  getter stayed plain. No interprocedural analysis is required: reading a
  reactive value at the call site is itself reactive. Added 5 dataflow tests.

## 0.4.0

- **Computed getters**: a concrete getter (a getter with a body) in a `@Store`
  class whose body references reactive state now becomes a `Computed`-backed
  derived value. For each reactive getter `x`, the generator emits:
  - `late final Computed<T> x$ = computed(() => xRaw, options: ...)` — the
    memoized, reactive signal (lazy, glitch-free).
  - `@override T get x => x$.value;` — the reactive accessor consumers read.
  - `@override T get xRaw => super.x;` — the raw recompute (escape-hatch for
    getters with non-reactive dependencies).
- **Reactivity detector** (new `reactivity.dart`): determines which concrete
  getters are reactive through type analysis, not name lists. A getter is
  considered reactive if its body references any of: an abstract field, a
  concrete field whose type is a `@Store` impl (substore), a concrete field
  whose type is or contains a `Signal` (collections, user classes with Signal
  fields — deep cascade with cycle protection via `mixin`s and `implements`),
  another reactive getter/method (transitive fixpoint), or any access to a
  `Signal`-typed expression (`.value`, `.length`, `[]`, `.where()`, etc. —
  excluding untracked `.peek()`/`.previousValue` and pure mutations). Verified
  by 45 detector tests.
- Non-reactive getters are overridden as trivial `super.x` delegates so the
  generated class stays concrete.
- `Computed`/`computed` are resolved from the consumer's existing `signals`
  import — no new import required.
- Example `TodoFilterImpl` gains a `hasActiveFilter` computed getter to
  demonstrate the feature end-to-end.

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
