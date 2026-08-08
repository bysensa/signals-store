// ignore_for_file: lines_longer_than_80_chars

import 'package:signals/signals.dart';
import 'package:signals_store/signals_store.dart';
import 'package:test/test.dart';

import 'package:signals_store_example/domain/enums.dart';
import 'package:signals_store_example/domain/models.dart';
import 'package:signals_store_example/domain/stores.dart';

/// Интеграционный тест derived-стора `TodosDerived`: резолв корня через
/// `StoreRootScope` (авторегистрация при создании `AppStore(root: true)`),
/// реактивность computed-геттеров и безопасный dispose.
///
/// Окружение детектится автоматически по `FLUTTER_TEST` (без enableTestMode).
/// `resetCurrentZone` в tearDown — опциональная страховка.
void main() {
  tearDown(StoreRootScope.resetCurrentZone);

  AppStore _newStore() => AppStore(
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

  group('TodosDerived (integration)', () {
    test('resolves root via StoreRootScope and computes from it', () {
      final app = _newStore(); // авторегистрируется в test-окружение
      final derived = TodosDerived();

      expect(derived.visibleTodos, isEmpty);
      expect(derived.isAuthenticated, isFalse);

      app.projects.todos['1'] = Todo(
        id: '1',
        title: 'Write tests',
        projectId: 'p1',
        priority: Priority.medium,
        dueDate: null,
        isDone: false,
        tagIds: const {},
        createdAt: DateTime(2026, 1, 1),
      );
      expect(derived.visibleTodos, hasLength(1));
    });

    test('dispose runs without throwing', () {
      _newStore();
      final derived = TodosDerived();
      expect(derived.dispose, returnsNormally);
    });
  });
}
