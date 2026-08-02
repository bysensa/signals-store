import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../../intents/intents.dart';

/// Плитка задачи в списке.
///
/// Читает данные из реактивного стора (через `SignalBuilder`), поэтому
/// перерисовывается при изменении конкретной задачи. Действия (toggle, delete)
/// запускаются через Intent'ы.
class TodoListTile extends StatelessWidget {
  const TodoListTile({super.key, required this.store, required this.todo});

  final AppStore store;
  final Todo todo;

  @override
  Widget build(BuildContext context) {
    // Подписываемся на конкретную задачу — плитка перерисовывается только при
    // изменении именно этой задачи (а не всего списка).
    return SignalBuilder(
      builder: (context) {
        final current = store.projects.todos[todo.id];
        if (current == null) return const SizedBox.shrink();
        final overdue =
            !current.isDone && current.dueDate != null && current.dueDate!.isBefore(DateTime.now());
        return Dismissible(
          key: ValueKey(current.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => Actions.invoke(context, DeleteTodoIntent(current.id)),
          child: ListTile(
            leading: Checkbox(
              value: current.isDone,
              onChanged: (_) =>
                  Actions.invoke(context, ToggleTodoIntent(current.id)),
            ),
            title: Text(
              current.title,
              style: TextStyle(
                decoration: current.isDone ? TextDecoration.lineThrough : null,
                color: current.isDone ? Colors.grey : null,
              ),
            ),
            subtitle: _subtitle(context, current, overdue),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _priorityDot(current.priority.weight),
                if (current.dueDate != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.event,
                    size: 18,
                    color: overdue ? Colors.red : Colors.grey,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _subtitle(BuildContext context, Todo current, bool overdue) {
    final tagLabels = current.tagIds
        .map((id) => store.tags.tags[id])
        .whereType<Tag>()
        .map((t) => '#${t.label}')
        .toList();
    final parts = <String>[];
    if (current.dueDate != null) {
      parts.add('${current.dueDate!.toLocal()}'.substring(0, 10));
    }
    parts.addAll(tagLabels);
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' • '),
      style: TextStyle(
        fontSize: 12,
        color: overdue ? Colors.red : Colors.grey,
      ),
    );
  }

  Widget _priorityDot(int weight) {
    final color = switch (weight) {
      2 => Colors.red,
      1 => Colors.orange,
      _ => Colors.blueGrey,
    };
    return Icon(Icons.flag, size: 18, color: color);
  }
}
