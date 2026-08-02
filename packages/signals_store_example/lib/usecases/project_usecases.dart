import '../data/fake_repos.dart';
import '../domain/stores.dart';
import 'package:signals/signals.dart';

/// UseCase: создать проект.
///
/// Внешняя зависимость ([ProjectsRepo]) передаётся параметром `call`.
extension type CreateProject(AppStore state) {
  Future<void> call({
    required String name,
    required int colorValue,
    required ProjectsRepo projectsRepo,
  }) async {
    final project = await projectsRepo.add(name: name, colorValue: colorValue);
    // MapSignal-мутация вне batch (см. заметку в CreateTodo). Скаляры — в batch.
    state.projects.projects[project.id] = project;
    batch(() {
      state.projects.currentProjectId = project.id;
      state.ui.filter.projectFilterId = project.id;
    });
  }
}

/// UseCase: выбрать активный проект (переключение вкладки/drawer-пункта).
/// Чистая мутация, без внешних зависимостей.
extension type SelectProject(AppStore state) {
  void call(String? projectId) {
    batch(() {
      state.projects.currentProjectId = projectId;
      state.ui.filter.projectFilterId = projectId;
    });
  }
}
