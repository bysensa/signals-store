// ignore_for_file: lines_longer_than_80_chars

import 'enums.dart';
import 'models.dart';
import 'package:signals/signals.dart';
import 'package:signals_store/signals_store.dart';

part 'stores.g.dart';
part 'derived_stores.dart';
part 'todo_details_store.dart';

/// Глобальное дерево сторов по образцу Overmind.
///
/// Каждый `abstract`-класс помечен `@Store(name:)` — генератор создаёт
/// конкретный типобезопасный класс, где поля реактивны через `Signal`.
///
/// **Сторы не содержат внешних зависимостей** (репозиториев). Только данные.
/// Внешние зависимости передаются в UseCase как параметры `invoke` (см.
/// `lib/usecases/`).
///
/// Данные хранятся нормализованно — `Map<String, T>` по id, как завещает
/// Overmind (references вместо дублирования объектов).

/// Сессия текущего пользователя.
@Store(name: 'SessionStore')
abstract class SessionStoreImpl {
  /// Текущий пользователь. `null` — не аутентифицирован.
  abstract User? currentUser;

  /// Идёт ли запрос авторизации/загрузки.
  abstract bool isLoading;

  /// Текст ошибки последней операции (для показа в UI). `null` — нет ошибки.
  abstract String? error;
}

/// Проекты и задачи (нормализованно по id).
///
/// Коллекции `projects`/`todos` — реактивные через [MapSignal]: in-place-мутации
/// (`store.projects.todos[id] = v`, `.remove(id)`) автоматически триггерят
/// обновления. Это concrete-поля (стабильные ссылки), поэтому генератор
/// пробрасывает их как `super.x`, без лишней `Signal`-обёртки.
@Store(name: 'ProjectsStore')
abstract class ProjectsStoreImpl {
  /// Все проекты: id → Project (реактивная коллекция).
  final MapSignal<String, Project> projects;

  /// Все задачи: id → Todo (реактивная коллекция).
  final MapSignal<String, Todo> todos;

  /// Id текущего выбранного проекта. `null` — показывать все проекты.
  abstract String? currentProjectId;

  ProjectsStoreImpl({required this.projects, required this.todos});
}

/// Теги.
@Store(name: 'TagsStore')
abstract class TagsStoreImpl {
  /// Все теги: id → Tag (реактивная коллекция).
  final MapSignal<String, Tag> tags;

  TagsStoreImpl({required this.tags});
}

/// Фильтр и сортировка списка задач.
@Store(name: 'TodoFilter')
abstract class TodoFilterImpl {
  /// Id проекта-фильтра. `null` — без фильтра по проекту.
  abstract String? projectFilterId;

  /// Фильтр по приоритету. `null` — любой приоритет.
  abstract Priority? priorityFilter;

  /// Скрывать ли выполненные задачи.
  abstract bool hideDone;

  /// Способ сортировки.
  abstract TodoSortBy sortBy;

  /// Активен ли хоть один фильтр (computed — читает reactive-поля).
  bool get hasActiveFilter =>
      projectFilterId != null || priorityFilter != null || hideDone;
}

/// UI-состояние (busy-флаги, snackbar).
@Store(name: 'UiStore')
abstract class UiStoreImpl {
  /// Вложенный стор фильтра. Concrete-поле — стабилен, не реактивен на корне;
  /// его собственные поля реактивны через [Signal].
  final TodoFilterImpl filter;

  /// Глобальный busy-флаг для длительных операций.
  abstract bool isBusy;

  /// Сообщение для показа в SnackBar. `null` — скрыть.
  abstract String? snackbarMessage;

  UiStoreImpl({required this.filter});
}

/// Корневой стор — композиция вложенных подсторов.
///
/// Доступ: `appStore.session.currentUser`, `appStore.projects.todos[id]`,
/// `appStore.ui.filter.sortBy` и т.д.
///
/// Вложенные сторы — concrete-поля (стабильные ссылки). Их реактивность
/// обеспечивается собственными [Signal]-полями каждого подстора, а не
/// Signal-обёрткой на корне.
///
/// Помечен `root: true` — сгенерированный [AppStore] саморегистрируется в
/// `StoreRootScope` при создании и служит корнем для derived-сторов (см.
/// `derived_stores.dart`): они резолвят этот стор через `StoreRootScope.of`.
@Store(name: 'AppStore', root: true)
abstract class AppStoreImpl {
  final SessionStoreImpl session;
  final ProjectsStoreImpl projects;
  final TagsStoreImpl tags;
  final UiStoreImpl ui;

  AppStoreImpl({
    required this.session,
    required this.projects,
    required this.tags,
    required this.ui,
  });
}
