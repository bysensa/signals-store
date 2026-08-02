import 'package:flutter/material.dart';
import 'package:signals/signals.dart';

import 'data/fake_repos.dart';
import 'domain/enums.dart';
import 'domain/models.dart';
import 'domain/stores.dart';
import 'ui/app.dart';

/// Точка входа в приложение Tasker.
///
/// Здесь собирается дерево состояния (вложенные сторы — concrete-поля корневого
/// `AppStore`) и набор репозиториев (внешних зависимостей). Стор и репозитории
/// передаются в `TaskerApp`, который регистрирует `Actions` и связывает UI.
void main() {
  // Дерево сторов (overmind-style): корневой AppStore — композиция вложенных
  // подсторов. Каждый подстор — @Store-сгенерированный класс. Коллекции
  // (projects/todos/tags) — реактивные `MapSignal`, in-place-мутации которых
  // автоматически триггерят обновления; скалярные поля — реактивны через Signal.
  final store = AppStore(
    session: SessionStore(
      currentUser: null,
      isLoading: false,
      error: null,
    ),
    projects: ProjectsStore(
      projects: mapSignal<String, Project>({}),
      todos: mapSignal<String, Todo>({}),
      currentProjectId: null,
    ),
    tags: TagsStore(tags: mapSignal<String, Tag>({})),
    ui: UiStore(
      filter: TodoFilter(
        hideDone: false,
        priorityFilter: null,
        projectFilterId: null,
        sortBy: TodoSortBy.createdDesc,
      ),
      isBusy: false,
      snackbarMessage: null,
    ),
  );

  // Внешние зависимости. В сторах их нет — они передаются параметрами в
  // UseCase-методы `invoke` (см. lib/usecases/) и в конструкторы Actions.
  final repos = Repos.defaults();

  runApp(TaskerApp(store: store, repos: repos));
}
