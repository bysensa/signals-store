import '../domain/stores.dart';

/// UseCase: показать сообщение в SnackBar.
///
/// Записывает текст в `ui.snackbarMessage`; UI-слой (app.dart) слушает это поле
/// и показывает SnackBar при появлении значения, после чего вызывает
/// [ClearSnackbar].
extension type ShowSnackbar(AppStore state) {
  void invoke({required String message}) {
    state.ui.snackbarMessage = message;
  }
}

/// UseCase: очистить сообщение SnackBar (вызывается UI после показа).
extension type ClearSnackbar(AppStore state) {
  void invoke() {
    state.ui.snackbarMessage = null;
  }
}
