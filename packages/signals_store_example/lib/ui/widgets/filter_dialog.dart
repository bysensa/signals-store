import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/stores.dart';
import '../../intents/intents.dart';

/// Показывает диалог фильтра/сортировки.
///
/// Все изменения внутри диалога немедленно вызывают соответствующие Intent'ы
/// (SetPriorityFilterIntent, ToggleHideDoneIntent, SetSortByIntent) — стор
/// обновляется реактивно, и пользователь видит результат до закрытия диалога.
Future<void> showFilterDialog(BuildContext context, AppStore store) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FilterDialog(store: store),
  );
}

class _FilterDialog extends StatelessWidget {
  const _FilterDialog({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Фильтр и сортировка'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Приоритет',
                style: TextStyle(fontWeight: FontWeight.bold)),
            // Список опций приоритета — реактивно подсвечивает текущий выбор.
            SignalBuilder(
              builder: (context) {
                // Читаем текущий фильтр, чтобы подписаться на изменения.
                final active = store.ui.filter.priorityFilter;
                return Wrap(
                  spacing: 8,
                  children: [
                    _priorityChip(context, 'Любой', null, active == null),
                    for (final p in Priority.values)
                      _priorityChip(context, p.label, p, active == p),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Сортировка',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SignalBuilder(
              builder: (context) {
                final active = store.ui.filter.sortBy;
                return RadioGroup<TodoSortBy>(
                  groupValue: active,
                  onChanged: (v) {
                    if (v != null) {
                      Actions.invoke(context, SetSortByIntent(v));
                    }
                  },
                  child: Column(
                    children: [
                      for (final s in TodoSortBy.values)
                        RadioListTile<TodoSortBy>(
                          value: s,
                          title: Text(s.label),
                          dense: true,
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // Скрытие выполненных.
            SignalBuilder(
              builder: (context) {
                final hideDone = store.ui.filter.hideDone;
                return SwitchListTile(
                  value: hideDone,
                  title: const Text('Скрывать выполненные'),
                  dense: true,
                  onChanged: (_) =>
                      Actions.invoke(context, const ToggleHideDoneIntent()),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Actions.invoke(context, const ResetFilterIntent()),
          child: const Text('Сбросить'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  Widget _priorityChip(
    BuildContext context,
    String label,
    Priority? priority,
    bool selected,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        Actions.invoke(context, SetPriorityFilterIntent(priority));
      },
    );
  }
}
