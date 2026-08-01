/// Code generator for signals_store.
///
/// Подключается потребителем через `build_runner` (см. README). Сами типы
/// (`[StoreGenerator]`, `storeBuilder`) обычно не импортируются напрямую —
/// `build.yaml` этого пакета регистрирует builder для всех библиотек.
library;

export 'src/builder.dart' show storeBuilder;
export 'src/store_generator.dart' show StoreGenerator;
