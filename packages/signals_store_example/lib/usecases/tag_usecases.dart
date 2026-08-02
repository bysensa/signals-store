import '../data/fake_repos.dart';
import '../domain/stores.dart';

/// UseCase: создать тег.
///
/// Внешняя зависимость ([TagsRepo]) передаётся параметром `call`.
extension type CreateTag(AppStore state) {
  Future<void> call({
    required String label,
    required int colorValue,
    required TagsRepo tagsRepo,
  }) async {
    final tag = await tagsRepo.add(label: label, colorValue: colorValue);
    // MapSignal-мутация без batch (см. заметку в CreateTodo).
    state.tags.tags[tag.id] = tag;
  }
}
