import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../../intents/intents.dart';

/// Показывает диалог создания проекта.
///
/// Подтверждение вызывает `CreateProjectIntent` через `Actions.invoke` — action
/// выполнит `CreateProject` UseCase с репозиторием и покажет SnackBar.
Future<void> showCreateProjectDialog(BuildContext context, AppStore store) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CreateProjectDialog(),
  );
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _nameController = TextEditingController();
  int _colorIndex = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый проект'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Цвет'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (var i = 0; i < TaskerColors.projectPalette.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _colorIndex = i),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(TaskerColors.projectPalette[i]),
                      shape: BoxShape.circle,
                      border: _colorIndex == i
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _onCreate,
          child: const Text('Создать'),
        ),
      ],
    );
  }

  void _onCreate() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Actions.invoke(
      context,
      CreateProjectIntent(
        name: name,
        colorValue: TaskerColors.projectPalette[_colorIndex],
      ),
    );
    Navigator.of(context).pop();
  }
}
