// ignore_for_file: lines_longer_than_80_chars

part of 'stores.dart';

/// Агрегат статистики по задачам.
///
/// Возвращается [TodosDerivedImpl.todoStats]. Immutable value-тип — данные, а
/// не стор, поэтому живёт рядом с derived-селектором, который его вычисляет.
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
  String toString() =>
      'TodoStats(total=$total, active=$active, done=$done, overdue=$overdue)';
}

/// Derived-стор: агрегаты и селекторы над корневым [AppStoreImpl].
///
/// В отличие от рукописных `computed`-селекторов (бывший `ui/derived.dart`),
/// derived-стор — полноценный стор: его computed-геттеры эмитит генератор из
/// `@DerivedStore`. Корень резолвится через `StoreRootScope.of<AppStoreImpl>()`
/// при каждом обращении, поэтому derived всегда видит актуальный корень (в т.ч.
/// после его пересоздания). Создаётся on-demand там, где нужен
/// (`TodosDerived()`), без ручной проброски стора.
///
/// Логика селекторов перенесена из бывшего рукописного `Derived` (фильтрация,
/// сортировка, статистика) — генератор оборачивает её в `Computed`, поэтому
/// чтение геттеров мемоизировано и реактивно (через `Watch`/`SignalBuilder`).
///
/// Живёт в той же библиотеке, что и корневой стор (`part of 'stores.dart'`),
/// чтобы генератор видел `AppStoreImpl` помеченным `root: true` при валидации
/// типизации root-геттера (разрешение имён — per-library).
@DerivedStore(name: 'TodosDerived')
abstract class TodosDerivedImpl {
  /// Корень дерева сторов. Bodyless-геттер: генератор эмитит реализацию через
  /// `StoreRootScope.of<AppStoreImpl>()`. НЕ `abstract AppStoreImpl get root;`
  /// (с `abstract` это невалидный Dart в контексте codegen-контракта).
  AppStoreImpl get root;

  /// Отфильтрованный + отсортированный список задач.
  ///
  /// Читает `root.ui.filter.*` и `root.projects.todos.*` — реактивные поля,
  /// поэтому селектор пересчитывается при изменении фильтра или коллекции задач.
  List<Todo> get visibleTodos {
    final filter = root.ui.filter;
    var list = root.projects.todos.values.toList();

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

  /// Агрегированная статистика по всем задачам (всего/активно/готово/просрочено).
  TodoStats get todoStats {
    final now = DateTime.now();
    var total = 0;
    var done = 0;
    var overdue = 0;
    for (final t in root.projects.todos.values) {
      total++;
      if (t.isDone) {
        done++;
      } else {
        if (t.dueDate != null && t.dueDate!.isBefore(now)) overdue++;
      }
    }
    return TodoStats(
      total: total,
      active: total - done,
      done: done,
      overdue: overdue,
    );
  }

  /// Текущий выбранный проект (`null` — все проекты).
  Project? get activeProject {
    final id = root.projects.currentProjectId;
    if (id == null) return null;
    return root.projects.projects[id];
  }

  /// Аутентифицирован ли пользователь.
  bool get isAuthenticated => root.session.currentUser != null;
}
