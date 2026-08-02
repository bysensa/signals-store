import '../data/fake_repos.dart';
import '../domain/models.dart';
import '../domain/stores.dart';
import 'package:signals/signals.dart';

/// UseCase: загрузить начальные данные (проекты, теги, задачи).
///
/// Оркестрирует три репозитория в одной операции. Все три — внешние зависимости,
/// передаются параметром `invoke` (в сторах их нет).
extension type LoadInitialData(AppStore state) {
  Future<void> invoke({
    required ProjectsRepo projectsRepo,
    required TodosRepo todosRepo,
    required TagsRepo tagsRepo,
  }) async {
    batch(() {
      state.session.isLoading = true;
      state.ui.isBusy = true;
    });
    try {
      // Параллельная загрузка — независимые репозитории. Каждому future —
      // явный типовой параметр, иначе `Future.wait` вернёт `List<Object>`.
      final results = await Future.wait<dynamic>([
        projectsRepo.fetchAll(),
        tagsRepo.fetchAll(),
        todosRepo.fetchAll(),
      ]);
      final projects = results[0] as List<Project>;
      final tags = results[1] as List<Tag>;
      final todos = results[2] as List<Todo>;

      // Коллекции — реактивные MapSignal: in-place-мутации вне batch
      // (внутри batch в signals 7.1.0 они не доходят до computed/effect).
      for (final p in projects) {
        state.projects.projects[p.id] = p;
      }
      for (final t in tags) {
        state.tags.tags[t.id] = t;
      }
      for (final t in todos) {
        state.projects.todos[t.id] = t;
      }
      // По умолчанию выбираем первый проект, если он есть. Скаляры внутри batch.
      if (projects.isNotEmpty) {
        batch(() {
          state.projects.currentProjectId = projects.first.id;
          state.ui.filter.projectFilterId = projects.first.id;
        });
      }
    } finally {
      batch(() {
        state.session.isLoading = false;
        state.ui.isBusy = false;
      });
    }
  }
}
