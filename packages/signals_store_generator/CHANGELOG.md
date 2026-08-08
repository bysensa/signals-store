## 0.6.1

- **Docs**: document `@Store(root: true)` and `@DerivedStore` in the README
  (root store, derived stores, per-library `part of` constraint).

## 0.6.0

- **Feature (`@Store(root: true)`)**: a store annotated `@Store(root: true)`
  auto-registers itself in `StoreRootScope` — the constructor body emits
  `StoreRootScope.register(this)` (the root of the store tree, discoverable by
  derived stores via `StoreRootScope.of<T>()`). Non-root stores are unchanged.
- **Feature (unified `dispose()`)**: every generated `@Store` now emits a
  `void dispose()` method that disposes its `Signal` fields (`field$.dispose()`)
  and `Computed` fields (`getter$.dispose()`); for a `@Store(root: true)` store
  `dispose()` also calls `StoreRootScope.unregister(this)`. If the annotated
  superclass declares its own concrete `dispose()`, the generated method
  `@override`s it and chains `super.dispose()`. The generated code now imports
  `package:signals_store/signals_store.dart` for `StoreRootScope`.
- **Feature (`@DerivedStore`)**: derived stores with root access via
  `StoreRootScope.of<T>()`, their own reactive state, computed getters, and
  `dispose()`. A `@DerivedStore` class declares one abstract getter typed by a
  `@Store(root: true)` impl (the root slot); the generator emits it as
  `@override <Type> get <root> => StoreRootScope.of<<Type>>();` — a **getter**
  (not `late final`), so a freshly created derived always binds to the current
  root after root re-creation. Everything else (abstract fields → `Signal`,
  concrete fields → pass-through, concrete getters → `Computed`, name
  collisions, `dispose()`) is shared with `@Store` via the existing emitter.
  `@Store` and `@DerivedStore` on one class is rejected; a field (not getter)
  typed by a root store is rejected; a root getter typed by a non-root store is
  rejected.
- **Fix (dispose double-dispose)**: the unified `dispose()` previously emitted
  `field$.dispose()` twice for abstract fields (once via the field loop, once
  via the reactive-name loop). Now only `Computed` getters are disposed in the
  reactive-name loop; abstract fields are disposed once via the field loop.
  No behavioral change for correct usage (Signal/Computed `dispose()` is
  idempotent), but the generated source is no longer redundant.
- **Fix (empty constructor params)**: a store with no constructor parameters
  (e.g. a derived store whose state is only computed getters over the root)
  previously emitted an invalid `({})` named-parameter list; now emits `()`.

## 0.5.0

- **Deps**: raised the `analyzer` constraint from `^8.1.1` to `^12.1.0`. This
  is the highest analyzer version compatible with the current Flutter stable
  SDK (which pins `meta 1.18.0`; `analyzer >=13.1.0` requires `meta ^1.18.3`,
  and `test >=1.31.2` requires `analyzer >=13`, so 12.1.0 is the ceiling until
  Flutter's bundled `meta` and the test stack are bumped). **Breaking for
  consumers**: if your project depends on `analyzer` 8–11 (directly or through
  another generator), resolve the conflict by upgrading that side. Migrated the
  element-model usage to the analyzer 12 API: `isSynthetic` was removed from
  the public element API (replaced with `!isOriginDeclaration`),
  `ClassDeclaration.name` was removed from the AST (replaced with
  `namePart.typeName.lexeme`), and a private initializing-formal's
  `FormalParameterElement.name` now reports the *public* parameter name
  (`secret`) rather than the field name (`_secret`) — super-formal matching now
  keys on `FieldFormalParameterElement.field.name`. No change to the generated
  output.

## 0.4.4

- **Feature (self-sufficient concrete fields)**: concrete fields with an inline
  initializer (`final int x = 5;`, `int b = 5;`, `final int? c = null;`) and
  non-final nullable fields without an initializer (`int? d;`, `List<int>? e;`,
  which Dart defaults to `null`) no longer require an initializing-formal in
  the super constructor. They are not added to the generated constructor and
  not forwarded through `super` — their value comes from the field declaration
  in the superclass, which the generated subclass simply inherits. Previously
  these were rejected by the C4 validation ("cannot be forwarded through the
  super constructor"). A `final` field with no initializer (e.g. `final int? e;`)
  still requires an initializing-formal (Dart gives it no default), so it is
  still validated by C4.
- **Docs (late fields)**: a `late` field initialized in the body of the
  user-declared unnamed constructor (`SImpl() { f = 42; }`) is preserved — the
  generated subclass calls `super()` implicitly, so the constructor body runs.
  Initialization of `late` fields is the user's responsibility, as for any
  `late`. Added a regression test proving the generator does not break this
  pattern.
- **Bugfix (positional super argument order — silent data swap)**: with two or
  more private concrete fields forwarded through a positional super constructor
  (`SImpl(this._b, this._a)`), the generator passed `super(...)` arguments in
  *field-name-sorted* order (`super(a, b)`) instead of the super constructor's
  *formal-declaration* order (`super(b, a)`). Because the parameter types match,
  this compiled silently and swapped the values at runtime. The generator now
  collects positional super arguments in the formal-declaration order. It also
  rejects a positional super formal that has no matching concrete field.
- **Bugfix (multi-underscore private fields)**: the constructor parameter name
  for a private field stripped only ONE leading underscore, so `__count`
  produced the still-private parameter `_count` and re-triggered
  `private_named_non_field_parameter`. All leading underscores are now stripped
  (`__count` → `count`).
- **Bugfix (underscore-only field)**: a field consisting only of underscores
  (`abstract int _;`) previously produced an empty constructor parameter name
  and reached the source formatter with unparseable code. It now fails with a
  descriptive codegen error asking to rename the field.
- **i18n**: all user-facing `InvalidGenerationSource` error messages and the
  README are now in English (the package targets an international pub.dev
  audience). Code comments remain in Russian.
- **Bugfix (private fields)**: code generated for private fields
  (`abstract int _count;`, `final int _secret;`) previously did not compile.
  Dart forbids private names on named parameters that are not
  initializing-formals (`private_named_non_field_parameter`) and forbids
  `super._private` (`super_formal_parameter_without_associated_named`) — even
  within the same library. The generator emitted exactly these illegal forms
  but the existing tests missed it because they only used `contains` matchers
  and never compiled the result. A private field `_field` now produces a
  private signal/getter/setter (`_field$`, `_field`) but a **public**
  constructor parameter `field` (underscore stripped) that forwards the value.
  Private concrete fields with a positional super-constructor are now supported
  (`super(value)` in the initializer list, required to be last); private
  concrete fields with a named super-constructor (`{required this._x}`) are
  rejected with a descriptive error — Dart fundamentally does not expose a
  private named super-parameter to the subclass. The C4 validation now also
  rejects public concrete fields declared as positional initializing-formals
  (`this.x`) — `required super.x` requires a named formal. Added tests that
  actually compile the generated code via `dart analyze` (not just
  `contains` matchers), plus collision detection for the stripped parameter
  name (`count` + `_count` now collide).

## 0.4.3

- **Bugfix (name collisions)**: a getter whose name collides with an abstract
  field (`abstract int sum; int get sum => ...;`) or with the computed
  contract suffix (`int get sumRaw => ...;` next to `int get sum`) previously
  produced duplicate declarations (`sum$`, `get sum`, `sumRaw`) and broke the
  consumer's compile. The generator now collects all names it will emit and
  fails with a descriptive error naming the conflicting sources, asking to
  rename one of them.
- **Bugfix (named constructors)**: named constructors declared in the impl
  class are now rejected with a descriptive error. They cannot initialize
  abstract (Signal) fields, so the auto-generated unnamed constructor is the
  only supported one. Unnamed constructors remain supported (they initialize
  concrete fields via `super.x`).
- **Bugfix (missing super-constructor)**: a pass-through concrete field
  without an initializing-formal parameter in the superclass's unnamed
  constructor previously emitted an invalid `required super.<field>` and broke
  the consumer's compile. The generator now validates this upfront and fails
  with a descriptive error suggesting to add the constructor or make the field
  abstract.

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
