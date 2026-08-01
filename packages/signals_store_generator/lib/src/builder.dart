import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'store_generator.dart';

/// Точка входа сборщика кода, используемая в `build.yaml`.
///
/// [SharedPartBuilder] пишет сгенерированный код в part-файл `*.g.dart`,
/// подключаемый потребителем через `part 'foo.g.dart';`.
Builder storeBuilder(BuilderOptions options) {
  return SharedPartBuilder(
    [const StoreGenerator()],
    'store_generator',
  );
}
