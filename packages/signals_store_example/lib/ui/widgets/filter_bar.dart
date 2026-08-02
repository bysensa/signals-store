import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../domain/stores.dart';
import '../../intents/intents.dart';

/// Панель управления списком: кнопка фильтра + индикатор активного фильтра.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final filter = store.ui.filter;
        final activeFilters = <String>[];
        if (filter.priorityFilter != null) {
          activeFilters.add(filter.priorityFilter!.label);
        }
        if (filter.hideDone) activeFilters.add('без выполненных');
        if (filter.projectFilterId != null) {
          final p = store.projects.projects[filter.projectFilterId];
          if (p != null) activeFilters.add(p.name);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () =>
                    Actions.invoke(context, const ShowFilterDialogIntent()),
                icon: const Icon(Icons.tune),
                label: const Text('Фильтр'),
              ),
              const SizedBox(width: 12),
              if (activeFilters.isEmpty)
                const Text('Все задачи',
                    style: TextStyle(color: Colors.grey))
              else
                Expanded(
                  child: Text(
                    activeFilters.join(' • '),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
