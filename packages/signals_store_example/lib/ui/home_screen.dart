import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../domain/stores.dart';
import '../intents/intents.dart';
import 'widgets/filter_bar.dart';
import 'widgets/stats_card.dart';
import 'widgets/todo_list_tile.dart';

/// Главный экран после входа.
///
/// Показывает статистику (computed), панель фильтра и реактивный список задач
/// (`visibleTodos` computed). Drawer содержит список проектов; FAB открывает
/// диалог создания задачи через `ShowCreateTodoDialogIntent`.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.derived,
  });

  final AppStore store;
  final TodosDerived derived;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SignalBuilder(
          builder: (context) {
            final project = derived.activeProject;
            return Text(project?.name ?? 'Все проекты');
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Фильтр',
            icon: const Icon(Icons.tune),
            onPressed: () =>
                Actions.invoke(context, const ShowFilterDialogIntent()),
          ),
        ],
      ),
      drawer: _ProjectsDrawer(store: store),
      body: Column(
        children: [
          StatsCard(derived: derived),
          const SizedBox(height: 4),
          FilterBar(store: store),
          const Divider(height: 1),
          Expanded(
            // Список пересчитывается реактивно через visibleTodos computed.
            child: SignalBuilder(
              builder: (context) {
                final todos = derived.visibleTodos;
                if (todos.isEmpty) {
                  return const Center(
                    child: Text(
                      'Нет задач',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: todos.length,
                  itemBuilder: (context, i) => TodoListTile(
                    store: store,
                    todo: todos[i],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Actions.invoke(context, const ShowCreateTodoDialogIntent()),
        icon: const Icon(Icons.add),
        label: const Text('Задача'),
      ),
    );
  }
}

class _ProjectsDrawer extends StatelessWidget {
  const _ProjectsDrawer({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SignalBuilder(
        builder: (context) {
          final user = store.session.currentUser;
          final projects = store.projects.projects.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final currentId = store.projects.currentProjectId;
          return ListView(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(user?.name ?? ''),
                accountEmail: Text(user?.email ?? ''),
                currentAccountPicture:
                    const CircleAvatar(child: Icon(Icons.person)),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Все проекты'),
                selected: currentId == null,
                onTap: () {
                  Navigator.of(context).pop();
                  Actions.invoke(context, const OpenProjectIntent(null));
                },
              ),
              const Divider(),
              for (final p in projects)
                ListTile(
                  leading:
                      Icon(Icons.circle, size: 12, color: Color(p.colorValue)),
                  title: Text(p.name),
                  selected: currentId == p.id,
                  onTap: () {
                    Navigator.of(context).pop();
                    Actions.invoke(context, OpenProjectIntent(p.id));
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: const Text('Новый проект'),
                onTap: () {
                  Navigator.of(context).pop();
                  Actions.invoke(
                      context, const ShowCreateProjectDialogIntent());
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Выйти'),
                onTap: () {
                  Navigator.of(context).pop();
                  Actions.invoke(context, const LogoutIntent());
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
