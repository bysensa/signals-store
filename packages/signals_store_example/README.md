# signals_store_example

End-to-end пример для [`signals_store_generator`](../signals_store_generator).

Демонстрирует полный цикл:

1. `lib/stores.dart` — описание стора через `@Store`-аннотации (`part 'stores.g.dart';`).
2. `flutter pub run build_runner build` генерирует `lib/stores.g.dart`.
3. `test/generated_store_test.dart` — runtime-проверка, что сгенерированные
   сторы реактивны и изолированы.

Воспроизвести локально:

```sh
flutter pub get
flutter pub run build_runner build
flutter test
```
