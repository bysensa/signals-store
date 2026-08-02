# Tasker — сложный example для signals_store

**Дата:** 2026-08-02
**Статус:** Approved
**Пакет:** `packages/signals_store_example/`

## Цель

Создать сложный, end-to-end пример, демонстрирующий работу библиотеки
`signals_store` и генератора `signals_store_generator` по архитектуре,
вдохновлённой [overmind](https://overmindjs.org/): глобальный стор с
вложенными подсторами, UseCase как `extension type` стора, слой Intent +
`ContextAction<T extends Intent>` для обработки действий пользователя.

## Принятые решения

| Решение | Выбор | Обоснование |
|---|---|---|
| Формат | Flutter-приложение | Показывает UI, навигацию, диалоги, реактивность |
| Домен | Менеджер задач «Tasker» (сложный) | Проекты, приоритеты, теги, фильтры, статистика, auth |
| Intent/Action | Встроенный `Intent` + `ContextAction<T extends Intent>` Flutter | Идиоматично, контекст в `invoke` для Navigator/dialog |
| UseCase target | Корневой `AppStore` | Совпадает с ТЗ (`CreateUser(GlobalState state)`) |
| Сторы | `@Store(name:)` codegen | Типобезопасно, без бойлерплейта, рекламирует генератор |
| Реактивность UI | `Watch` из `package:signals/flutter.dart` | Стандарт signals v7 для Flutter |

## Нефункциональные требования (из ТЗ)

1. **Сторы не содержат внешних зависимостей** (репозиториев). В сторах только данные.
2. **UseCase — `extension type` стора.** Внешние зависимости передаются параметрами `invoke`:
   ```dart
   extension type CreateTodo(AppStore state) {
     Future<void> invoke({required String title, required TodosRepo todosRepo}) async { ... }
   }
   ```
3. **Intent + Action для действий пользователя.** Action содержит логику навигации/диалогов
   и вызывает UseCase, передавая параметры и зависимости.
4. **Глобальный стор с вложенными сторами** в стиле overmind.

## Архитектура

### Домен и модель данных

Сущности (иммутабельные value-types — данные в `Map` сторов, не сторы):

- **`User`** — `{id, name, email}`
- **`Project`** — `{id, name, color}`
- **`Tag`** — `{id, label, color}`
- **`Todo`** — `{id, title, projectId, priority, dueDate?, isDone, Set<Tag> tags, createdAt}`
- **`TodoDraft`** — черновик из диалога создания (title, projectId, priority, dueDate, tagIds)
- Enums: **`Priority {low, medium, high}`**, **`TodoSortBy {createdDesc, dueDateAsc, priorityDesc, titleAsc}`**

Данные хранятся **нормализованно** — `Map<String, T>` по id, как завещает overmind
(references вместо дублирования объектов). `currentProjectId`/`currentUser` — id-ссылки.

### Сторы (`lib/domain/stores.dart`)

Все сторы через `@Store(name:)` codegen (`part 'stores.g.dart';`). Корневой `AppStore`
— композиция вложенных сторов.

**Модель полей генератора** (уточнена в процессе реализации):

- `abstract`-поля → реактивные через `Signal` (приватное `_<field>$`, геттер/сеттер).
- concrete-поля (`final X x;`) → pass-through (`required super.x`), без Signal-обёртки.

Это позволяет вкладывать сторы как **стабильные** concrete-ссылки: их собственные
`abstract`-поля реактивны, а на уровне корня лишний Signal не нужен. Поля
вложенных сторов типизируются **суперклассом-описанием** (`SessionStoreImpl`),
а генератор переписывает тип на имя реализации (`SessionStore`).

```dart
@Store(name: 'SessionStore')
abstract class SessionStoreImpl {
  abstract User? currentUser;
  abstract bool isLoading;
  abstract String? error;
}

@Store(name: 'ProjectsStore')
abstract class ProjectsStoreImpl {
  abstract Map<String, Project> projects;
  abstract Map<String, Todo> todos;
  abstract String? currentProjectId;
}

@Store(name: 'TagsStore')
abstract class TagsStoreImpl {
  abstract Map<String, Tag> tags;
}

@Store(name: 'TodoFilter')
abstract class TodoFilterImpl {
  abstract String? projectFilterId;
  abstract Priority? priorityFilter;
  abstract bool hideDone;
  abstract TodoSortBy sortBy;
}

@Store(name: 'UiStore')
abstract class UiStoreImpl {
  final TodoFilterImpl filter;     // concrete — стабилен
  abstract bool isBusy;
  abstract String? snackbarMessage;
  UiStoreImpl({required this.filter});
}

@Store(name: 'AppStore')
abstract class AppStoreImpl {
  final SessionStoreImpl session;   // concrete — стабильные ссылки
  final ProjectsStoreImpl projects;
  final TagsStoreImpl tags;
  final UiStoreImpl ui;
  AppStoreImpl({required this.session, required this.projects,
                required this.tags, required this.ui});
}
```

Сторы **не** держат репозитории.

#### Реактивные коллекции (`MapSignal`)

Поля-коллекции (`projects`, `todos`, `tags`) объявлены как concrete-поля типа
`MapSignal<K,V>` и инициализируются через `mapSignal<K,V>({})`. Так in-place-
мутации (`store.projects.todos[id] = todo`, `.remove(id)`) автоматически
триггерят обновления — без ручного полного переопределения Map в каждом UseCase.

> ⚠️ **Ограничение signals 7.1.0:** мутации `MapSignal` внутри `batch()` НЕ
> доходят до `computed`/`effect` (подтверждено минимальным тестом). Поэтому в
> UseCase-мутациях коллекций `batch()` не используется — только для скаляров.
> См. регрессионный тест `in-place MapSignal mutations ... fire reactive
> updates`.

### Derived-стейт (UI-слой)

Селекторы (computed) — часть UI-слоя, т.к. отвечают на вопрос «как отобразить
данные», а не «что хранить». Живут в `lib/ui/derived.dart`. Создаются один раз
на инстанс `AppStore` (`Derived.of(store)`), переиспользуются во всём UI через
`Watch`:

- `visibleTodos` — отфильтрованный + отсортированный `List<Todo>` по `ui.filter`
- `todoStats` — total/active/done/overdue counts
- `todosByPriority` — breakdown по приоритетам
- `activeProject` — `Project?` по `projects.currentProjectId`
- `isAuthenticated` — `session.currentUser != null`
- `visibleTags` — `List<Tag>`

### UseCase-слой (`lib/usecases/`)

UseCase — `extension type X(AppStore state)` с методом `invoke`. Внешние зависимости —
параметры `invoke`. Мутации оборачиваются в `batch(() {...})`.

| UseCase | Файл | Repo (внеш.) | Мутирует |
|---|---|---|---|
| `Login` | `auth_usecases.dart` | `AuthRepo` | `session` |
| `Logout` | `auth_usecases.dart` | — | `session` |
| `LoadInitialData` | `init_usecases.dart` | `ProjectsRepo, TodosRepo, TagsRepo` | `projects, tags` |
| `CreateTodo` | `todo_usecases.dart` | `TodosRepo` | `projects.todos` |
| `ToggleTodo` | `todo_usecases.dart` | — | `projects.todos[id]` |
| `DeleteTodo` | `todo_usecases.dart` | `TodosRepo` | `projects.todos` |
| `CreateProject` | `project_usecases.dart` | `ProjectsRepo` | `projects.projects` |
| `CreateTag` | `tag_usecases.dart` | `TagsRepo` | `tags.tags` |
| `SetProjectFilter`, `SetPriorityFilter`, `ToggleHideDone`, `SetSortBy` | `filter_usecases.dart` | — | `ui.filter` |
| `ShowSnackbar`, `ClearSnackbar` | `ui_usecases.dart` | — | `ui.snackbarMessage` |

### Intent + Action (`lib/intents/`, `lib/actions/`)

`Intent` — встроенный Flutter (`package:flutter/widgets.dart`), несёт параметры.
`Action` — `ContextAction<T extends Intent>` (контекст в `invoke` для Navigator/dialog).
Action оркестрирует: UI-сайд-эффекты через `context` + вызов UseCase с зависимостями.

Intents → UseCase/эффект (однозначное сопоставление):

- `LoginIntent` → `Login` + `LoadInitialData`
- `LogoutIntent` → `Logout`
- `CreateTodoIntent` → `CreateTodo`
- `ShowCreateTodoDialogIntent` → `showDialog` → дочерний `CreateTodoIntent`
- `ToggleTodoIntent` → `ToggleTodo`
- `DeleteTodoIntent` → `DeleteTodo`
- `OpenProjectIntent` → `SetProjectFilter` (projectId из интента)
- `ShowFilterDialogIntent` → `showDialog` → дочерние `SetPriorityFilterIntent`/`ToggleHideDoneIntent`/`SetSortByIntent`
- `CreateProjectIntent` → `CreateProject`
- `CreateTagIntent` → `CreateTag`

Все Actions собираются в `Map<Type, Action<Intent>> buildActions(AppStore, Repos)` и
регистрируются одним `Actions` widget в корне. UI запускает через `Actions.invoke(context, SomeIntent(...))`.

### Фейковые репозитории (`lib/data/fake_repos.dart`)

In-memory реализации с искусственной задержкой (`Future.delayed`), имитируют сеть:

- `AuthRepo` — `Future<User> login(email, password)`, `Future<void> logout()`
- `ProjectsRepo` — `Future<List<Project>> fetchAll()`, `Future<Project> add(name, color)`
- `TodosRepo` — `Future<List<Todo>> fetchAll()`, `Future<Todo> add(draft)`, `Future<void> remove(id)`, `Future<void> update(todo)`
- `TagsRepo` — `Future<List<Tag>> fetchAll()`, `Future<Tag> add(label, color)`

Передаются в UseCase/Action как параметры. В сторы **не** попадают.

### Структура Flutter-UI

```
lib/
  main.dart                      # bootstrap: repos, store, Actions-корень, MaterialApp
  domain/
    enums.dart                   # Priority, TodoSortBy
    models.dart                  # User, Project, Todo, Tag, TodoDraft
    stores.dart + stores.g.dart  # @Store-описания (codegen)
  usecases/                      # extension type AppStore (см. таблицу)
  intents/intents.dart           # все Intent-классы
  actions/actions.dart           # все ContextAction<T> + buildActions()
  data/fake_repos.dart
  ui/
    app.dart                     # корень с Actions widget + snackbar биндинг
    derived.dart                 # computed-селекторы (часть UI-слоя)
    login_screen.dart
    home_screen.dart             # Scaffold + drawer (проекты) + body (todo list)
    widgets/
      todo_list_tile.dart
      filter_bar.dart
      stats_card.dart
      create_todo_dialog.dart
      filter_dialog.dart
```

Реактивность: `Watch` (signals/flutter) — чтение полей стора внутри `Watch` builder
автоматически перерисовывает при изменении.

## Сценарий демо

1. Логин (фейковый email/password) → `LoginIntent` → `Login` UseCase (`AuthRepo`) →
   `LoadInitialData` (`ProjectsRepo, TodosRepo, TagsRepo`) → навигация на `HomeScreen`.
2. Список задач по проекту, статистика (через `todoStats`), теги, приоритеты, дедлайны.
3. Фильтрация (`ShowFilterDialogIntent` → диалог → `SetPriorityFilterIntent` и т.д.) +
   сортировка → `visibleTodos` пересчитывается реактивно.
4. Создание задачи: `ShowCreateTodoDialogIntent` → `showDialog` → `CreateTodoIntent`
   → `CreateTodo` UseCase (`TodosRepo`) → snackbar.
5. Toggle/delete → `ToggleTodoIntent`/`DeleteTodoIntent` → UseCase → список и статистика
   обновляются реактивно.
6. Смена проекта в drawer (`OpenProjectIntent`), logout.

## Верификация

- `dart run build_runner build` (или `flutter pub run build_runner build`) — успешно.
- `flutter analyze` — без errors/warnings.
- `flutter test` (или `dart test`) — smoke-тесты сторов/usecases/intents зелёные.
- Приложение запускается и интерактивно работает (логин/создание/фильтрация/logout).

## Ограничения / Open questions

Нет открытых вопросов — все ключевые развилки закрыты в процессе брейншторма.
