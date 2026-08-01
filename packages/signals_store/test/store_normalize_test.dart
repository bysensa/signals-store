import 'package:test/test.dart';
import 'package:signals_store/src/store.dart';

void main() {
  // Изоляция: каждый тест начинается с чистого кэша символов.
  setUp(ReactiveStore.resetCache);
  tearDown(ReactiveStore.resetCache);

  group('symbol normalization via real field access', () {
    test('public getter and setter map to the same signal', () {
      final store = _PublicStore();

      store.count = 42;
      expect(store.count, 42);

      // Повторная запись в то же поле перезаписывает значение (а не создаёт
      // второй сигнал) — косвенное доказательство, что getter- и setter-символы
      // нормализованы к одному ключу.
      store.count = 7;
      expect(store.count, 7);
    });

    test('private field round-trip works (mangled symbol normalized)', () {
      final store = _PrivateStore();

      store._secret = 'hidden';
      expect(store._secret, 'hidden');
    });

    test('multiple fields get independent signals', () {
      final store = _MultiStore();

      store.a = 1;
      store.b = 2;
      store.c = 3;

      expect(store.a, 1);
      expect(store.b, 2);
      expect(store.c, 3);

      // Перезапись одного не затрагивает другие.
      store.a = 100;
      expect(store.a, 100);
      expect(store.b, 2);
      expect(store.c, 3);
    });

    test(
      'different store types do not share signal cache (runtimeType keying)',
      () {
        final s1 = _StoreA()..value = 'from-a';
        final s2 = _StoreB()..value = 'from-b';

        // Одинаковое имя поля, но разные runtimeType → независимые сигналы.
        expect(s1.value, 'from-a');
        expect(s2.value, 'from-b');
      },
    );

    test('reading never-written field throws FieldInitializationError', () {
      final store = _PublicStore();
      expect(
        () => store.count,
        throwsA(isA<FieldInitializationError>()),
      );
    });
  });

  // Имя сигнала в DevTools: чистая строка ('field'), а не
  // 'Symbol("field")'. Проверяется через @visibleForTesting геттер signalFor,
  // т.к. внутренний _signals приватный.
  group('signal debug name', () {
    test('Signal.name uses clean field name, not Symbol(...) toString', () {
      final store = _NameStore()..field = 1;

      final signal = store.signalFor(#field);
      expect(signal, isNotNull);
      // НЕ 'Symbol("field")' — нормализованная строка.
      expect(signal!.name, equals('field'));
    });
  });
}

// --- Fixtures: real abstract fields (не Invocation.setter) ---

abstract class _PublicImpl {
  abstract int count;
}

class _PublicStore extends _PublicImpl with ReactiveStore {}

abstract class _PrivateImpl {
  // ignore: unused_field — доступ через геттер/сеттер в тестах
  abstract String _secret;
}

class _PrivateStore extends _PrivateImpl with ReactiveStore {}

abstract class _MultiImpl {
  abstract int a;
  abstract int b;
  abstract int c;
}

class _MultiStore extends _MultiImpl with ReactiveStore {}

abstract class _StoreAImpl {
  abstract String value;
}

class _StoreA extends _StoreAImpl with ReactiveStore {}

abstract class _StoreBImpl {
  abstract String value;
}

class _StoreB extends _StoreBImpl with ReactiveStore {}

// --- Fixtures для группы 'signal debug name' ---

abstract class _NameImpl {
  abstract int field;
}

class _NameStore extends _NameImpl with ReactiveStore {}
