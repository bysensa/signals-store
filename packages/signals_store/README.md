# signals_store

Reactive store на базе пакета [`signals`](https://pub.dev/packages/signals) v7.
Превращает `abstract`-поля класса в реактивные сигналы через перехват
`noSuchMethod` — без бойлерплейта, с полной статической типизацией.

## Установка

```yaml
dependencies:
  signals_store:
    path: ../../packages/signals_store  # или git/url
```

## Быстрый старт

`ReactiveStore` реализован в `lib/src/store.dart`. Публичный barrel
(`package:signals_store/signals_store.dart`) на данный момент реэкспортирует
только аннотации, поэтому `ReactiveStore` импортируется напрямую из `src/`
(так же, как это делают тесты пакета). `effect` поставляется пакетом `signals`.

```dart
import 'package:signals_store/src/store.dart'; // ReactiveStore
import 'package:signals/signals.dart';          // effect

abstract class _CounterImpl {
  abstract int count;
  abstract String name;
}

class CounterStore extends _CounterImpl with ReactiveStore {
  CounterStore({required int count, required String name}) {
    this.count = count;
    this.name = name;
  }
}

void main() {
  final store = CounterStore(count: 0, name: 'demo');

  // Запись и чтение — реактивные через signals.
  store.count = 5;
  print(store.count); // 5

  // Подписка через signals API:
  effect(() => print('count изменился: ${store.count}'));
  store.count = 10; // печатает "count изменился: 10"
}
```

Во Flutter вызывайте `dispose()` из `State.dispose()`:

```dart
class _MyWidgetState extends State<MyWidget> {
  final store = CounterStore(count: 0, name: '');

  @override
  void dispose() {
    store.dispose(); // обязательно!
    super.dispose();
  }
}
```

## Типобезопасность

Поля **полностью типизированы статически**. `abstract int count` задаёт
типизированные геттер и сеттер, поэтому компилятор проверяет и чтение,
и запись:

```dart
final int c = store.count;   // OK
store.count = 'oops';        // ❌ compile error: invalid_assignment
```

Дополнительно: абстрактный геттер выполняет implicit cast возвращаемого
значения к объявленному типу — это даёт **рантайм type-check** бесплатно,
даже если значение записано через нетипизированный путь (сериализатор,
reflection-маппер).

## Limitations

### 1. Кэш нормализации символов

`ReactiveStore` кэширует результат нормализации `Symbol` глобально, с ключом
по `runtimeType`. Это детерминировано и оптимально для прод-приложений, но:

- **Переопределение `runtimeType`** в подклассе не поддерживается — кэш может
  сломаться или слить записи разных типов. Не переопределяйте `runtimeType`.
- **Flutter hot-reload** регистрирует новый `Type` при каждом reload, что
  вызывает ограниченный рост кэша (~10–20 записей на дев-сессию). Чтобы сбросить
  в тестах или при интенсивном hot-reload:

  ```dart
  ReactiveStore.resetCache(); // @visibleForTesting
  ```

### 2. Поддерживаются только mutable `abstract`-поля

`noSuchMethod` перехватывает и геттер, и сеттер. Поэтому:

- ❌ `abstract final int x` — не работает: `final` не имеет сеттера, нельзя
  инициализировать в конструкторе → compile error.
- ❌ Computed (derived) поля не поддерживаются этим подходом. Для computed
  используйте `signals` напрямую (`computed(...)`) вне ReactiveStore.

```dart
// ✅ Правильно:
abstract class _Impl { abstract int count; }

// ❌ Неправильно:
abstract class _Bad { abstract final int x; }  // compile error с ReactiveStore
```

### 3. Производительность на hot-path

`noSuchMethod` + 2 Map lookup'а на каждое чтение/запись. Приемлемо для
UI-состояния, но узко для tight loops (списки 10k+ элементов). Для hot-path
consider кодогенерацию (`signals_store_generator`, планируется).

### 4. `dispose()` — ответственность вызывающего

`ReactiveStore` не интегрируется с Flutter lifecycle автоматически. Вы обязаны
вызывать `dispose()`, иначе сигналы утекут. Идемпотентен, безопасен к
повторному вызову.

### 5. Имена сигналов в DevTools

Сигналы именуются чистым именем поля (`count`), а не `Symbol("count")` —
для читаемости в DevTools и логах.

## Тестирование

```bash
# VM-тесты (по умолчанию):
flutter test packages/signals_store/test/

# dart2js smoke (требует node):
bash packages/signals_store/scripts/dart2js_smoke.sh

# dart2js полный (требует Chrome, для CI):
flutter test packages/signals_store/test/ --platform chrome
```

## Лицензия

См. корневой LICENSE.
