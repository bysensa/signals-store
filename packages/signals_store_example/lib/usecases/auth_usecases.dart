import '../data/fake_repos.dart';
import '../domain/stores.dart';
import 'package:signals/signals.dart';

/// UseCase: аутентифицировать пользователя.
///
/// [extension type] на корневом [AppStore] — паттерн сигнализирует, что это
/// мутация дерева состояния. Внешняя зависимость ([AuthRepo]) передаётся
/// параметром `call`, в сторах её нет.
extension type Login(AppStore state) {
  /// Пытается залогиниться через [authRepo]; при успехе записывает пользователя
  /// в `session.currentUser` и сбрасывает ошибку.
  ///
  /// Бросает [AuthException] при неверных кредах (перехватывается в Action).
  Future<void> call({
    required String email,
    required String password,
    required AuthRepo authRepo,
  }) async {
    batch(() => state.session.isLoading = true);
    try {
      final user = await authRepo.login(email: email, password: password);
      batch(() {
        state.session.currentUser = user;
        state.session.error = null;
      });
    } catch (e) {
      batch(() {
        state.session.error = e.toString();
        state.session.isLoading = false;
      });
      rethrow;
    }
    state.session.isLoading = false;
  }
}

/// UseCase: выйти из аккаунта. Не требует внешних зависимостей.
extension type Logout(AppStore state) {
  void call() {
    batch(() {
      state.session.currentUser = null;
      state.session.error = null;
      state.session.isLoading = false;
      // Сбрасываем выбор проекта/фильтры в нейтральное состояние.
      state.projects.currentProjectId = null;
    });
  }
}
