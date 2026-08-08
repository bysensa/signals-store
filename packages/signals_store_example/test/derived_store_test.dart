// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:signals_store/signals_store.dart';

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

  AppStore newStore() => AppStore(
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
      final app = newStore(); // авторегистрируется в test-окружение
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
      newStore();
      final derived = TodosDerived();
      expect(derived.dispose, returnsNormally);
    });

    // D1: двойной dispose идемпотентен (signals dispose идемпотентны — проверено
    // эмпирически; повторный вызов не должен падать).
    test('double dispose is idempotent', () {
      newStore();
      final derived = TodosDerived();
      derived.dispose();
      expect(derived.dispose, returnsNormally);
    });
  });
}
