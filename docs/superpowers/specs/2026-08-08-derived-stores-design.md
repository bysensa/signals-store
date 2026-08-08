# Derived-сторы: дизайн

Дата: 2026-08-08
Статус: одобрено пользователем (диалоговый брейншторм), ожидает ревью спеки

## Контекст и цель

Сегодня derived-состояние (аналог `derived` из overmind.js) живёт в рукописном
классе `Derived` (`packages/signals_store_example/lib/ui/derived.dart`) — пучок
`computed()` над `AppStore`, создаваемый вручную. Цель — поднять механику на
уровень генератора: **полноценные сторы с доступом к корню дерева сторов**.

Ключевой сценарий (от пользователя): derived-сторы создаются **on-demand в любом
месте приложения**, где ссылки на корень нет. Пример: стейт экрана в стеке
навигации — экран открывается, создаётся derived-стор, корень при этом доступен
внутри стора. Экран закрывается — стор диспозится.

## Семантика

Derived-стор = **полноценный стор + доступ к корню**. По всем механикам он
идентичен `@Store`; отличия только в трёх точках: аннотация `@DerivedStore`,
abstract-геттер root, сгенерированный `dispose()`.

- **Единый пайплайн с `@Store` (требование переиспользования):** derived
  обрабатывается тем же ядром генератора — поля, геттеры, конструктор,
  детектор реактивности, коллизии. Отличия — аддитивные надстройки: root-геттер,
  `dispose()`, имя root в reactive-базе. Дублирование логики полей/геттеров/ctor
  между `@Store` и `@DerivedStore` запрещено — общий приватный эмиттер
  `_emitStoreClass` (см. «Изменения в генераторе»);
- собственные `abstract`-поля → реактивные `Signal`-поля (как в `@Store`).
  Собственное состояние — норма: используется в т.ч. для параметров создания
  (`todoId` экрана);
- concrete-поля → pass-through, concrete-геттеры → `Computed` (существующий
  детектор реактивности);
- доступ к корню — через самодекларируемый `abstract`-геттер `root`;
- **`dispose()` — единая механика для `@Store` и `@DerivedStore`** (см.
  «Жизненный цикл»): пользовательская логика перед диспозом — через
  `dispose()`, объявленный в impl, генератор вызовет `super.dispose()` первым.

Derived-стор **не является полем дерева** и не конструируется корнем — проблема
«курица-яйцо» отсутствует по построению. Монтирование derived как
concrete-поля-подстора в дерево остаётся возможным через существующий
pass-through механизм `@Store` (root резолвится лениво при первом доступе,
после регистрации корня) — не запрещаем, документируем.

## API

### Аннотации (signals_store_annotation)

```dart
class DerivedStore {
  const DerivedStore({required this.name});
  final String name;
}
```

Без параметра `from:` — единственный источник истины о типе корня это тип
abstract-геттера в impl (см. ниже). На одном классе — ровно одна аннотация
`@DerivedStore`; `@Store` и `@DerivedStore` на одном классе запрещены.

В существующую аннотацию `@Store` добавляется флаг `root`:

```dart
class Store {
  const Store({required this.name, this.abstract = false, this.root = false});

  final String name;
  final bool abstract;

  /// Если `true` — сгенерированный стор саморегистрируется в StoreRootScope
  /// при создании и является валидной целью root-геттера derived-сторов.
  final bool root;
}
```

### Пользовательский код

```dart
@DerivedStore(name: 'TodoDetailsStore')
abstract class TodoDetailsStoreImpl {
  /// Корень дерева сторов. Маркер для генератора: реализация резолвится
  /// через StoreRootScope. Должен быть ровно один такой геттер.
  AppStoreImpl get root;

  /// Собственное реактивное поле (параметр создания).
  abstract String todoId;

  /// Computed-геттер: читает корень → реактивен.
  Todo? get todo => root.projects.todos[todoId];

  /// Пользовательская логика перед диспозом (опционально). Генератор
  /// вызовет super.dispose() первым, пока сигналы ещё живы.
  void dispose() {
    // произвольная логика: отписки, логирование, ...
  }
}
```

**Почему геттер, а не миксин/параметр аннотации:** source_gen не может вживить
член в исходный класс, а тела геттеров в impl должны анализироваться — `root`
обязан быть объявлен в самом impl. Вариант с миксином `RootedStore<R>` +
`from:` в аннотации рассматривался и отклонён: тип корня писался бы дважды,
плюс лишний API в рантайм-пакете. Вариант «только `from:` без объявления»
невозможен: идентификатор `root` в телах impl не разрешится (compile error).

**Почему геттер без тела (а не поле и не `abstract`-ключевое слово):** в abstract-классе геттер без тела (`AppStoreImpl get root;`) автоматически абстрактен — реализацию даёт подкласс. Ключевое слово `abstract` на членах запрещено Dart (`abstract_class_member`). Синтаксис поля (`abstract AppStoreImpl root;`) сегодня означает «Signal-поле стора» — root таким быть не должен (стабильная ссылка, резолвится один раз). Поле, типизированное корневым impl, в `@DerivedStore`-классе → валидационная ошибка «объявите root как геттер без тела».

### Генерируемый код

```dart
class TodoDetailsStore extends TodoDetailsStoreImpl {
  TodoDetailsStore({required String todoId})
      : todoId$ = Signal<String>(todoId,
            options: SignalOptions<String>(
                name: 'TodoDetailsStore.todoId'));

  final Signal<String> todoId$;

  @override
  String get todoId => todoId$.value;
  @override
  set todoId(String value) => todoId$.value = value;

  @override
  AppStoreImpl get root => StoreRootScope.of<AppStoreImpl>();

  late final Computed<Todo?> todo$ = computed(() => todoRaw,
      options: ComputedOptions<Todo?>(name: 'TodoDetailsStore.todo'));

  @override
  Todo? get todo => todo$.value;
  @override
  Todo? get todoRaw => super.todo;

  @override
  void dispose() {
    super.dispose(); // эмитится, если dispose объявлен в impl: сигналы ещё живы
    todoId$.dispose();
    todo$.dispose();
  }
}
```

- `root` — **геттер** (не `late final`-поле): резолвит `StoreRootScope.of<T>()`
  при каждом обращении. Поэтому derived всегда видит **текущий** корень —
  пересоздание корня (см. «Пересоздание корня») не оставляет derived привязанным
  к старому инстансу. Стоимость (скан реестра, N≤2) на каждое вычисление
  computed пренебрежимо мала; `of<T>()` читает `List`/`Expando`, не сигналы,
  поэтому ложных зависимостей в computed не возникает.
- `dispose()` генерируется только для derived (экранный lifecycle:
  `State.dispose()` → `store.dispose()`). Корневые сторы не меняются
  (app-lifetime).
- **Пользовательская логика перед диспозом:** если impl объявляет concrete
  `void dispose()`, генератор эмитит override, вызывающий `super.dispose()`
  первым — до диспоза сигналов (сигналы ещё живы, их можно читать). Если
  dispose не объявлен — эмитится dispose только с диспозом сигналов (без
  super-вызова). Если dispose объявлен **abstract** (`void dispose();`) —
  эмитится реализация с диспозом сигналов: так dispose входит в публичный
  контракт impl-типа (удобно, когда переменная типизирована impl'ом).
  Dispose синхронный; асинхронную очистку пользователь запускает сам
  (dispose не может await'ить).
- Правила полей/геттеров/конструктора — как у `@Store` (abstract-поля →
  Signal, concrete-поля → pass-through, reactive-геттеры → Computed,
  коллизии имён — существующий `_checkNameCollisions` + учёт имени
  root-геттера/`dispose`).

## StoreRootScope (runtime, signals_store)

Реестр корня с **детектом окружения через env-var** — никакого флага, маркера
зоны или ручного bootstrap. Окружения не пересекаются: test-регистрации никогда
не попадают в app-реестр и наоборот.

Принцип детекции:
- **Тест** — детектится по `Platform.environment['FLUTTER_TEST']` (автоматически
  выставляется `flutter test`, runtime, не требует `--dart-define`). Подтверждено
  эмпирически.
- **App** (plain `runApp` или с `runZonedGuarded`) — переменная отсутствует →
  единый глобальный реестр. Топология зон приложения на резолв **не влияет**,
  поэтому `runZonedGuarded` работает без каких-либо действий.

```dart
class StoreRootScope {
  static final bool _isTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  static final _Registry _appRegistry = _Registry();
  static final Expando<_Registry> _testByZone = Expando();

  /// Регистрирует [root] (слабо) в активном окружении.
  static void register(Object root);

  /// Резолвит корень типа [T] (`is T`-скан по weak-ссылкам); `StateError`,
  /// если не найден. Убирает мёртвые weak-записи влетую.
  static T of<T>();

  /// Явное снятие регистрации (вызывается из dispose корневого стора).
  static void unregister(Object root);

  /// Очищает per-zone реестр текущей зоны (tearDown). Опционально: per-test
  /// зоны раннера уже изолируют.
  @visibleForTesting
  static void resetCurrentZone();

  static _Registry _active() {
    if (_isTest) {
      // per-test зоны раннера (package:test/flutter_test) → автоизоляция.
      return _testByZone[Zone.current] ??= _Registry();
    }
    return _appRegistry;
  }
}
```

- **Почему env-var, а не зона/маркер/флаг:** `Platform.environment['FLUTTER_TEST']`
  — единственный сигнал, который надёжно отличает тест от app **и** не зависит
  от топологии зон приложения. Зон-маркер ломался на `runZonedGuarded`;
  `Zone.current == Zone.root` — то же; compile-time `bool.fromEnvironment(
  'FLUTTER_TEST')` под `flutter test` даёт **false** (проверено), нужен явный
  `--dart-define`. Runtime env-var работает автоматически.
- **Тестам ничего делать не нужно:** `flutter test` выставляет переменную →
  детект → per-zone реестр → изоляция через зоны раннера.
- **App (включая `runZonedGuarded`):** переменная отсутствует → `_appRegistry`,
  без разницы, в какой зоне живёт app-код.
- **Авторегистрация:** конструктор стора с `@Store(root: true)` пишет в активное
  окружение через `StoreRootScope.register(this)`. `main.dart` не меняется.
- **Web-платформа:** `dart:io` недоступен; signals_store требует Flutter SDK
  (web не заявлен). При необходимости web-цели — добавить `--dart-define=
  IS_TEST=true` и компилировать `_isTest` из `bool.fromEnvironment` (fallback).

### Эмпирические проверки (проверено при дизайне)

1. **`Platform.environment['FLUTTER_TEST']` выставляется `flutter test`**
   автоматически (runtime env-var, не dart-define) — ✅ проверено зондом.
   `bool.fromEnvironment('FLUTTER_TEST')` под `flutter test` даёт **false**
   (✅ проверено) — compile-time константу нужно выставлять `--dart-define`
   явно. Отсюда выбор runtime env-var.
2. **package:test / flutter_test создают зону на каждый тест** — ✅ проверено
   (тело теста в дочерней зоне, соседние тесты — разные зоны). Отсюда
   автоизоляция test-окружения через per-zone реестр. Регресс-зонд в плане.
3. Поведение signals после `dispose()` — проверяется при реализации
   (зафиксировать фактическое поведение для документации).

## Root-маркировка: `@Store(root: true)`

Root-статус — **явная маркировка**, а не вывод из структуры дерева:
пользователь помечает корневой стор `@Store(root: true)` (см. секцию API).
Детекция O(1) — статус читается из аннотации, никаких графов containment и
обходов; производительность генерации не зависит от числа сторов.

- **Параллельный второй корень** (StoreX — отдельное дерево): StoreX тоже
  помечается `root: true`; оба конструктора регистрируют, `of<StoreAImpl>()`
  работает — derived не ломаются.
- **Поглощение** (в StoreXImpl появилось поле типа StoreAImpl): ничего не
  ломается — StoreA продолжает саморегистрироваться (его конструктор
  вызывается при сборке дерева StoreX), и derived-from-StoreA резолвит именно
  тот инстанс StoreA, который лежит в дереве. Перенастройка derived на
  StoreX — осознанное решение пользователя, а не требование генератора.
- **Подстор как цель derived:** маркировка не запрещает пометить не-корневой
  стор — `root: true` означает «саморегистрируется и доступен для резолва».
  Тип может быть одновременно подстором одного дерева и точкой резолва.
- **Два инстанса одного помеченного типа:** повторная регистрация заменяет
  предыдущую (последний созданный выигрывает) — задокументировано в
  StoreRootScope.

## Изменения в генераторе

1. **Общий эмиттер (переиспользование):** вся логика полей/геттеров/конструктора/
   коллизий выносится в приватный `_emitStoreClass(...)`. `@Store` и
   `@DerivedStore` вызывают его; дублирование логики между ними запрещено.
   Производные-опции (root-геттер, dispose) передаются параметрами/флагами.
2. Новый `TypeChecker` для `@DerivedStore`; обработка в том же проходе, что
   `@Store`.
3. Детектор реактивности: имя root-геттера добавляется в reactive-базу через
   новый параметр `extraReactiveNames` у `computeReactiveGetters` (root —
   геттер без тела, не поле, и в базу из `_instanceFields` не попадает).
   Геттеры, читающие `root.*`, становятся Computed существующим фикс-пойнтом.
   Изменение аддитивное (параметр опциональный, default empty) и не затрагивает
   существующие `@Store`-вызовы.
4. Root-маркировка: сторы с `@Store(root: true)` получают тело конструктора
   с авторегистрацией. Граф containment не строится — статус явный, O(1).
5. **`dispose()` — едино для `@Store` и `@DerivedStore`:** `_emitStoreClass`
   всегда эмитит `dispose()` для сгенерированного стора, диспозящий
   Signal/Computed-поля; для concrete/abstract `dispose()` в impl — по правилам
   секции «Жизненный цикл». Для `@Store(root: true)` dispose дополнительно
   снимает регистрацию из `StoreRootScope` (`StoreRootScope.unregister(this)`).
6. Валидации (понятные ошибки `InvalidGenerationSource`):
   - `@DerivedStore` только на abstract-классе;
- ровно один геттер без тела, типизированный корневым impl (= root-слот);
     ноль — ошибка «объявите root»; больше одного — ошибка;
   - тип root-геттера — impl, помеченный `@Store(root: true)` (иначе ошибка:
     «пометьте <тип> как @Store(root: true)»); `@DerivedStore`-impl как цель —
     ошибка (derived-of-derived не поддерживается);
   - поле (не геттер), типизированное корневым impl → ошибка «объявите как
     геттер без тела»;
   - запрет named-конструкторов (как у `@Store`);
   - `dispose()` в impl с неподходящей сигнатурой (параметры, non-void)
     → ошибка; concrete/abstract `void dispose()` — легален;
   - проверка пустоты: для `@Store` — как сегодня; для derived — без полей
     валиден, если есть геттеры помимо root; совсем пустой — ошибка
     «ничего генерировать не нужно»;
   - коллизии имён с именем root-геттера, `*Raw`, `*$`; объявленный в impl
     `dispose` — не коллизия, а точка override.
7. v1-ограничения (ошибки с понятным текстом): без type-параметров и
   `abstract: true` для derived; корень и derived — в одной библиотеке.

## Тестирование

- Юнит-тесты derived: тест создаёт `AppStore(...)` (авторегистрация пишет в
  test-окружение — детектится автоматически по `FLUTTER_TEST`, без
  `enableTestMode`) → создаёт derived → assert. Изоляция per-test — через зоны
  раннера автоматически; `resetCurrentZone()` в tearDown опционален.
- Подмена корня: `StoreRootScope.register(fakeExtendsAppStoreImpl)` — резолв
  по `is T` найдёт фейк.
- Тесты генератора: contains-матчеры + обязательный `dart analyze` на
  сгенерированном выводе (helper `_expectCompiles` — проектный принцип
  «codegen tests must compile»).
- Эмпирические проверки зон — отдельные задачи до реализации (см. выше).

## Миграция примера

Рукописный `Derived` в `ui/derived.dart` заменяется generated derived-стором
(или несколькими) — showcase в example-пакете. Консистентно с архитектурными
гайдлайнами: derived-сторы отвечают «как отобразить», живут в UI-слое.

## Отклонённые альтернативы

- **Миксин `RootedStore<R>` + `from:` в аннотации** — тип корня дважды, лишний
  runtime-API. Заменено самодекларируемым abstract-геттером.
- **`@Store(derived: true)`** — размытый контракт одной аннотации на два
  режима; менее очевидные ошибки пользователя.
- **Вывод derived по структуре без аннотации** — магия, ломает легальный
  сегодня pass-through concrete-поля типа корня.
- **Монтирование derived как поля корня с авто-созданием корнем** — не закрывает
  главный сценарий (создание on-demand в месте без ссылки на корень); оставлено
  как опция через существующий pass-through.
- **Резолв в подсторы (рекурсивный обход)** — YAGNI.
- **Zone-keyed реестр для app-окружения** — зависимость от топологии зон
  приложения (`runZonedGuarded` и т.п.): регистрация в одной зоне могла быть
  невидима из другой. App-реестр глобален и zone-free; зоны используются
  только внутри явно включённого test-окружения.
- **Вывод root-статуса из графа containment** — неявная магия: добавление
  поля в одном сторе молча меняет поведение другого; реструктуризация дерева
  ломает derived на этапе кодогенерации; тип не может быть одновременно
  корнем и подстором. Заменено явной маркировкой `@Store(root: true)`.
- **`static bool _testMode` + ручное `enableTestMode()`** — лишний boilerplate
  и глобальное состояние. Заменено детектом по `Platform.environment['FLUTTER_TEST']`.
- **Зона-маркер / `Zone.current == Zone.root` для детекта app** — ломается на
  `runZonedGuarded` (crash-reporting в main): app-код в дочерней зоне
  детектится как тест → регистрации уходят в пустой per-zone реестр →
  `StateError`. Заменено env-var (не зависит от топологии зон).
- **`bool.fromEnvironment('FLUTTER_TEST')`** — compile-time константа; под
  `flutter test` даёт **false** (проверено), нужен явный `--dart-define`.
  Runtime env-var работает автоматически — выбран он.
- **Хук `onDispose()`** — лишняя конвенция имени; заменён естественным
  override: impl объявляет `dispose()`, генератор вызывает `super.dispose()`
  первым.
- **`late final` root-поле в derived** — кеширует корень при первом обращении,
  оставляя derived привязанным к **старому** инстансу после пересоздания корня.
  Заменено геттером `root => StoreRootScope.of<T>()` — резолв при каждом
  обращении, derived всегда видит актуальный корень.
- **zone-values с форком зон (`runIsolated`)** — не нужно: Expando по
  Zone.current даёт изоляцию без форков.

## Пересоздание корня

Сценарии смены инстанса корня и поведение `StoreRootScope`:

- **Hot restart:** статика сбрасывается, `main()` перевызывается → регистрация
  в чистый реестр. Корректно.
- **App-swap с dispose** (logout → `old.dispose()` → `new AppStore()`): dispose
  корня вызывает `unregister(old)`, затем конструктор нового регистрирует себя.
  Корректно.
- **App-swap без dispose:** `register(new)` убирает старую weak-запись того же
  `runtimeType` (replace), мёртвые weak-записи чистятся при `register` и `of<T>`
  превентивно (`target == null`). Корректно — реестр не копит мусор.
- **Derived, живущий через пересоздание корня:** поскольку root — **геттер**
  (не `late final`), свежесозданный derived всегда привяжется к **актуальному**
  корню при первом обращении. Уже-живущий derived, чьи computed подписаны на
  сигналы **старого** корня, при пересоздании автоматически не переподпишется
  (computed переоценивается по триггеру своих текущих зависимостей). Поэтому
  **контракт: время жизни derived ≤ время жизни текущего корня.** На практике
  пересоздание корня (logout) совпадает с разборкой UI (`Navigator` reset), и
  старые derived диспозятся вместе с экранами — staleness не возникает.

## Жизненный цикл: `dispose()` для `@Store` и `@DerivedStore`

`dispose()` диспозит Signal- и Computed-поля стора. **Механика едина для
`@Store` и `@DerivedStore`** — один и тот же код-генератор:

- если impl объявляет concrete `void dispose()` → эмитится override, вызывающий
  `super.dispose()` **первым** (сигналы ещё живы, их можно читать);
- если dispose не объявлен → эмитится dispose только с диспозом сигналов
  (без super-вызова);
- если dispose объявлен **abstract** (`void dispose();`) → эмитится реализация
  с диспозом сигналов; так dispose входит в публичный контракт impl-типа;
- неподходящая сигнатура (параметры, non-void) → ошибка кодогенерации;
- dispose синхронный; асинхронную очистку пользователь запускает сам.

Для **`@DerivedStore`** dispose всегда генерируется (on-demand жизненный цикл
экрана/диалога: `State.dispose()` → `store.dispose()`). Для **`@Store`** dispose
генерируется по умолчанию тоже — это безопасно (idempotent), даёт единообразный
контракт «любой сгенерированный стор диспозится», и позволяет диспозить
поддерево сторов (например, при logout'е: `appStore.session.dispose()`).
Стор с `@Store(root: true)` при dispose дополнительно снимает себя с регистрации
в `StoreRootScope` (см. ниже).

## Циклы удержания и `WeakReference`

**Проблема:** `StoreRootScope` держит ссылку на корневой стор. Корневой стор
через дерево полей ссылается на подсторы; подсторы через `Computed`-геттеры
могут ссылаться обратно на корень; derived-стор через root-геттер ссылается на
корень. Если **derived-стор читает корень из scope**, а scope держит корень
сильно (strong) — disposed derived-стор, удерживаемый чем-то, не освобождается.
Хуже: в тестах, где root создаётся и забывается, strong-ref в глобальном
реестре удерживал бы его до конца процесса.

**Решение:** реестр хранит корни через **`WeakReference`** (Dart 3, стабильно).
Это разрывает цикл: scope не удерживает стор; стор удерживается обычными
ссылками приложения (дерево, `State`/`InheritedWidget`). Корень, на который не
осталось сильных ссылок, собирается GC; его weak-запись в реестре
обнуляется (`WeakReference.target == null`) и убирается при следующем
обходе `of<T>()`.

Контракт `of<T>()`:

```dart
static T of<T>() {
  // Сборка мусора влетую: weak-записи с обнулённым target пропускаются.
  for (final ref in _activeRefs().toList()) {
    final target = ref.target;
    if (target == null) {
      _activeRefs().remove(ref);     // убрали мёртвую запись
      continue;
    }
    if (target is T) return target;
  }
  throw StateError('StoreRootScope: корень типа $T не зарегистрирован. ...');
}
```

- Авторегистрация: `register(this)` создаёт `WeakReference(this)`.
- `dispose()` корневого стора (`@Store(root: true)`) дополнительно явно
  удаляет свою weak-запись — детерминизм вместо ожидания GC (для тестов
  это важно).
- Derived-стор **не** регистрируется в scope (только корень) → его
  жизненный цикл управляется полностью сильными ссылками приложения;
  dispose derived освобождает только его собственные Signal/Computed.
- Подстор в дереве корня **не** регистрируется в scope (только `root: true`) →
  дерево удерживается корнем; scope держит лишь слабую ссылку на корень.
