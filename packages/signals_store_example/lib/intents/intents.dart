import 'package:flutter/widgets.dart';

import '../domain/enums.dart';

/// Intent'ы — иммутабельное описание «чего хочет пользователь».
///
/// Используется встроенный Flutter [Intent]. Каждый Intent несёт параметры,
/// необходимые для выполнения. Не содержит логики — только данные.
///
/// Запускаются через `Actions.invoke(context, SomeIntent(...))`; маршрутизируются
/// в соответствующий `ContextAction<T>` (см. `lib/actions/actions.dart`).

/// Войти в аккаунт.
class LoginIntent extends Intent {
  const LoginIntent({required this.email, required this.password});
  final String email;
  final String password;
}

/// Выйти из аккаунта.
class LogoutIntent extends Intent {
  const LogoutIntent();
}

/// Показать диалог создания задачи.
class ShowCreateTodoDialogIntent extends Intent {
  const ShowCreateTodoDialogIntent();
}

/// Создать задачу (с готовыми параметрами — обычно вызывается из диалога).
class CreateTodoIntent extends Intent {
  const CreateTodoIntent({
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

/// Переключить статус выполнения задачи.
class ToggleTodoIntent extends Intent {
  const ToggleTodoIntent(this.todoId);
  final String todoId;
}

/// Удалить задачу.
class DeleteTodoIntent extends Intent {
  const DeleteTodoIntent(this.todoId);
  final String todoId;
}

/// Выбрать проект (переключение вкладки/drawer-пункта). `null` — все проекты.
class OpenProjectIntent extends Intent {
  const OpenProjectIntent(this.projectId);
  final String? projectId;
}

/// Показать диалог фильтра/сортировки.
class ShowFilterDialogIntent extends Intent {
  const ShowFilterDialogIntent();
}

/// Задать фильтр по приоритету.
class SetPriorityFilterIntent extends Intent {
  const SetPriorityFilterIntent(this.priority);
  final Priority? priority;
}

/// Переключить скрытие выполненных задач.
class ToggleHideDoneIntent extends Intent {
  const ToggleHideDoneIntent();
}

/// Задать способ сортировки.
class SetSortByIntent extends Intent {
  const SetSortByIntent(this.sortBy);
  final TodoSortBy sortBy;
}

/// Сбросить фильтр к значениям по умолчанию.
class ResetFilterIntent extends Intent {
  const ResetFilterIntent();
}

/// Показать диалог создания проекта.
class ShowCreateProjectDialogIntent extends Intent {
  const ShowCreateProjectDialogIntent();
}

/// Создать проект (параметры — из диалога).
class CreateProjectIntent extends Intent {
  const CreateProjectIntent({required this.name, required this.colorValue});

  final String name;
  final int colorValue;
}
