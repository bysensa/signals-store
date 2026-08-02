import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../actions/actions.dart';
import '../data/fake_repos.dart';
import '../domain/stores.dart';
import '../usecases/ui_usecases.dart' show ClearSnackbar;
import 'derived.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Корневой виджет приложения.
///
/// Регистрирует реестр `Actions` (`buildActions`) одним виджетом `Actions` в
/// корне — так любой потомок может запустить любой Intent через
/// `Actions.invoke(context, ...)`. Также биндит SnackBar к полю
/// `ui.snackbarMessage`: при появлении значения показывает сообщение и очищает
/// стор через `ClearSnackbar` UseCase.
class TaskerApp extends StatelessWidget {
  const TaskerApp({
    super.key,
    required this.store,
    required this.repos,
  });

  final AppStore store;
  final Repos repos;

  @override
  Widget build(BuildContext context) {
    final actions = buildActions(store, repos);
    // Actions оборачивает MaterialApp целиком, а НЕ только `home`. Иначе диалоги
    // и новые маршруты (живущие в Overlay Navigator'а, который НЕ является
    // потомком `home:`) не смогут найти реестр через `Actions.invoke(context)`.
    return Actions(
      actions: actions,
      child: MaterialApp(
        title: 'Tasker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1565C0),
          useMaterial3: true,
        ),
        home: _SnackbarHost(
          store: store,
          child: _AuthGate(store: store),
        ),
      ),
    );
  }
}

/// Переключает экран по состоянию аутентификации (реактивно через computed).
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final derived = Derived.of(store);
    return SignalBuilder(
      builder: (context) {
        if (derived.isAuthenticated.value) {
          return HomeScreen(store: store, derived: derived);
        }
        return LoginScreen(store: store);
      },
    );
  }
}

/// Показывает SnackBar при появлении сообщения в `ui.snackbarMessage`.
class _SnackbarHost extends StatefulWidget {
  const _SnackbarHost({required this.store, required this.child});
  final AppStore store;
  final Widget child;

  @override
  State<_SnackbarHost> createState() => _SnackbarHostState();
}

class _SnackbarHostState extends State<_SnackbarHost> {
  String? _lastShown;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final message = widget.store.ui.snackbarMessage;
        // Показываем только при смене значения на непустое (защита от
        // повторных перерисовок SignalBuilder).
        if (message != null && message != _lastShown) {
          _lastShown = message;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (messenger != null) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(message),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
            // Очищаем стор, чтобы то же сообщение можно было показать снова.
            ClearSnackbar(widget.store).invoke();
          });
        }
        return widget.child;
      },
    );
  }
}
