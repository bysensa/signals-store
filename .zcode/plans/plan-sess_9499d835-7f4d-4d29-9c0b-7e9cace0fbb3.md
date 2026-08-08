# Fix: приватные поля генерируют некомпилируемый код

## Корневая причина (эмпирически подтверждена)

Сгенерированный для приватных полей код **не компилируется**. Существующие тесты проходили, потому что используют только `contains`-матчеры и никогда не проверяют компилируемость результата.

| Поле | Super-ctor | Текущий вывод | Ошибка Dart |
|---|---|---|---|
| private **abstract** `_count` | — | `CounterStore({required int _count})` | `private_named_non_field_parameter` |
| private **concrete** `_s`, **named** super | `{required this._s}` | `HolderStore({required super._s})` | `super_formal_parameter_without_associated_named` + `private_named_non_field_parameter` |
| private **concrete** `_s`, **positional** super | `this._s` | ошибка C4 (false positive — валидный кейс отклоняется) | `isRequiredNamed` фильтр не ловит positional initializing-formal |

**Языковое ограничение Dart (подтверждено):** приватное имя НЕ может быть named-параметром, не являющимся initializing-formal; `super._private` запрещён даже в той же библиотеке. Единственный путь — **публичный параметр** (имя без `_`), который форвардит значение.

## Решение (выбрано пользователем): Strip underscore → public param

Приватное поле `_count` → конструктор принимает публичный `count`, который форвардит значение:
- **abstract**: в приватный `_count$`-сигнал (`_count$ = Signal<int>(count, ...)`). Signal-поле и геттер/сеттер остаются приватными (`_count$`, `_count`).
- **concrete (positional super)**: через явный `: super(secret)` в initializer-list.
- **concrete (named super)**: **запретить** понятной ошибкой (Dart не раскрывает приватный named-параметр суперконструктора подклассу — фундаментальное ограничение).

## Файлы к изменению

### 1. `packages/signals_store_generator/lib/src/store_generator.dart`

**Добавить helper для имени параметра (≈ строка 510, после `_typeStringFor`):**
```dart
/// Имя параметра конструктора для поля.
/// Для приватного поля `_count` → публичное `count` (Dart запрещает приватные
/// named-параметры, не являющиеся initializing-formal). Для публичного — как есть.
String _ctorParamName(FieldElement f) {
  final n = f.name!;
  return n.startsWith('_') ? n.substring(1) : n;
}

/// Приватное ли поле (имя начинается с `_`).
bool _isPrivateField(FieldElement f) => f.name!.startsWith('_');
```

**Реактивные поля (блок 169-196):** для приватного поля эмитить публичный параметр, но приватный signal/геттер/сеттер:
```dart
for (final f in reactiveFields) {
  final typeStr = _typeStringFor(f.type, implToStoreName);
  final fieldName = f.name!;                       // _count (private)
  final paramName = _ctorParamName(f);             // count  (public, stripped)
  final signalField = '$fieldName\$';              // _count$ (private)
  signalFieldDecls.add('  final Signal<$typeStr> $signalField;');
  ctorParams.add('required $typeStr $paramName');  // public param
  ctorInits.add('$signalField = Signal<$typeStr>($paramName, '
      "options: SignalOptions<$typeStr>(name: '$storeName.$fieldName'))");
  accessors.addAll([
    '  @override\n  $typeStr get $fieldName => $signalField.value;',
    '  @override\n  set $fieldName($typeStr value) => $signalField.value = value;',
  ]);
}
```

**Concrete поля (блок 198-232) — переписать валидацию C4 и эмиссию:**

Разделяем приватные и публичные concrete-поля. Для приватных требуем **позиционный** initializing-formal в super-конструкторе; для публичных — named (текущее поведение).

```dart
final superFormals = <String, ParameterElement>{};
for (final p in element.unnamedConstructor?.formalParameters ?? const []) {
  if (p.isInitializingFormal) superFormals[p.name!] = p;  // ключ: ИМЯ поля
}
final positionalSuperArgs = <String>[];  // для приватных → : super(x, y, ...)

for (final f in plainFields) {
  final fieldName = f.name!;
  final formal = superFormals[fieldName];
  if (formal == null) {
    throw InvalidGenerationSource(/* обновить сообщение: упомянуть positional для приватных */);
  }
  if (_isPrivateField(f)) {
    // Приватное поле: Dart не позволяет super._x. Требуем POSITIONAL super-формал.
    if (formal.isNamed) {
      throw InvalidGenerationSource(
        'Concrete-поле «$fieldName» — приватное, и суперконструктор объявляет его '
        'как ИМЕНОВАННЫЙ параметр ({required this.$fieldName}). Dart не позволяет '
        'подклассу передать приватное named-значение в super-конструктор. Сделайте '
        'параметр позиционным: «${element.name}(this.$fieldName);», или сделайте '
        'поле public/abstract.', element: f);
    }
    // Публичный параметр в подклассе → позиционная передача в super.
    final paramName = _ctorParamName(f);
    ctorParams.add('required $typeStr $paramName');
    positionalSuperArgs.add(paramName);
  } else {
    // Публичное поле: текущее поведение — required super.field.
    ctorParams.add('required super.$fieldName');
  }
}
```

Затем при эмиссии конструктора (блок 316-321): если `positionalSuperArgs` непустой, добавить `super(${positionalSuperArgs.join(', ')})` в initializer-list **перед** signal-инициализаторами.

### 2. Детектор коллизий `_checkNameCollisions` (строки 363-412)

Добавить проверку для **stripped-имён параметров** приватных полей: приватное `_count` создаёт публичный параметр `count`, который конфликтует с публичным полем `count`. Внести в `reactiveFields`/`plainFields` циклы дополнительный `checkName(paramName, ...)`, когда поле приватное.

### 3. Тесты `packages/signals_store_generator/test/store_generator_test.dart`

**Исправить существующие тесты приватных полей (строки 272-325):** обновить матчи — теперь параметр публичный:
- `required int count` (вместо `required int _count`)
- `_count$` / `_count` (signal/геттер остаются приватными) — без изменений

**Добавить новую группу `audit: private field compilation` с реальной компиляцией:**
- C-private-1: private abstract → публичный `count` param, компилируемость проверена через dart analyzer на сгенерированном коде (не только `contains`).
- C-private-2: private concrete positional super → `super(secret)` в initializer-list.
- C-private-3: private concrete **named** super → build error с понятным сообщением (новая валидация).
- C-private-4: false-positive C4 убран — positional private concrete теперь валидируется и компилируется.
- C-private-5: коллизия `count` + `_count` → build error про коллизию stripped-имени.
- **Метод проверки компилируемости:** расширить helper (новый `_expectCompiles`) — берёт сгенерированный код, оборачивает в минимальную программу в том же пакете (`tool/_codegen_check.dart`), запускает `dart analyze`, asserts 0 ошибок. Это поднимает планку: ловит некомпилируемый код, который `contains`-матчеры пропускают.

### 4. Документация

**`packages/signals_store_generator/README.md:13-16`** — обновить формулировку: приватное поле `_field` → приватный `_field$`/геттер/сеттер, но **публичный** параметр конструктора `field` (stripped). Объяснить, почему (ограничение Dart).

**`packages/signals_store_generator/CHANGELOG.md`** — добавить `## 0.4.4`:
```
- **Bugfix (private fields)**: сгенерированный для приватных полей (`abstract int _count;`,
  `final int _secret;`) код не компилировался — Dart запрещает приватные имена в
  named-параметрах, не являющихся initializing-formal, и `super._private`.
  Теперь приватное поле `_field` создаёт приватный signal/геттер/сеттер (`_field$`, `_field`),
  но **публичный** параметр конструктора `field` (без подчёркивания), форвардящий значение.
  Приватные concrete-поля с позиционным super-конструктором теперь поддерживаются
  (`super(value)`); приватные concrete-поля с именованным super-конструктором
  (`{required this._x}`) запрещены понятной ошибкой — Dart фундаментально не позволяет
  подклассу передать приватный named-параметр в super. Добавлены тесты с реальной
  компиляцией сгенерированного кода (а не только `contains`-матчеры).
```

**`packages/signals_store_generator/pubspec.yaml:6`** — `version: 0.4.3` → `0.4.4`.

### 5. Doc-comment генератора (store_generator.dart:16-27)

Обновить `{@template store_generator}` — отразить, что приватные поля получают публичный параметр конструктора.

## Порядок выполнения (build sequence)

1. **Helpers + reactive path** в store_generator.dart (`_ctorParamName`, `_isPrivateField`, блок reactive).
2. **Concrete path + C4 rewrite** в store_generator.dart.
3. **Коллизии** в `_checkNameCollisions`.
4. **Tests:** исправить существующие (272-325), добавить группу аудита с `_expectCompiles`.
5. **Запустить тесты**, подтвердить зелёный.
6. **README + CHANGELOG + pubspec bump + doc-comment.**
7. **Регенерировать example** (`build_runner`) и подтвердить, что example компилируется (`dart analyze` в `packages/signals_store_example`).

## Проверка (verification)

- `flutter test` в `packages/signals_store_generator` — все тесты зелёные, включая новую группу аудита с компиляцией.
- `dart analyze` в `packages/signals_store_example` после регенерации — 0 ошибок.
- Временные probe-файлы (`tool/probe*.dart`, `lib/_priv_*`) удалить.

## Рамки (не в этой задаче)

- Не трогаю: reactivity-детектор, computed-геттеры, generics, abstract stores — работают корректно.
- Не меняю публичный API (имена классов/методов генератора).
- Не публикую на pub.dev (только bump версии в pubspec — публикация отдельным шагом по запросу).