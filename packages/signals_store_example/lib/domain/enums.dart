/// Enum'ы домена Tasker.
library;

/// Приоритет задачи.
enum Priority {
  low('Низкий'),
  medium('Средний'),
  high('Высокий');

  const Priority(this.label);

  final String label;

  /// Числовой вес для сортировки (выше приоритет → больше вес).
  int get weight => switch (this) {
        Priority.low => 0,
        Priority.medium => 1,
        Priority.high => 2,
      };
}

/// Способ сортировки списка задач.
enum TodoSortBy {
  createdDesc('Сначала новые'),
  dueDateAsc('Сначала срочные'),
  priorityDesc('По приоритету'),
  titleAsc('По названию');

  const TodoSortBy(this.label);

  final String label;
}
