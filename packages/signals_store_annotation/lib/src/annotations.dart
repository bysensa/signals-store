/// Аннотация: помечает `abstract`-класс как описание стора, для которого
/// генератор создаст реализацию с заданным [name].
///
/// По умолчанию генерируется **конкретный** класс. Если [abstract] равен
/// `true`, генератор создаст `abstract`-класс — например, обобщённый базовый
/// стор, чью реализацию (с указанием аргументов типа) пользователь пишет сам.
///
/// На одном классе допускается **ровно одна** аннотация `@Store`; несколько
/// аннотаций вызывают ошибку кодогенерации.
///
/// ```dart
/// @Store(name: 'CounterStore')
/// abstract class CounterImpl {
///   abstract int count;
/// }
/// ```
///
/// Обобщённый абстрактный стор:
///
/// ```dart
/// @Store(name: 'GenericStore', abstract: true)
/// abstract class SomeStore<T, R extends Result> {
///   abstract T value;
/// }
/// ```
/// сгенерирует
/// ```dart
/// abstract class GenericStore<T, R extends Result> extends SomeStore<T, R> {
///   ...
/// }
/// ```
class Store {
  const Store({required this.name, this.abstract = false, this.root = false});

  /// Имя генерируемого класса-реализации.
  final String name;

  /// Если `true` — генерируется `abstract`-класс.
  final bool abstract;

  /// Если `true` — сгенерированный стор саморегистрируется в `StoreRootScope`
  /// при создании и является валидной целью root-геттера derived-сторов.
  final bool root;
}

/// Аннотация: помечает `abstract`-класс как derived-стор — полноценный стор
/// с собственным состоянием и доступом к корню дерева сторов.
///
/// Derived-стор идентичен `@Store` по всем механикам (abstract-поля → Signal,
/// concrete-поля → pass-through, concrete-геттеры → Computed). Отличия:
///
/// - обязательный геттер `root` **без тела** (bodyless), типизированный
///   `@Store(root: true)`-impl'ом; генератор эмитит его реализацию через
///   `StoreRootScope.of<T>()`. Ключевое слово `abstract` на членах запрещено
///   Dart — bodyless-геттер в abstract-классе абстрактен по умолчанию;
/// - сгенерированный `dispose()` для on-demand жизненного цикла (см. дизайн).
///
/// **Ограничение (per-library):** генератор резолвит тип root-геттера в рамках
/// одной библиотеки, поэтому derived-стор и его root-стор (`@Store(root: true)`)
/// должны быть в одной библиотеке. Чтобы разнести их по файлам, используйте
/// `part`/`part of` — оба файла образуют одну библиотеку.
///
/// На одном классе допускается ровно одна аннотация `@DerivedStore`;
/// `@Store` и `@DerivedStore` на одном классе запрещены.
///
/// ```dart
/// @DerivedStore(name: 'TodoDetailsStore')
/// abstract class TodoDetailsStoreImpl {
///   AppStoreImpl get root; // bodyless — генератор эмитит реализацию
///   abstract String todoId;
///   Todo? get todo => root.projects.todos[todoId];
/// }
/// ```
class DerivedStore {
  const DerivedStore({required this.name});

  /// Имя генерируемого класса-реализации.
  final String name;
}
