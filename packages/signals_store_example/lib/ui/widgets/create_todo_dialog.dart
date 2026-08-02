import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/stores.dart';
import '../../intents/intents.dart';

/// Показывает диалог создания задачи.
///
/// Внутри подтверждения (по «Сохранить») вызывает `CreateTodoIntent` через
/// `Actions.invoke` — это замыкает цепочку: action показал диалог → диалог
/// вызвал дочерний intent → action выполнит UseCase.
Future<void> showCreateTodoDialog(BuildContext context, AppStore store) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CreateTodoDialog(store: store),
  );
}

class _CreateTodoDialog extends StatefulWidget {
  const _CreateTodoDialog({required this.store});
  final AppStore store;

  @override
  State<_CreateTodoDialog> createState() => _CreateTodoDialogState();
}

class _CreateTodoDialogState extends State<_CreateTodoDialog> {
  final _titleController = TextEditingController();
  Priority _priority = Priority.medium;
  DateTime? _dueDate;
  String? _projectId;
  final Set<String> _tagIds = {};

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая задача'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Проект — реактивно из стора. Список может меняться.
            SignalBuilder(
              builder: (context) {
                final projects = widget.store.projects.projects.values.toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                _projectId ??= projects.isNotEmpty ? projects.first.id : null;
                return DropdownButtonFormField<String>(
                  initialValue: _projectId,
                  decoration: const InputDecoration(labelText: 'Проект'),
                  items: [
                    for (final p in projects)
                      DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          children: [
                            Icon(Icons.circle,
                                size: 10, color: Color(p.colorValue)),
                            const SizedBox(width: 8),
                            Text(p.name),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _projectId = v),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Priority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: [
                for (final p in Priority.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (v) => setState(() => _priority = v ?? Priority.medium),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(_dueDate == null
                      ? 'Без дедлайна'
                      : 'До: ${_dueDate!.toLocal()}'
                          .substring(0, 16)),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                  child: const Text('Выбрать дату'),
                ),
                if (_dueDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Теги — реактивно из стора.
            SignalBuilder(
              builder: (context) {
                final tags = widget.store.tags.tags.values.toList()
                  ..sort((a, b) => a.label.compareTo(b.label));
                return Wrap(
                  spacing: 8,
                  children: [
                    for (final t in tags)
                      FilterChip(
                        label: Text('#${t.label}'),
                        avatar: Icon(Icons.circle,
                            size: 8, color: Color(t.colorValue)),
                        selected: _tagIds.contains(t.id),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _tagIds.add(t.id);
                          } else {
                            _tagIds.remove(t.id);
                          }
                        }),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  void _onSave() {
    final title = _titleController.text.trim();
    if (title.isEmpty || _projectId == null) return;
    // Цепочка действий: диалог вызывает CreateTodoIntent.
    Actions.invoke(
      context,
      CreateTodoIntent(
        title: title,
        projectId: _projectId!,
        priority: _priority,
        dueDate: _dueDate,
        tagIds: Set.of(_tagIds),
      ),
    );
    Navigator.of(context).pop();
  }
}
