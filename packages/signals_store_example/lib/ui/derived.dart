import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/stores.dart';
import 'package:signals/signals.dart';

/// Селекторы (derived state) — часть UI-слоя.
///
/// Derived-стейт отвечает на вопрос «как отобразить данные», а не «что хранить»,
/// поэтому живёт рядом с виджетами, а не в домене. Каждый селектор — это
/// [Computed] на основе `computed(...)` из signals, который лениво
/// пересчитывается только при изменении затронутых полей сторов. Доступ к полям
/// стор-генерированных классов (`store.projects.todos`,
/// `store.ui.filter.sortBy`, ...) читает `.value` внутренних сигналов, поэтому
/// отслеживание зависимостей внутри `computed` работает автоматически.
///
/// Селекторы создаются один раз на инстанс [AppStore] (см. `Derived.of`).
/// В UI используются через `Watch` — чтение `.value` перерисовывает виджет при
/// изменении любой зависимости.

/// Агрегат статистики по задачам.
class TodoStats {
  const TodoStats({
    required this.total,
    required this.active,
    required this.done,
    required this.overdue,
  });

  final int total;
  final int active;
  final int done;
  final int overdue;

  @override
  String toString() => 'TodoStats(total=$total, active=$active, done=$done, '
      'overdue=$overdue)';
}

/// Пучок (bundle) computed-селекторов для конкретного [AppStore].
///
/// Создаётся один раз через [Derived.of] и переиспользуется во всём UI.
class Derived {
  Derived._(this.s)
      : visibleTodos = computed(() => _computeVisibleTodos(s)),
        todoStats = computed(() => _computeStats(s)),
        todosByPriority = computed(() => _computeByPriority(s)),
        activeProject = computed(() => _computeActiveProject(s)),
        isAuthenticated = computed(() => s.session.currentUser != null),
        visibleTags = computed(() => s.tags.tags.values.toList()
          ..sort((a, b) => a.label.compareTo(b.label)));

  final AppStore s;

  /// Отфильтрованный + отсортированный список задач.
  final ReadonlySignal<List<Todo>> visibleTodos;

  /// Агрегированная статистика по всем задачам.
  final ReadonlySignal<TodoStats> todoStats;

  /// Распределение активных (невыполненных) задач по приоритетам.
  final ReadonlySignal<Map<Priority, int>> todosByPriority;

  /// Текущий выбранный проект (`null` — все проекты).
  final ReadonlySignal<Project?> activeProject;

  /// Аутентифицирован ли пользователь.
  final ReadonlySignal<bool> isAuthenticated;

  /// Все теги, отсортированные по подписи.
  final ReadonlySignal<List<Tag>> visibleTags;

  /// Создаёт пучок селекторов для [store]. Вызывать один раз на инстанс стора.
  factory Derived.of(AppStore store) => Derived._(store);

  static List<Todo> _computeVisibleTodos(AppStore s) {
    final filter = s.ui.filter;
    var list = s.projects.todos.values.toList();

    if (filter.projectFilterId != null) {
      list = list.where((t) => t.projectId == filter.projectFilterId).toList();
    }
    if (filter.priorityFilter != null) {
      list = list.where((t) => t.priority == filter.priorityFilter).toList();
    }
    if (filter.hideDone) {
      list = list.where((t) => !t.isDone).toList();
    }

    switch (filter.sortBy) {
      case TodoSortBy.createdDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case TodoSortBy.dueDateAsc:
        // Без дедлайна — в конце списка.
        list.sort((a, b) {
          final ad = a.dueDate;
          final bd = b.dueDate;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
      case TodoSortBy.priorityDesc:
        list.sort((a, b) => b.priority.weight.compareTo(a.priority.weight));
      case TodoSortBy.titleAsc:
        list.sort((a, b) => a.title.compareTo(b.title));
    }

    return list;
  }

  static TodoStats _computeStats(AppStore s) {
    final now = DateTime.now();
    var total = 0;
    var done = 0;
    var overdue = 0;
    for (final t in s.projects.todos.values) {
      total++;
      if (t.isDone) {
        done++;
      } else {
        if (t.dueDate != null && t.dueDate!.isBefore(now)) overdue++;
      }
    }
    return TodoStats(total: total, active: total - done, done: done, overdue: overdue);
  }

  static Map<Priority, int> _computeByPriority(AppStore s) {
    final counts = {for (final p in Priority.values) p: 0};
    for (final t in s.projects.todos.values) {
      if (!t.isDone) counts[t.priority] = counts[t.priority]! + 1;
    }
    return counts;
  }

  static Project? _computeActiveProject(AppStore s) {
    final id = s.projects.currentProjectId;
    if (id == null) return null;
    return s.projects.projects[id];
  }
}
