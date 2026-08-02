import 'package:flutter/widgets.dart';

import '../data/fake_repos.dart';
import '../domain/stores.dart';
import '../intents/intents.dart';
import '../ui/widgets/create_project_dialog.dart' as project_dialog;
import '../ui/widgets/create_todo_dialog.dart' as todo_dialog;
import '../ui/widgets/filter_dialog.dart' as filter_dialog;
import '../usecases/auth_usecases.dart';
import '../usecases/filter_usecases.dart';
import '../usecases/init_usecases.dart';
import '../usecases/project_usecases.dart';
import '../usecases/todo_usecases.dart';
import '../usecases/ui_usecases.dart';

/// Actions — оркестраторы логики.
///
/// Каждый [ContextAction<T extends Intent>] получает `BuildContext` в `invoke`
/// (через [ContextAction]) — это позволяет ему взаимодействовать с навигацией
/// и показывать диалоги/SnackBar. Action:
///
/// 1. извлекает параметры из [Intent];
/// 2. вызывает нужный UseCase, передавая в него стор (через `extension type`)
///    и внешние зависимости (репозитории) параметрами `call`;
/// 3. выполняет UI-сайд-эффекты (навигация, диалоги) через `context`.
///
/// Все actions собираются в `Map<Type, Action<Intent>>` через [buildActions] и
/// регистрируются одним `Actions` widget в корне приложения (см. `ui/app.dart`).
///
/// Диалоги (create todo / filter / create project) реализованы как виджеты в
/// `ui/widgets/` и показываются actions через `showDialog`. Сами виджеты
/// диалогов внутри вызывают `Actions.invoke(context, ...)`, формируя цепочку
/// действий (например, ShowCreateTodoDialogIntent → CreateTodoIntent).

/// Действие: войти. Вызывает `Login` + `LoadInitialData` UseCase.
class LoginAction extends ContextAction<LoginIntent> {
  LoginAction(this.store, this.repos);
  final AppStore store;
  final Repos repos;

  @override
  Future<Object?> invoke(LoginIntent intent, [BuildContext? context]) async {
    try {
      await Login(store)(
        email: intent.email,
        password: intent.password,
        authRepo: repos.auth,
      );
      // После успешного логина — загрузить начальные данные.
      await LoadInitialData(store)(
        projectsRepo: repos.projects,
        todosRepo: repos.todos,
        tagsRepo: repos.tags,
      );
    } on Exception {
      // Ошибка уже записана в `session.error` UseCase'ом; UI её покажет.
    }
    return null;
  }
}

/// Действие: выйти. Сбрасывает сессию.
class LogoutAction extends ContextAction<LogoutIntent> {
  LogoutAction(this.store, this.repos);
  final AppStore store;
  final Repos repos;

  @override
  Future<Object?> invoke(LogoutIntent intent, [BuildContext? context]) async {
    await repos.auth.logout();
    Logout(store)();
    return null;
  }
}

/// Действие: показать диалог создания задачи. После заполнения формы диалог
/// сам вызовет `CreateTodoIntent` (цепочка действий).
class ShowCreateTodoDialogAction
    extends ContextAction<ShowCreateTodoDialogIntent> {
  ShowCreateTodoDialogAction(this.store);
  final AppStore store;

  @override
  Future<Object?> invoke(
    ShowCreateTodoDialogIntent intent, [
    BuildContext? context,
  ]) async {
    if (context == null) return null;
    // Импорт виджета диалога — нижним блоком `late import`-стиля невозможен
    // в Dart, поэтому показываем его напрямую. Циклической зависимости нет:
    // диалог ссылается на actions только через `Actions.invoke` в рантайме.
    // ignore: implementation_imports
    await _showCreateTodoDialog(context, store);
    return null;
  }
}

/// Действие: создать задачу. Вызывает `CreateTodo` UseCase + показывает SnackBar.
class CreateTodoAction extends ContextAction<CreateTodoIntent> {
  CreateTodoAction(this.store, this.repos);
  final AppStore store;
  final Repos repos;

  @override
  Future<Object?> invoke(CreateTodoIntent intent, [BuildContext? context]) async {
    await CreateTodo(store)(
      title: intent.title,
      projectId: intent.projectId,
      priority: intent.priority,
      dueDate: intent.dueDate,
      tagIds: intent.tagIds,
      todosRepo: repos.todos,
    );
    ShowSnackbar(store)(message: 'Задача добавлена');
    return null;
  }
}

/// Действие: переключить статус задачи.
class ToggleTodoAction extends ContextAction<ToggleTodoIntent> {
  ToggleTodoAction(this.store);
  final AppStore store;

  @override
  Object? invoke(ToggleTodoIntent intent, [BuildContext? context]) {
    ToggleTodo(store)(todoId: intent.todoId);
    return null;
  }
}

/// Действие: удалить задачу.
class DeleteTodoAction extends ContextAction<DeleteTodoIntent> {
  DeleteTodoAction(this.store, this.repos);
  final AppStore store;
  final Repos repos;

  @override
  Future<Object?> invoke(DeleteTodoIntent intent, [BuildContext? context]) async {
    await DeleteTodo(store)(
      todoId: intent.todoId,
      todosRepo: repos.todos,
    );
    ShowSnackbar(store)(message: 'Задача удалена');
    return null;
  }
}

/// Действие: выбрать проект.
class OpenProjectAction extends ContextAction<OpenProjectIntent> {
  OpenProjectAction(this.store);
  final AppStore store;

  @override
  Object? invoke(OpenProjectIntent intent, [BuildContext? context]) {
    SelectProject(store)(intent.projectId);
    return null;
  }
}

/// Действие: показать диалог фильтра.
class ShowFilterDialogAction extends ContextAction<ShowFilterDialogIntent> {
  ShowFilterDialogAction(this.store);
  final AppStore store;

  @override
  Future<Object?> invoke(
    ShowFilterDialogIntent intent, [
    BuildContext? context,
  ]) async {
    if (context == null) return null;
    await _showFilterDialog(context, store);
    return null;
  }
}

/// Действие: задать фильтр по приоритету.
class SetPriorityFilterAction extends ContextAction<SetPriorityFilterIntent> {
  SetPriorityFilterAction(this.store);
  final AppStore store;

  @override
  Object? invoke(SetPriorityFilterIntent intent, [BuildContext? context]) {
    SetPriorityFilter(store)(intent.priority);
    return null;
  }
}

/// Действие: переключить скрытие выполненных.
class ToggleHideDoneAction extends ContextAction<ToggleHideDoneIntent> {
  ToggleHideDoneAction(this.store);
  final AppStore store;

  @override
  Object? invoke(ToggleHideDoneIntent intent, [BuildContext? context]) {
    ToggleHideDone(store)();
    return null;
  }
}

/// Действие: задать сортировку.
class SetSortByAction extends ContextAction<SetSortByIntent> {
  SetSortByAction(this.store);
  final AppStore store;

  @override
  Object? invoke(SetSortByIntent intent, [BuildContext? context]) {
    SetSortBy(store)(intent.sortBy);
    return null;
  }
}

/// Действие: сбросить фильтр.
class ResetFilterAction extends ContextAction<ResetFilterIntent> {
  ResetFilterAction(this.store);
  final AppStore store;

  @override
  Object? invoke(ResetFilterIntent intent, [BuildContext? context]) {
    ResetFilter(store)();
    return null;
  }
}

/// Действие: показать диалог создания проекта.
class ShowCreateProjectDialogAction
    extends ContextAction<ShowCreateProjectDialogIntent> {
  ShowCreateProjectDialogAction(this.store);
  final AppStore store;

  @override
  Future<Object?> invoke(
    ShowCreateProjectDialogIntent intent, [
    BuildContext? context,
  ]) async {
    if (context == null) return null;
    await _showCreateProjectDialog(context, store);
    return null;
  }
}

/// Действие: создать проект. Вызывает `CreateProject` UseCase + SnackBar.
class CreateProjectAction extends ContextAction<CreateProjectIntent> {
  CreateProjectAction(this.store, this.repos);
  final AppStore store;
  final Repos repos;

  @override
  Future<Object?> invoke(
    CreateProjectIntent intent, [
    BuildContext? context,
  ]) async {
    await CreateProject(store)(
      name: intent.name,
      colorValue: intent.colorValue,
      projectsRepo: repos.projects,
    );
    ShowSnackbar(store)(message: 'Проект создан');
    return null;
  }
}

/// Собирает реестр `Type → Action` для регистрации в `Actions` widget.
///
/// Один вызов `buildActions(store, repos)` в корне приложения покрывает все
/// интенты. UI запускает действия через `Actions.invoke(context, SomeIntent())`.
Map<Type, Action<Intent>> buildActions(AppStore store, Repos repos) {
  return <Type, Action<Intent>>{
    LoginIntent: LoginAction(store, repos),
    LogoutIntent: LogoutAction(store, repos),
    ShowCreateTodoDialogIntent: ShowCreateTodoDialogAction(store),
    CreateTodoIntent: CreateTodoAction(store, repos),
    ToggleTodoIntent: ToggleTodoAction(store),
    DeleteTodoIntent: DeleteTodoAction(store, repos),
    OpenProjectIntent: OpenProjectAction(store),
    ShowFilterDialogIntent: ShowFilterDialogAction(store),
    SetPriorityFilterIntent: SetPriorityFilterAction(store),
    ToggleHideDoneIntent: ToggleHideDoneAction(store),
    SetSortByIntent: SetSortByAction(store),
    ResetFilterIntent: ResetFilterAction(store),
    ShowCreateProjectDialogIntent: ShowCreateProjectDialogAction(store),
    CreateProjectIntent: CreateProjectAction(store, repos),
  };
}

// --- Реализации показа диалогов ---
//
// Каждая функция — тонкая обёртка над `showDialog`, строит виджет диалога из
// `ui/widgets/` и передаёт ему стор. Внутри диалога подтверждение делается
// через `Actions.invoke(context, ...)`, что замыкает цепочку:
// Action показывает диалог → пользователь заполняет форму → диалог вызывает
// дочерний Intent → Action выполняет UseCase.

Future<void> _showCreateTodoDialog(BuildContext context, AppStore store) {
  return todo_dialog.showCreateTodoDialog(context, store);
}

Future<void> _showFilterDialog(BuildContext context, AppStore store) {
  return filter_dialog.showFilterDialog(context, store);
}

Future<void> _showCreateProjectDialog(BuildContext context, AppStore store) {
  return project_dialog.showCreateProjectDialog(context, store);
}
