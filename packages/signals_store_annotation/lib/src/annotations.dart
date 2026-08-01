/// Аннотация: помечает `abstract`-класс как описание стора, для которого
/// генератор создаст конкретную реализацию с заданным [name].
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
class Store {
  const Store({required this.name});

  /// Имя генерируемого класса-реализации.
  final String name;
}
