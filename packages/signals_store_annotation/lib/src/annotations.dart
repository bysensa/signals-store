/// Аннотация: помечает `abstract`-класс как описание стора, для которого
/// генератор создаст реализацию с заданным [name].
///
/// По умолчанию генерируется **конкретный** класс. Если [abstract] равен
/// `true`, генератор создаст `abstract`-класс — например, обобщённый базовый
/// стор, чью реализацию (с указанием аргументов типа) пользователь пишет сам.
///
/// Несколько аннотаций `@Store` на одном классе создают несколько реализаций
/// (по одной на аннотацию):
///
/// ```dart
/// @Store(name: 'FirstSomeStore')
/// @Store(name: 'SecondSomeStore')
/// abstract class SomeStoreImpl {
///   abstract String name;
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
  const Store({required this.name, this.abstract = false});

  /// Имя генерируемого класса-реализации.
  final String name;

  /// Если `true` — генерируется `abstract`-класс (например, обобщённый базовый
  /// стор). По умолчанию `false` (конкретный класс).
  final bool abstract;
}
