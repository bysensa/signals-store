import '../domain/enums.dart';
import '../domain/stores.dart';
import 'package:signals/signals.dart';

/// Группа usecase'ов для управления фильтром/сортировкой списка задач.
///
/// Все — чистые мутации `ui.filter`, без внешних зависимостей. Сгруппированы
/// в один файл, т.к. концептуально связаны.

/// UseCase: задать фильтр по проекту. `null` — сбросить.
extension type SetProjectFilter(AppStore state) {
  void call(String? projectId) {
    state.ui.filter.projectFilterId = projectId;
  }
}

/// UseCase: задать фильтр по приоритету. `null` — любой приоритет.
extension type SetPriorityFilter(AppStore state) {
  void call(Priority? priority) {
    state.ui.filter.priorityFilter = priority;
  }
}

/// UseCase: переключить скрытие выполненных задач.
extension type ToggleHideDone(AppStore state) {
  void call() {
    state.ui.filter.hideDone = !state.ui.filter.hideDone;
  }
}

/// UseCase: задать способ сортировки.
extension type SetSortBy(AppStore state) {
  void call(TodoSortBy sortBy) {
    state.ui.filter.sortBy = sortBy;
  }
}

/// UseCase: сбросить фильтр к значениям по умолчанию.
extension type ResetFilter(AppStore state) {
  void call() {
    batch(() {
      state.ui.filter.projectFilterId = state.projects.currentProjectId;
      state.ui.filter.priorityFilter = null;
      state.ui.filter.hideDone = false;
      state.ui.filter.sortBy = TodoSortBy.createdDesc;
    });
  }
}
