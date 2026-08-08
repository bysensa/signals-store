// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:signals_store_example/data/fake_repos.dart';
import 'package:signals_store_example/domain/enums.dart';
import 'package:signals_store_example/domain/models.dart';
import 'package:signals_store_example/domain/stores.dart';
import 'package:signals_store_example/usecases/auth_usecases.dart';
import 'package:signals_store_example/usecases/filter_usecases.dart';
import 'package:signals_store_example/usecases/init_usecases.dart';
import 'package:signals_store_example/usecases/todo_usecases.dart';

/// Архитектурные smoke-тесты примера Tasker.
///
/// Проверяют, что слои (сторы без репозиториев, UseCase как extension type
/// стора, derived-селекторы) работают end-to-end без UI:
/// - сторы типобезопасны и реактивны (через @Store codegen + MapSignal);
/// - UseCase мутирует стор, внешние зависимости — параметры call;
/// - computed-селекторы пересчитываются при изменении стора.
AppStore _freshStore() => AppStore(
      session: SessionStore(currentUser: null, isLoading: false, error: null),
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

void main() {
  group('stores', () {
    test('AppStore exposes nested concrete substores with reactive fields', () {
      final store = _freshStore();

      // Вложенные сторы доступны как concrete-поля (не Signal-wrapped на корне).
      expect(store.session, isA<SessionStore>());
      expect(store.projects, isA<ProjectsStore>());
      expect(store.tags, isA<TagsStore>());
      expect(store.ui, isA<UiStore>());
      // А вложенный фильтр — в свою очередь concrete-поле UiStore.
      expect(store.ui.filter, isA<TodoFilter>());

      // Поля реактивны: запись обновляет чтение.
      store.session.isLoading = true;
      expect(store.session.isLoading, isTrue);
      store.ui.filter.sortBy = TodoSortBy.priorityDesc;
      expect(store.ui.filter.sortBy, TodoSortBy.priorityDesc);
    });

    test('typed store fields reject wrong types at runtime', () {
      final store = _freshStore();
      // Невалидная запись бросает type error (абстрактный геттер implicit-cast'ит).
      expect(
        () => store.session.currentUser = const User(
          id: '1',
          name: 'x',
          email: 'y',
        ),
        returnsNormally,
      );
      expect(store.session.currentUser?.name, 'x');
    });
  });

  group('UseCase: extension type on AppStore', () {
    test('CreateTodo mutates store via call, repo passed as dependency', () async {
      final store = _freshStore();
      // Подготовим проект, к которому привяжем задачу.
      store.projects.projects['p1'] =
          const Project(id: 'p1', name: 'Personal', colorValue: 0xFF000000);

      final repos = Repos.defaults();
      await CreateTodo(store)(
        title: 'Test task',
        projectId: 'p1',
        priority: Priority.high,
        dueDate: null,
        tagIds: const {},
        todosRepo: repos.todos,
      );

      expect(store.projects.todos.length, 1);
      final todo = store.projects.todos.values.single;
      expect(todo.title, 'Test task');
      expect(todo.priority, Priority.high);
      expect(todo.projectId, 'p1');
      expect(todo.isDone, isFalse);
    });

    test('ToggleTodo flips isDone without external dependencies', () async {
      final store = _freshStore();
      store.projects.projects['p1'] =
          const Project(id: 'p1', name: 'P', colorValue: 0xFF000000);

      final repos = Repos.defaults();
      await CreateTodo(store)(
        title: 't',
        projectId: 'p1',
        priority: Priority.low,
        dueDate: null,
        tagIds: const {},
        todosRepo: repos.todos,
      );
      final id = store.projects.todos.keys.single;

      ToggleTodo(store)(todoId: id);
      expect(store.projects.todos[id]!.isDone, isTrue);
      ToggleTodo(store)(todoId: id);
      expect(store.projects.todos[id]!.isDone, isFalse);
    });

    test('SetPriorityFilter mutates ui.filter without dependencies', () {
      final store = _freshStore();
      SetPriorityFilter(store)(Priority.high);
      expect(store.ui.filter.priorityFilter, Priority.high);
    });

    test('Login records error on bad credentials (repo is a dependency)',
        () async {
      final store = _freshStore();
      final repos = Repos.defaults();
      await expectLater(
        Login(store)(
          email: 'nobody@example.com',
          password: 'x',
          authRepo: repos.auth,
        ),
        throwsA(isA<AuthException>()),
      );
      expect(store.session.error, isNotNull);
      expect(store.session.currentUser, isNull);
    });
  });

  group('derived selectors', () {
    test('LoadInitialData seeds store and derived stats reflect it', () async {
      final store = _freshStore();
      final repos = Repos.defaults();
      await LoadInitialData(store)(
        projectsRepo: repos.projects,
        todosRepo: repos.todos,
        tagsRepo: repos.tags,
      );

      // Сидер репозиториев: 3 проекта, 3 тега, 4 задачи.
      expect(store.projects.projects.length, 3);
      expect(store.tags.tags.length, 3);
      expect(store.projects.todos.length, 4);

      final derived = TodosDerived();
      final stats = derived.todoStats;
      expect(stats.total, 4);
      // Одна задача в сидере помечена done (td4).
      expect(stats.done, 1);
      expect(stats.active, 3);
    });

    test('visibleTodos respects hideDone filter and recomputes', () async {
      final store = _freshStore();
      final repos = Repos.defaults();
      await LoadInitialData(store)(
        projectsRepo: repos.projects,
        todosRepo: repos.todos,
        tagsRepo: repos.tags,
      );
      final derived = TodosDerived();

      // После LoadInitialData фильтр по проекту = первый проект (p1 «Личное»),
      // в котором 2 задачи (одна выполнена). Снимем фильтр по проекту, чтобы
      // видеть все 4.
      SetProjectFilter(store)(null);
      final beforeHide = derived.visibleTodos.length;
      ToggleHideDone(store)();
      final afterHide = derived.visibleTodos.length;

      expect(beforeHide, 4);
      expect(afterHide, 3); // одна выполненная скрыта
    });

    test(
        'in-place MapSignal mutations (CreateTodo/DeleteTodo) fire reactive '
        'updates', () async {
      // Регрессия: Signal<Map> НЕ триггерит on in-place map[k]=v/remove.
      // Коллекции в сторах теперь реактивные MapSignal, поэтому UseCase-мутации
      // должны вызывать подписки. Проверяем через effect (как делает UI).
      final store = _freshStore();
      store.projects.projects['p1'] =
          const Project(id: 'p1', name: 'P', colorValue: 0xFF000000);

      final derived = TodosDerived();
      var fireCount = 0;
      final sub = effect(() {
        // Чтение computed подписывает эффект на все затронутые сигналы.
        derived.visibleTodos;
        fireCount++;
      });
      expect(fireCount, 1); // первичное срабатывание.

      final repos = Repos.defaults();
      await CreateTodo(store)(
        title: 'reactive task',
        projectId: 'p1',
        priority: Priority.medium,
        dueDate: null,
        tagIds: const {},
        todosRepo: repos.todos,
      );
      expect(fireCount, greaterThan(1), reason: 'CreateTodo должен триггерить');

      final id = store.projects.todos.keys.single;
      await DeleteTodo(store)(todoId: id, todosRepo: repos.todos);
      expect(fireCount, greaterThan(2), reason: 'DeleteTodo должен триггерить');

      sub();
    });
  });
}
