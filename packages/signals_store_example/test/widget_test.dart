// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:signals_store_example/data/fake_repos.dart';
import 'package:signals_store_example/domain/enums.dart';
import 'package:signals_store_example/domain/models.dart';
import 'package:signals_store_example/domain/stores.dart';
import 'package:signals_store_example/ui/app.dart';

/// Widget-тест: приложение рендерит экран входа и реагирует на корректный логин.
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
  testWidgets('shows login screen and logs in with seed credentials',
      (tester) async {
    final store = _freshStore();
    final repos = Repos.defaults();

    await tester.pumpWidget(TaskerApp(store: store, repos: repos));

    // На стартовом экране — поле входа.
    expect(find.text('Войти в Tasker'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));

    // Тестовые креды уже предзаполнены (alice@example.com / secret).
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pump(); // запускает async login + load.

    // Даём выполниться фейк-задержкам репозиториев (login 600ms + load ~500ms).
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // После успешного логина — сессия установлена и данные загружены
    // (сидер TodosRepo = 4 задачи).
    expect(store.session.currentUser, isNotNull);
    expect(store.projects.todos.length, 4);
    // На главном экране присутствует FAB создания задачи.
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  // Регрессия: диалоги показываются в Overlay Navigator'а, который НЕ является
  // потомком `MaterialApp.home`. Раньше `Actions` лежал внутри `home`, и
  // `Actions.invoke(context, ...)` из диалога падал с "Unable to find an
  // action". Теперь `Actions` оборачивает весь `MaterialApp`.
  testWidgets(
      'filter dialog can invoke intents (Actions reachable from overlay)',
      (tester) async {
    final store = _freshStore();
    final repos = Repos.defaults();

    await tester.pumpWidget(TaskerApp(store: store, repos: repos));
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Открываем диалог фильтра (через appBar action или FilterBar).
    await tester.tap(find.byTooltip('Фильтр'));
    await tester.pumpAndSettle();
    expect(find.text('Фильтр и сортировка'), findsOneWidget);

    // Переключаем приоритет через ChoiceChip — это вызывает
    // SetPriorityFilterIntent из контекста диалога (overlay). Не должно падать.
    await tester.tap(find.text('Высокий'));
    await tester.pumpAndSettle();

    // Intent отработал → стор обновился.
    expect(store.ui.filter.priorityFilter?.label, 'Высокий');

    // Закрываем диалог.
    await tester.tap(find.widgetWithText(FilledButton, 'Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Фильтр и сортировка'), findsNothing);
  });
}
