## 0.1.0

- Initial version.
- `StoreGenerator` (`source_gen` + `build_runner`) that turns an
  `abstract`-class annotated with one or more `@Store(name: ...)` into concrete
  subclasses with `Signal`-backed fields.
- Multiple `@Store` annotations per class produce multiple implementations.
- `SharedPartBuilder` registered via `build.yaml` (writes `.g.dart` through
  `combining_builder`).
- Preserves field types incl. nullable and generic (`int?`, `List<String>`).
