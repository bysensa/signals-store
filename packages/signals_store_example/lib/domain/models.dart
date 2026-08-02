import 'enums.dart';

/// Иммутабельные value-типы домена Tasker.
///
/// Это данные, которые хранятся в нормализованных `Map`'ах сторов — не сторы.
/// Сторы (`*Store`-классы) живут в `stores.dart` и содержат только данные,
/// без репозиториев.

/// Аутентифицированный пользователь.
class User {
  const User({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  @override
  bool operator ==(Object other) =>
      other is User && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'User($email)';
}

/// Проект (категория задач).
class Project {
  const Project({required this.id, required this.name, required this.colorValue});

  final String id;
  final String name;

  /// Цвет проекта как 0xAARRGGBB int (хранится как данное, не как Color,
  /// чтобы модель не зависела от Flutter/dart:ui).
  final int colorValue;

  @override
  bool operator ==(Object other) =>
      other is Project && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Project($name)';
}

/// Тег задачи.
class Tag {
  const Tag({required this.id, required this.label, required this.colorValue});

  final String id;
  final String label;
  final int colorValue;

  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Tag(#$label)';
}

/// Задача.
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.projectId,
    required this.priority,
    required this.dueDate,
    required this.isDone,
    required this.tagIds,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String projectId;
  final Priority priority;

  /// Дедлайн. `null` — без дедлайна.
  final DateTime? dueDate;

  final bool isDone;

  /// Id тегов, привязанных к задаче (ссылки на `TagsStore.tags`).
  final Set<String> tagIds;

  final DateTime createdAt;

  /// Копия с переопределёнными полями.
  Todo copyWith({
    String? title,
    bool? isDone,
    Priority? priority,
    DateTime? dueDate,
    Set<String>? tagIds,
  }) {
    return Todo(
      id: id,
      title: title ?? this.title,
      projectId: projectId,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      isDone: isDone ?? this.isDone,
      tagIds: tagIds ?? this.tagIds,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) => other is Todo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Todo($title${isDone ? ' ✓' : ''})';
}

/// Черновик задачи из диалога создания.
///
/// Передаётся из UI-диалога в `CreateTodoIntent` и далее в `CreateTodo` UseCase.
class TodoDraft {
  const TodoDraft({
    required this.title,
    required this.projectId,
    required this.priority,
    required this.dueDate,
    required this.tagIds,
  });

  final String title;
  final String projectId;
  final Priority priority;
  final DateTime? dueDate;
  final Set<String> tagIds;
}

/// Палитра цветов проектов/тегов (int-значения).
abstract final class TaskerColors {
  static const List<int> projectPalette = [
    0xFFEF5350, // red
    0xFF42A5F5, // blue
    0xFF66BB6A, // green
    0xFFFFCA28, // amber
    0xFFAB47BC, // purple
    0xFF26C6DA, // cyan
  ];

  static const List<int> tagPalette = [
    0xFF7E57C2,
    0xFFEC407A,
    0xFF5C6BC0,
    0xFF26A69A,
    0xFFFF7043,
  ];
}
