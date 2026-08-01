# signals_store_annotation

Аннотации для реактивных сторов [`signals_store`](../signals_store) и их
[code-генератора](../signals_store_generator).

## Установка

```yaml
dependencies:
  signals_store_annotation:
    path: ../../packages/signals_store_annotation  # или git/url
```

## Использование

Аннотация [`@Store`][Store] помечает `abstract`-класс как описание стора: его
`abstract`-поля (геттер + сеттер) код-генератор превратит в реактивные
`Signal`-бэкенды.

```dart
import 'package:signals_store_annotation/signals_store_annotation.dart';

@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int count;
  abstract String name;
}
```

Несколько аннотаций `@Store` на одном классе порождают несколько
классов-реализаций (по одной на аннотацию).

## Связанные пакеты

- [`signals_store_generator`](../signals_store_generator) — code-генератор,
  создающий реализации сторов.
- [`signals_store`](../signals_store) — runtime `ReactiveStore` (альтернатива
  кодогенерации на базе `noSuchMethod`).

[Store]: lib/src/annotations.dart
