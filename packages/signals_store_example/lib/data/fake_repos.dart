import 'dart:async';

import '../domain/enums.dart';
import '../domain/models.dart';

/// Фейковые репозитории — имитируют сетевые запросы с искусственной задержкой.
///
/// **Важно по архитектуре:** репозитории — внешние зависимости. Они НЕ хранятся
/// в сторах. Они передаются параметрами в методы `invoke` UseCase (см.
/// `lib/usecases/`) и в конструкторы `ContextAction` (см. `lib/actions/`).
/// Так сторы остаются чистыми данными, а внешние зависимости легко мокаются в
/// тестах.

/// Генератор уникальных id (достаточно для примера; не криптостойкий).
String _uuid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${identityHashCode(Object()).toRadixString(36)}';

/// Репозиторий аутентификации.
class AuthRepo {
  /// Известные пользователи (email → пароль).
  static const Map<String, ({String password, String name})> _users = {
    'alice@example.com': (password: 'secret', name: 'Алиса'),
    'bob@example.com': (password: 'hunter2', name: 'Боб'),
  };

  /// Возвращает пользователя при корректных кредах, иначе бросает [AuthException].
  Future<User> login({required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final entry = _users[email];
    if (entry == null || entry.password != password) {
      throw AuthException('Неверный email или пароль');
    }
    return User(id: _uuid(), name: entry.name, email: email);
  }

  Future<void> logout() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// Ошибка аутентификации.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Репозиторий проектов.
class ProjectsRepo {
  final Map<String, Project> _store = {};

  /// Начальные проекты при первом обращении.
  static const List<Project> _seed = [
    Project(id: 'p1', name: 'Личное', colorValue: 0xFF42A5F5),
    Project(id: 'p2', name: 'Работа', colorValue: 0xFFEF5350),
    Project(id: 'p3', name: 'Учёба', colorValue: 0xFF66BB6A),
  ];

  Future<List<Project>> fetchAll() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_store.isEmpty) {
      for (final p in _seed) {
        _store[p.id] = p;
      }
    }
    return _store.values.toList();
  }

  Future<Project> add({required String name, required int colorValue}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final p = Project(id: _uuid(), name: name, colorValue: colorValue);
    _store[p.id] = p;
    return p;
  }
}

/// Репозиторий тегов.
class TagsRepo {
  final Map<String, Tag> _store = {};

  static const List<Tag> _seed = [
    Tag(id: 't1', label: 'срочно', colorValue: 0xFFEF5350),
    Tag(id: 't2', label: 'идея', colorValue: 0xFFAB47BC),
    Tag(id: 't3', label: 'дом', colorValue: 0xFF26C6DA),
  ];

  Future<List<Tag>> fetchAll() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_store.isEmpty) {
      for (final t in _seed) {
        _store[t.id] = t;
      }
    }
    return _store.values.toList();
  }

  Future<Tag> add({required String label, required int colorValue}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final t = Tag(id: _uuid(), label: label, colorValue: colorValue);
    _store[t.id] = t;
    return t;
  }
}

/// Репозиторий задач.
class TodosRepo {
  final Map<String, Todo> _store = {};

  /// Начальные задачи (ссылаются на seeded-проекты и теги).
  List<Todo> get _seed {
    final now = DateTime.now();
    return [
      Todo(
        id: 'td1',
        title: 'Прочитать книгу',
        projectId: 'p1',
        priority: Priority.low,
        dueDate: null,
        isDone: false,
        tagIds: const {'t2'},
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      Todo(
        id: 'td2',
        title: 'Подготовить отчёт',
        projectId: 'p2',
        priority: Priority.high,
        dueDate: now.add(const Duration(days: 1)),
        isDone: false,
        tagIds: const {'t1'},
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      Todo(
        id: 'td3',
        title: 'Сделать домашку',
        projectId: 'p3',
        priority: Priority.medium,
        dueDate: now.add(const Duration(hours: 8)),
        isDone: false,
        tagIds: const {},
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Todo(
        id: 'td4',
        title: 'Купить молоко',
        projectId: 'p1',
        priority: Priority.low,
        dueDate: null,
        isDone: true,
        tagIds: const {'t3'},
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ];
  }

  Future<List<Todo>> fetchAll() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_store.isEmpty) {
      for (final t in _seed) {
        _store[t.id] = t;
      }
    }
    return _store.values.toList();
  }

  Future<Todo> add(TodoDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final t = Todo(
      id: _uuid(),
      title: draft.title,
      projectId: draft.projectId,
      priority: draft.priority,
      dueDate: draft.dueDate,
      isDone: false,
      tagIds: draft.tagIds,
      createdAt: DateTime.now(),
    );
    _store[t.id] = t;
    return t;
  }

  Future<void> update(Todo todo) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _store[todo.id] = todo;
  }

  Future<void> remove(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _store.remove(id);
  }
}

/// Контейнер всех репозиториев приложения.
///
/// Передаётся в `buildActions(...)` и через Actions в UseCase. В тестах любая
/// зависимость может быть заменена моком.
class Repos {
  const Repos({
    required this.auth,
    required this.projects,
    required this.tags,
    required this.todos,
  });

  final AuthRepo auth;
  final ProjectsRepo projects;
  final TagsRepo tags;
  final TodosRepo todos;

  /// Дефолтный набор фейковых репозиториев.
  factory Repos.defaults() => Repos(
        auth: AuthRepo(),
        projects: ProjectsRepo(),
        tags: TagsRepo(),
        todos: TodosRepo(),
      );
}
