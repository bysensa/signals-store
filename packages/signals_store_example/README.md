# signals_store_example — Tasker

Полноценный Flutter-пример, демонстрирующий архитектуру управления состоянием на
базе [`signals_store`](../signals_store) и генератора
[`signals_store_generator`](../signals_store_generator), вдохновлённую
[overmind](https://overmindjs.org/).

Это менеджер задач «Tasker»: проекты, задачи с приоритетом/дедлайном/тегами,
фильтрация, сортировка, статистика и аутентификация.

## Архитектурные принципы

Пример иллюстрирует четыре принципа из ТЗ:

1. **Глобальный стор с вложенными сторами** (overmind-style). Корневой `AppStore`
   — композиция подсторов `SessionStore` / `ProjectsStore` / `TagsStore` /
   `UiStore`, каждый из которых — `@Store`-сгенерированный класс.
2. **Сторы не содержат внешних зависимостей** (репозиториев). В сторах только
   данные; репозитории передаются параметрами в UseCase и Actions.
3. **UseCase — `extension type` стора**. Мутабельные операции реализованы как
   `extension type CreateTodo(AppStore state) { invoke({... , TodosRepo repo}) }`.
   Внешние зависимости передаются параметрами `invoke`.
4. **Intent + `ContextAction<T extends Intent>`** для действий пользователя.
   Action оркестрирует: навигация/диалоги через `BuildContext` + вызов UseCase.

### Структура

```
lib/
  main.dart                      # bootstrap: дерево сторов + репозитории
  domain/
    enums.dart                   # Priority, TodoSortBy
    models.dart                  # User, Project, Todo, Tag, TodoDraft
    stores.dart + stores.g.dart  # @Store-описания (codegen)
  usecases/                      # extension type AppStore
    auth_usecases.dart           # Login, Logout
    init_usecases.dart           # LoadInitialData
    todo_usecases.dart           # CreateTodo, ToggleTodo, DeleteTodo
    project_usecases.dart        # CreateProject, SelectProject
    tag_usecases.dart            # CreateTag
    filter_usecases.dart         # Set*Filter, ToggleHideDone, SetSortBy, ResetFilter
    ui_usecases.dart             # ShowSnackbar, ClearSnackbar
  intents/intents.dart           # все Intent-классы
  actions/actions.dart           # все ContextAction<T> + buildActions()
  data/fake_repos.dart           # AuthRepo, ProjectsRepo, TodosRepo, TagsRepo
  ui/
    app.dart                     # корень: Actions widget + snackbar биндинг
    derived.dart                 # computed-селекторы (часть UI-слоя)
    login_screen.dart
    home_screen.dart             # Scaffold + drawer (проекты) + todo list
    widgets/
      todo_list_tile.dart
      filter_bar.dart
      stats_card.dart
      create_todo_dialog.dart
      filter_dialog.dart
      create_project_dialog.dart
```

### Ключевая идея: модель полей генератора

`@Store` различает два вида полей:

- **`abstract`-поля** → реактивные через `Signal` (подписка в `effect`/`Watch`/
  `SignalBuilder`).
- **concrete-поля** (`final X x;`) → pass-through (`required super.x`). Это
  стабильные ссылки, например вложенные сторы — их реактивность обеспечивается
  собственными `Signal`-полями.

Так корневой `AppStore` держит подсторы как concrete-ссылки: `appStore.session`
типизирован конкретным `SessionStore`, чьи `currentUser`/`isLoading`/`error`
полноценно реактивны.

### Реактивные коллекции (`MapSignal`)

Поля-коллекции (`projects`, `todos`, `tags`) объявлены как concrete-поля типа
`MapSignal<K,V>` (из `package:signals/signals.dart`) и инициализируются через
`mapSignal<K,V>({})`. Так in-place-мутации (`store.projects.todos[id] = todo`,
`.remove(id)`) автоматически триггерят обновления UI/computed — без ручного
полного переопределения Map в каждом UseCase.

```dart
@Store(name: 'ProjectsStore')
abstract class ProjectsStoreImpl {
  final MapSignal<String, Project> projects;   // реактивная коллекция
  final MapSignal<String, Todo> todos;          // реактивная коллекция
  abstract String? currentProjectId;            // реактивный скаляр
  ProjectsStoreImpl({required this.projects, required this.todos});
}
```

> ⚠️ **Ограничение signals 7.1.0:** мутации `MapSignal` внутри `batch()` НЕ
> доходят до `computed`/`effect` (подтверждено минимальным тестом). Поэтому в
> UseCase-мутациях коллекций `batch()` не используется — только для скалярных
> полей. См. регрессионный тест `in-place MapSignal mutations ... fire reactive
> updates` в `test/architecture_test.dart`.

## Запуск

```sh
cd packages/signals_store_example
flutter pub get
flutter pub run build_runner build   # (пере)генерация stores.g.dart
flutter run
```

Тестовые аккаунты (фейковые):

- `alice@example.com` / `secret`
- `bob@example.com` / `hunter2`

## Сценарий

1. Логин → `LoginIntent` → `Login` UseCase (`AuthRepo`) + `LoadInitialData`
   (три репозитория параллельно) → навигация на главный экран.
2. Список задач с приоритетами/тегами/дедлайнами, статистика (`StatsCard` через
   computed `todoStats`), drawer с проектами.
3. Фильтрация (`ShowFilterDialogIntent` → диалог → `SetPriorityFilterIntent` /
   `ToggleHideDoneIntent` / `SetSortByIntent`) + сортировка → `visibleTodos`
   пересчитывается реактивно.
4. Создание задачи: `ShowCreateTodoDialogIntent` → `showDialog` →
   `CreateTodoIntent` → `CreateTodo` UseCase (`TodosRepo`) → SnackBar.
5. Toggle / delete (смахивание) → UseCase → список и статистика обновляются
   реактивно.
6. Смена проекта в drawer, logout.

## Тесты

```sh
flutter test                # архитектурные + widget-тесты
```

Покрывают: типобезопасность и реактивность сторов, UseCase-мутации (с
репозиторием-параметром и без), пересчёт computed-селекторов и end-to-end
логин через UI.
