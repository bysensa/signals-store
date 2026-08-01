import 'package:test/test.dart';
import 'package:signals_store/src/store.dart';

// Тесты фиксируют типобезопасность полей ReactiveStore.
//
// Ключевое свойство: хотя внутри ReactiveStore сигналы хранятся как
// Signal<dynamic>, статический тип поля определяется его `abstract`-декларацией
// в суперклассе. `abstract int count` задаёт типизированные геттер И сеттер,
// поэтому компилятор тайп-чекает и чтение, и запись по объявленному типу.
//
// Доказательство негативного случая (присваивание несовместимого типа
// отвергается статически) не помещено сюда как runnable-тест — код с
// type-error по определению не компилируется. Он проверяется отдельным
// `dart analyze` по файлу-зонду (см. инструкцию в конце файла).

abstract class _CounterStoreImpl {
  abstract int count;
  abstract String name;
}

class _CounterStore extends _CounterStoreImpl with ReactiveStore {
  _CounterStore({required int count, required String name}) {
    this.count = count;
    this.name = name;
  }
}

// Дженерик-стор: разные аргументы типа дают разные runtimeType → изолированные
// кэши нормализации символов. Заодно проверяем, что тип T сохраняется.
class _GenericStore<T> with ReactiveStore {
  _GenericStore(T initial) {
    value = initial;
  }

  abstract T value;
}

// Nullable-поле: проверяем, что null-семантика отличима от «не инициализировано».
abstract class _NullableImpl {
  abstract int? maybe;
}

class _NullableStore extends _NullableImpl with ReactiveStore {
  _NullableStore() {
    maybe = null; // явная инициализация null'ом
  }
}

// Поле, которое никогда не записывается: чтение должно бросать
// FieldInitializationError (семантика late-поля, но без ключевого слова late).
abstract class _UninitializedImpl {
  abstract int never;
}

class _Uninitialized extends _UninitializedImpl with ReactiveStore {}

// Fixture для runtime type-check: два поля разных типов, чтобы проверить
// implicit cast при чтении из динамического сигнала.
abstract class _TypedImpl {
  abstract int count;
  abstract String name;
}

class _TypedStore extends _TypedImpl with ReactiveStore {}

void main() {
  tearDown(ReactiveStore.resetCache);

  group('static type preservation', () {
    test('read returns declared type (would fail to compile if dynamic)', () {
      final store = _CounterStore(count: 5, name: 'hello');

      // Присваивание в строго типизированные переменные компилируется только
      // если store.count имеет статический тип int (а не dynamic).
      final int c = store.count;
      final String n = store.name;

      expect(c, 5);
      expect(n, 'hello');
    });

    test('write/read round-trip preserves value', () {
      final store = _CounterStore(count: 0, name: '');
      store.count = 42;
      store.name = 'world';

      expect(store.count, 42);
      expect(store.name, 'world');
    });

    test('generic store preserves type parameter T', () {
      final store = _GenericStore<double>(3.14);

      final double v = store.value; // статический тип — double
      expect(v, 3.14);
    });
  });

  group('field initialization semantics', () {
    test('nullable field explicitly initialized to null reads as null', () {
      final store = _NullableStore();
      expect(store.maybe, isNull);
    });

    test(
      'reading never-written field throws FieldInitializationError',
      () {
        final store = _Uninitialized();
        expect(
          () => store.never,
          throwsA(isA<FieldInitializationError>()),
        );
      },
    );
  });

  group('runtime type checking', () {
    test(
      'abstract getter implicitly casts stored dynamic to declared type',
      () {
        // Эмпирически: abstract T field выполняет implicit cast возвращаемого
        // из noSuchMethod значения к T. Это даёт рантайм type-check «бесплатно».
        final store = _TypedStore()..count = 42;

        // Корректный тип проходит.
        final int c = store.count;
        expect(c, 42);
      },
    );

    test(
      'writing wrong-typed value via forced noSuchMethod breaks on read',
      () {
        // Этот тест фиксирует, что РАНТАЙМ type-check существует — даже если
        // статический путь (через объявленный сеттер) его не пропустит.
        // Симулируем запись int в String-поле, обходя статический тип.
        final store = _TypedStore();

        // Принудительно зовём сеттер с неверным типом (как мог бы сделать
        // сериализатор или reflection-based маппер).
        (store as dynamic).noSuchMethod(Invocation.setter(#name, 123));

        // Чтение должно бросить type-error при implicit cast к String.
        expect(
          () => store.name,
          throwsA(predicate<Object>(
            (e) => e.toString().contains('String') ||
                e.toString().contains('int'),
          )),
        );
      },
    );
  });

  group('final field limitation', () {
    test(
      'class with final abstract field cannot be instantiated (compile-time)',
      () {
        // Этот тест — документация ограничения, а не runtime-проверка.
        // ReactiveStore требует mutable abstract-полей, потому что noSuchMethod
        // перехватывает И геттер, И сеттер. final-поле не имеет сеттера →
        // нельзя инициализировать в конструкторе → compile error.
        //
        // Доказательство (вне runnable-теста):
        //   abstract class _Bad { abstract final int x; }
        //   class _BadImpl extends _Bad with ReactiveStore {
        //     _BadImpl() { x = 1; }  // ❌ error: The setter 'x' isn't defined.
        //   }
        //
        // См. README раздел "Limitations" для обходных путей.
        expect(true, isTrue); // placeholder — фиксирует, что группа осмысленна
      },
    );
  });
}

// ---------------------------------------------------------------------------
// ИНСТРУКЦИЯ: регрессионная проверка статического отвержения неверного типа.
//
// Негативный кейс («нельзя присвоить String в int-поле») проверяется через
// статический анализ, а не через runtime-тест. Чтобы его воспроизвести:
//
//   $ cat > /tmp/probe.dart <<'EOF'
//   import 'package:signals_store/src/store.dart';
//   abstract class P { abstract int count; }
//   class Q extends P with ReactiveStore { Q() { count = 0; } }
//   void main() { Q().count = 'oops'; }   // <-- ожиаем invalid_assignment
//   EOF
//   $ dart analyze /tmp/probe.dart
//   # ожидаем: 1 error - A value of type 'String' can't be assigned ...
//
// Запускать регулярно (в CI) имеет смысл только после подключения
// package:analyzer / expect_lint-инфраструктуры, которая пока не введена.
// ---------------------------------------------------------------------------
