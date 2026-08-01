import 'package:meta/meta.dart';
import 'package:signals/signals.dart';

/// Signals based solution

/// Кэш нормализации Symbol в ключ, разбитый по типам сторов.
/// Нормализация Symbol.toString() выполняется 1 раз на уникальный символ
/// (геттер- или сеттер-форму) в рамках типа стора и переиспользуется всеми
/// инстансами этого типа. Растёт пропорционально числу типов сторов (конечно).
/// 
///```dart
/// class SomeStore extends SomeStoreImpl with ReactiveStore {
///   SomeStore({required int count, required String name}) {
///     this.count = count;
///     this.name = name;
///   }
/// }
///
/// abstract class SomeStoreImpl {
///   abstract int count;
///   abstract String name;
/// }
/// ```
final Map<Type, Map<Symbol, Symbol>> _cachesByType = {};

mixin ReactiveStore {
  // Реактивные сигналы, привязанные к Symbol свойств
  final Map<Symbol, Signal<dynamic>> _signals = {};

  bool _disposed = false;

  /// Локальный кэш нормализации символов для текущего типа стора. Разделяется
  /// между всеми инстансами одного типа. [runtimeType] — рантайм-чтение одного
  /// поля объекта (O(1)), выполняется при каждом noSuchMethod; на фоне
  /// остальной работы это пренебрежимо мало.
  Map<Symbol, Symbol> get _keyCache => _cachesByType[runtimeType] ??= {};

  /// Очищает глобальный кэш нормализации символов [_cachesByType].
  ///
  /// Предназначен для тестовой изоляции: без сброса кэш накапливает записи
  /// от предыдущих тестов, что маскирует регрессии в нормализации символов.
  /// Также полезен для сброса роста кэша при интенсивном Flutter hot-reload
  /// в дев-сессиях (каждый reload регистрирует новый `Type`).
  ///
  /// Идемпотентен: безопасен к вызову на пустом кэше.
  @visibleForTesting
  static void resetCache() => _cachesByType.clear();

  /// Освобождает все сигналы и очищает внутреннее состояние.
  ///
  /// После вызова любое обращение к полям стора бросает [StateError].
  /// Во Flutter вызывать из `State.dispose()`.
  ///
  /// Идемпотентен: повторные вызовы не имеют эффекта.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final signal in _signals.values) {
      signal.dispose();
    }
    _signals.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (_disposed) {
      throw StateError(
        'ReactiveStore уже disposed: доступ к полям запрещён '
        '(${invocation.memberName})',
      );
    }

    final memberSymbol = invocation.memberName;

    // 1. Чтение поля (Геттер)
    //
    // Lazy-создание: сигнал не существует до первой записи. Чтение
    // неинициализированного поля бросает FieldInitializationError вместо
    // молчаливого возврата null (см. P2). Это делает поведение единообразным
    // для nullable и не-null полей.
    if (invocation.isGetter) {
      // Нормализуем символ в единый ключ (см. _keyOf) — обязательно и в
      // геттер-, и в сеттер-ветке, иначе приватные mangled-символы не
      // совпадут.
      final key = _keyOf(memberSymbol);
      final signal = _signals[key];
      if (signal == null) {
        throw FieldInitializationError(memberSymbol);
      }

      return signal
          .value; // signals.dart регистрирует чтение в текущем эффекте
    }

    // 2. Запись поля (Сеттер)
    if (invocation.isSetter) {
      final key = _keyOf(memberSymbol);
      final newValue = invocation.positionalArguments.first;

      // Создаём сигнал сразу с реальным значением, чтобы избежать
      // промежуточного null-состояния (см. P7).
      final signal = _signals[key] ??= Signal<dynamic>(
        newValue,
        options: SignalOptions(name: key.toString()),
      );

      signal.value = newValue; // Обновляем значение сигнала
      return null;
    }

    // 3. Вызов метода (не геттер/сеттер) — ReactiveStore поддерживает
    //    только поля. Бросаем осмысленную ошибку вместо сырого
    //    NoSuchMethodError.
    if (invocation.isMethod) {
      throw UnsupportedError(
        'ReactiveStore поддерживает только поля, методы не разрешены: '
        '${invocation.memberName}',
      );
    }

    return super.noSuchMethod(invocation);
  }

  /// Нормализация символа в единый ключ.
  ///
  /// Вызывается в ОБЕИХ ветках (геттер и сеттер). Критически важно для
  /// приватных полей: их Symbol mangled по библиотеке, поэтому getter- и
  /// setter-символы из Invocation не равны `Symbol(str)`. Нормализация
  /// через `Symbol(очищенная строка)` срезает mangling и даёт единый ключ
  /// для обеих форм. Результат кэшируется в [_keyCache].
  ///
  /// Поддерживаем оба формата Symbol.toString() в Dart:
  ///   VM:      'Symbol("count=")' / 'Symbol("count")'  (с кавычками)
  ///   dart2js: 'Symbol(count=)'    / 'Symbol(count)'     (без кавычек)
  ///
  /// Работает и для геттер-формы (без '='), и для сеттер-формы (с '=').
  /// Используем indexOf/substring вместо регекса — примитивные строковые
  /// операции существенно быстрее. При неизвестном формате падаем явно.
  Symbol _keyOf(Symbol symbol) {
    return _keyCache[symbol] ??= _normalize(symbol);
  }

  Symbol _normalize(Symbol symbol) {
    final s = symbol.toString();

    // 'Symbol("count=")' / 'Symbol(count=)' -> contentStart после '('.
    final openParen = s.indexOf('(');
    if (openParen < 0) {
      throw StateError('Неожиданный формат Symbol.toString(): "$s"');
    }
    final contentStart = openParen + 1;

    // Пропуск открывающей кавычки, если она есть (формат VM).
    final hasQuote = contentStart < s.length && s[contentStart] == '"';
    final nameStart = contentStart + (hasQuote ? 1 : 0);
    if (nameStart >= s.length) {
      throw StateError('Пустое имя поля в Symbol.toString(): "$s"');
    }

    // Имя заканчивается на '=' (сеттер) — lastIndexOf устойчив к '=' в имени.
    final eq = s.lastIndexOf('=');
    if (eq >= nameStart) {
      return Symbol(s.substring(nameStart, eq));
    }

    // Геттер-форма (без '='): имя до закрывающей кавычки (VM) или скобки
    // (dart2js).
    final closingQuote = s.lastIndexOf('"');
    final end = closingQuote >= nameStart ? closingQuote : s.lastIndexOf(')');
    if (end < nameStart) {
      throw StateError('Не удалось найти конец имени в Symbol.toString(): "$s"');
    }
    return Symbol(s.substring(nameStart, end));
  }
}

/// Ошибка чтения поля [ReactiveStore] до его инициализации.
///
/// Бросается при чтении поля, в которое ещё ни разу не записывали значение.
/// Семантически аналогична [LateInitializationError], но относится к
/// реактивным полям стора, а не к `late`-переменным.
class FieldInitializationError extends Error {
  FieldInitializationError(this.fieldName);

  /// Символ поля, чтение которого вызвало ошибку.
  final Symbol fieldName;

  @override
  String toString() {
    return 'FieldInitializationError: поле $fieldName не было '
        'инициализировано. Запишите значение перед чтением.';
  }
}
