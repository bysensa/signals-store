import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../derived.dart';

/// Карточка статистики: всего / активно / выполнено / просрочено.
///
/// Читает `todoStats` computed-селектор — перерисовывается при любом изменении
/// задач или их статусов.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.derived});

  final Derived derived;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final stats = derived.todoStats.value;
        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(context, 'Всего', stats.total, Colors.blueGrey),
                _stat(context, 'Активно', stats.active, Colors.blue),
                _stat(context, 'Готово', stats.done, Colors.green),
                _stat(context, 'Просрочено', stats.overdue,
                    stats.overdue > 0 ? Colors.red : Colors.blueGrey),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stat(BuildContext context, String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
