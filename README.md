# signals-store

Управление состоянием на базе [`signals`](https://pub.dev/packages/signals) v7
для Dart/Flutter. Два互补имых подхода: **runtime-mixin** (без кодогенерации) и
**codegen** (статически типизированные сторы с computed-геттерами).

[![pub: signals_store](https://img.shields.io/badge/signals__store-0.2.0-blue)](https://pub.dev/packages/signals_store)
[![pub: signals_store_generator](https://img.shields.io/badge/signals__store__generator-0.4.2-blue)](https://pub.dev/packages/signals_store_generator)
[![pub: signals_store_annotation](https://img.shields.io/badge/signals__store__annotation-0.2.0-blue)](https://pub.dev/packages/signals_store_annotation)

## Пакеты

Монорепозиторий (Dart workspace) из четырёх пакетов:

| Пакет | Версия | Назначение |
|-------|--------|-----------|
| [`signals_store`](packages/signals_store) | 0.2.0 | `ReactiveStore` mixin — runtime-стор через `noSuchMethod`, без кодогенерации |
| [`signals_store_annotation`](packages/signals_store_annotation) | 0.2.0 | Аннотация `@Store` для codegen-подхода |
| [`signals_store_generator`](packages/signals_store_generator) | 0.4.2 | Генератор кода: `@Store`-классы → типизированные сторы с `Signal`-полями и `Computed`-геттерами |
| [`signals_store_example`](packages/signals_store_example) | — | Полноценный Flutter-пример «Tasker» (не публикуется на pub.dev) |

## Два подхода

### 1. Codegen (`@Store`) — рекомендуется

Аннотируете `abstract`-класс, генератор создаёт типизированную реализацию:
`abstract`-поля → `Signal`-backed, concrete-геттеры с реактивными зависимостями →
`Computed`. Полная статическая типизация, zero runtime-cost, поддержка вложенных
сторов (дерево состояния как в [overmind]).

```dart
import 'package:signals/signals.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';

part 'counter.g.dart';

@Store(name: 'CounterStore')
abstract class CounterImpl {
  abstract int count;             // → Signal<int> count$ (reactive)
  int get doubled => count * 2;   // → Computed<int> doubled$ (memoized)
}

void main() {
  final store = CounterStore(count: 0);
  effect(() => print('doubled: ${store.doubled}'));
  store.count = 5; // печатает "doubled: 10"
}
```

**Что генерируется** — см. [README генератора](packages/signals_store_generator/README.md):
- `Signal`-поля с override-геттером/сеттером (`count` ↔ `count$.value`)
- `Computed`-геттеры с escape-hatch (`doubled` → `doubled$.value`, `doubledRaw` → сырой пересчёт)
- Pass-through concrete-поля (вложенные сторы, `MapSignal`-коллекции)
- Детектор реактивности: определяет computed автоматически по типам, покрывая
  подсторы, Signal-коллекции, каскад через классы, dataflow через аргументы

### 2. Runtime-mixin (`ReactiveStore`) — без кодогенерации

`abstract`-поля класса становятся реактивными через перехват `noSuchMethod`.
Быстрый старт без `build_runner`, но runtime-cost (`noSuchMethod` + Map lookup
на каждое чтение) и без computed-геттеров.

```dart
import 'package:signals_store/signals_store.dart';
import 'package:signals/signals.dart';

abstract class _CounterImpl {
  abstract int count;
}

class CounterStore extends _CounterImpl with ReactiveStore {
  CounterStore({required int count}) { this.count = count; }
}

void main() {
  final store = CounterStore(count: 0);
  effect(() => print('count: ${store.count}'));
  store.count = 5; // печатает "count: 5"
}
```

Подходит для прототипов и UI-состояния вне hot-path. См.
[README signals_store](packages/signals_store/README.md).

### Когда что использовать

| | Codegen (`@Store`) | Runtime (`ReactiveStore`) |
|---|---|---|
| Типобезопасность | полная статическая | полная статическая |
| Computed-геттеры | ✅ автоматически | ❌ вручную через `computed()` |
| Вложенные сторы (дерево) | ✅ типизированные подсторы | вручную |
| Runtime-cost | zero (прямой доступ к `Signal`) | `noSuchMethod` + Map lookup |
| Кодогенерация | требуется (`build_runner`) | не требуется |
| Boilerplate | аннотация + `part` | mixin + конструктор |

Для production-приложений рекомендуется **codegen**; `ReactiveStore` удобен для
прототипов или изолированных простых сторов.

## Установка (codegen)

```yaml
dependencies:
  signals: ^7.0.0
  signals_store_annotation: ^0.2.0

dev_dependencies:
  signals_store_generator: ^0.4.2
  build_runner: ^2.4.0
```

Генерация:

```sh
dart run build_runner build
# Flutter: flutter pub run build_runner build
```

## Пример

[`signals_store_example`](packages/signals_store_example) — менеджер задач
«Tasker»: глобальное дерево сторов (`AppStore` → `SessionStore` /
`ProjectsStore` / `TagsStore` / `UiStore`), UseCase как `extension type`,
Intent + `ContextAction`, фильтрация/сортировка, аутентификация. Архитектура
вдохновлена [overmind].

```sh
cd packages/signals_store_example
flutter pub get
flutter run
```

## Разработка

Монорепозиторий использует Dart workspace (`resolution: workspace` в pubspec
каждого пакета). Команды запускаются из корня:

```sh
# Установка зависимостей воркспейса
flutter pub get

# Анализ всех пакетов
dart analyze packages/signals_store_annotation packages/signals_store packages/signals_store_generator

# Тесты генератора (детектор реактивности + codegen)
flutter test packages/signals_store_generator/test/

# Тесты example (включая runtime-проверки computed)
flutter test packages/signals_store_example/test/
```

## Лицензия

MIT — см. [LICENSE](LICENSE).

[overmind]: https://overmindjs.org
