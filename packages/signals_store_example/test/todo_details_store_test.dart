// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:signals_store/signals_store.dart';

import 'package:signals_store_example/domain/enums.dart';
import 'package:signals_store_example/domain/models.dart';
import 'package:signals_store_example/domain/stores.dart';

/// Демонстрация сложного derived-стора: on-demand стейт экрана с параметром,
/// собственным состоянием, кросс-слайсными computed и dispose.
void main() {
  tearDown(StoreRootScope.resetCurrentZone);

  AppStore newStore() {
    final projects = mapSignal<String, Project>({
      'p1': const Project(id: 'p1', name: 'Work', colorValue: 0xFF42A5F5),
    });
    final todos = mapSignal<String, Todo>({
      't1': Todo(
        id: 't1',
        title: 'Ship release',
        projectId: 'p1',
        priority: Priority.high,
        dueDate: null,
        isDone: false,
        tagIds: const {'urgent'},
        createdAt: DateTime(2026, 1, 1),
      ),
      't2': Todo(
        id: 't2',
        title: 'Review PR',
        projectId: 'p1',
        priority: Priority.medium,
        dueDate: null,
        isDone: false,
        tagIds: const {'urgent', 'code'},
        createdAt: DateTime(2026, 1, 2),
      ),
      't3': Todo(
        id: 't3',
        title: 'Read book',
        projectId: 'p2', // другой проект
        priority: Priority.low,
        dueDate: null,
        isDone: false,
        tagIds: const {},
        createdAt: DateTime(2026, 1, 3),
      ),
    });
    final tags = mapSignal<String, Tag>({
      'urgent': const Tag(id: 'urgent', label: 'urgent', colorValue: 0xFFEF5350),
      'code': const Tag(id: 'code', label: 'code', colorValue: 0xFF26C6DA),
    });
    return AppStore(
      session: SessionStore(currentUser: null, isLoading: false, error: null),
      projects: ProjectsStore(projects: projects, todos: todos, currentProjectId: null),
      tags: TagsStore(tags: tags),
      ui: UiStore(
        filter: TodoFilter(hideDone: false, priorityFilter: null, projectFilterId: null, sortBy: TodoSortBy.createdDesc),
        isBusy: false,
        snackbarMessage: null,
      ),
    );
  }

  test('TodoDetailsStore: cross-slice computed over root', () {
    newStore(); // авторегистрируется (root: true)
    final store = TodoDetailsStore(todoId: 't1', isEditing: false);

    // Computed читают корень через StoreRootScope.
    expect(store.todo?.title, 'Ship release');
    expect(store.project?.name, 'Work'); // кросс-слайс todo→project
    expect(store.tags.map((t) => t.label), ['urgent']); // кросс-слайс todo→tags
    expect(store.relatedTodos.map((t) => t.id), ['t2']); // композиция computed
    expect(store.headerTitle, 'Work · Ship release');
    expect(store.canSave, isFalse); // isEditing=false
  });

  test('TodoDetailsStore: own state + param reactivity', () {
    final app = newStore();
    final store = TodoDetailsStore(todoId: 't1', isEditing: false);

    // Собственное состояние реактивно.
    expect(store.canSave, isFalse);
    store.isEditing = true;
    expect(store.canSave, isTrue);

    // Параметр создания — тоже reactive-поле: меняем без пересоздания стора.
    store.todoId = 't2';
    expect(store.todo?.title, 'Review PR');
    expect(store.headerTitle, 'Work · Review PR');

    // Мутация корня реактивна: удаление задачи → computed пересчитывается.
    app.projects.todos.remove('t2');
    expect(store.todo, isNull);
    expect(store.headerTitle, 'Задача не найдена');
  });

  test('TodoDetailsStore: dispose is safe (on-demand lifecycle)', () {
    newStore();
    final store = TodoDetailsStore(todoId: 't1', isEditing: false);
    expect(store.dispose, returnsNormally);
    expect(store.dispose, returnsNormally); // идемпотентно
  });
}
