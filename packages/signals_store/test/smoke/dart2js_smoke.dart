// Probe для проверки, что ReactiveStore компилируется и работает под dart2js.
// Запускается НЕ через flutter test, а компилируется: dart compile js ... -o ...js
// и выполняется через node. assert'ы пишут результат в stdout.
//
// Важно: этот файл не должен импортировать Flutter-зависимости. signals_store
// зависит от Flutter SDK в environment, но lib не импортирует dart:ui —
// если компиляция падает на Flutter, нужен отдельный pure-dart sub-target
// (см. README / fallback в шаге 4).
//
// print здесь — это и есть механизм зонда (маркеры RESULT для grep-проверок
// в dart2js_smoke.sh), а не логирование. Подавляем avoid_print осознанно.

// ignore_for_file: avoid_print

import 'package:signals_store/src/store.dart';

abstract class _Impl {
  abstract int count;
  abstract String _private;
}

class _Store extends _Impl with ReactiveStore {}

void main() {
  // Симулируем тестовый прогон и выводим результаты как строки.
  final store = _Store();

  // Public field round-trip.
  store.count = 42;
  final publicRead = store.count;

  // Private field round-trip.
  store._private = 'secret';
  final privateRead = store._private;

  // Результаты для assert-скрипта.
  print('RESULT public_read=$publicRead');
  print('RESULT private_read=$privateRead');

  // FieldInitializationError при чтении неинициализированного.
  final fresh = _Store();
  String? err;
  try {
    fresh.count;
  } on FieldInitializationError catch (_) {
    err = 'field_init_error';
  }
  print('RESULT uninitialized=$err');

  // dispose + post-dispose access.
  final toDispose = _Store()..count = 1;
  toDispose.dispose();
  String? disposeErr;
  try {
    toDispose.count;
  } on StateError catch (_) {
    disposeErr = 'state_error';
  }
  print('RESULT post_dispose=$disposeErr');
}
