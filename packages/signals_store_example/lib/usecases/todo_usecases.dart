import 'dart:async';

import '../data/fake_repos.dart';
import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/stores.dart';

/// UseCase: создать задачу.
///
/// Внешняя зависимость ([TodosRepo]) передаётся параметром `invoke`.
extension type CreateTodo(AppStore state) {
  Future<void> invoke({
    required String title,
    required String projectId,
    required Priority priority,
    required DateTime? dueDate,
    required Set<String> tagIds,
    required TodosRepo todosRepo,
  }) async {
    final draft = TodoDraft(
      title: title,
      projectId: projectId,
      priority: priority,
      dueDate: dueDate,
      tagIds: tagIds,
    );
    final todo = await todosRepo.add(draft);
    // `todos` — реактивная MapSignal: in-place-мутация триггерит обновления.
    // ВНИМАНИЕ: не оборачиваем в batch() — MapSignal-мутации внутри batch в
    // signals 7.1.0 не доходят до computed/effect (см. тест reactive-fire).
    state.projects.todos[todo.id] = todo;
  }
}

/// UseCase: переключить статус выполнения задачи. Чистая мутация стейта, без
/// внешних зависимостей.
extension type ToggleTodo(AppStore state) {
  void invoke({required String todoId}) {
    final todo = state.projects.todos[todoId];
    if (todo == null) return;
    // MapSignal-мутация без batch (см. заметку в CreateTodo).
    state.projects.todos[todoId] = todo.copyWith(isDone: !todo.isDone);
  }
}

/// UseCase: удалить задачу.
///
/// Внешняя зависимость ([TodosRepo]) передаётся параметром `invoke`.
extension type DeleteTodo(AppStore state) {
  Future<void> invoke({required String todoId, required TodosRepo todosRepo}) async {
    await todosRepo.remove(todoId);
    // MapSignal-мутация без batch (см. заметку в CreateTodo).
    state.projects.todos.remove(todoId);
  }
}
