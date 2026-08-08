// ignore_for_file: lines_longer_than_80_chars

part of 'stores.dart';

/// Демонстрация сложного сценария `@DerivedStore`: on-demand стейт экрана
/// деталей задачи.
///
/// В отличие от [TodosDerivedImpl] (глобальные агрегаты), этот derived-стор
/// моделирует **экран** из стека навигации: создаётся при открытии экрана,
/// уничтожается при закрытии (`dispose`). Демонстрирует одновременно:
///
/// 1. **Параметр создания как reactive-поле** — `todoId` пробрасывается в
///    конструктор и становится Signal-полем (можно менять без пересоздания).
/// 2. **Собственное mutable-состояние** — `isEditing` (режим редактирования),
///    не зависящее от корня.
/// 3. **Computed, читающий корень через StoreRootScope** — `todo` резолвит
///    задачу по `todoId` из `root.projects.todos`.
/// 4. **Кросс-слайсные computed** — `project` и `tags` вычисляются через две
///    разные ветки дерева (`projects` и `tags`).
/// 5. **Derived-в-derived-композиция внутри одного стора** — `relatedTodos`
///    использует результат `todo`/`project` (через фикс-пойнт детектора).
/// 6. **Guard-ы на отсутствие данных** — задача могла быть удалена из корня
///    после открытия экрана → computed возвращают `null`/пусто.
///
/// Использование (например, в `State<TodoDetailsScreen>`):
///
/// ```dart
/// late final store = TodoDetailsStore(todoId: widget.todoId);
/// @override
/// void dispose() { store.dispose(); super.dispose(); }
/// // Watch((_) => Text(store.todo?.title ?? 'не найдено'))
/// ```
@DerivedStore(name: 'TodoDetailsStore')
abstract class TodoDetailsStoreImpl {
  /// Корень дерева сторов. Bodyless-геттер: генератор эмитит реализацию через
  /// `StoreRootScope.of<AppStoreImpl>()` — резолв при каждом обращении, поэтому
  /// экран всегда видит актуальный корень (в т.ч. после перелогина).
  AppStoreImpl get root;

  /// Id задачи — параметр создания. Reactive-поле (Signal): экран может
  /// сменить задачу без пересоздания стора (`store.todoId = 'other'`).
  abstract String todoId;

  /// Собственное состояние экрана: режим редактирования. Не зависит от корня —
  /// демонстрирует, что derived-стор это полноценный стор, а не только селекторы.
  abstract bool isEditing;

  /// Текущая задача из корня по [todoId]. `null`, если удалена после открытия.
  Todo? get todo => root.projects.todos[todoId];

  /// Проект задачи — кросс-слайс через `todo` → `root.projects.projects`.
  /// `null`, если задача или проект не найдены.
  Project? get project {
    final t = todo;
    if (t == null) return null;
    return root.projects.projects[t.projectId];
  }

  /// Полные теги задачи — кросс-слайс через `todo.tagIds` → `root.tags.tags`.
  /// Нормализованные id резолвятся в объекты [Tag].
  List<Tag> get tags {
    final t = todo;
    if (t == null) return const [];
    return [
      for (final tagId in t.tagIds)
        if (root.tags.tags[tagId] case final tag?) tag,
    ];
  }

  /// Связанные задачи того же проекта (кроме текущей), отсортированные по
  /// приоритету. Демонстрирует композицию computed-геттеров: читает [todo] и
  /// [project] — детектор реактивности помечает его computed через фикс-пойнт
  /// (зависимость от reactive-геттеров, которые сами reactive).
  List<Todo> get relatedTodos {
    final t = todo;
    final p = project;
    if (t == null || p == null) return const [];
    final related = root.projects.todos.values
        .where((other) => other.projectId == p.id && other.id != t.id)
        .toList()
      ..sort((a, b) => b.priority.weight.compareTo(a.priority.weight));
    return related;
  }

  /// Заголовок экрана: «<проект> · <задача>» или fallback, если данных нет.
  String get headerTitle {
    final t = todo;
    if (t == null) return 'Задача не найдена';
    final p = project;
    return p == null ? t.title : '${p.name} · ${t.title}';
  }

  /// Можно ли сохранять правки: только в режиме редактирования и когда задача
  /// существует в корне. Композиция собственного состояния и корня.
  bool get canSave => isEditing && todo != null;
}
