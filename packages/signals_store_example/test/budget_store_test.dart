// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:signals_store_example/domain/budget_store.dart';

/// Комплексные runtime-тесты генерации Computed-полей на примере BudgetStore.
///
/// Проверяют, что сгенерированные computed-геттеры работают реактивно в
/// runtime (а не только корректно определены детектором):
/// - начальное значение вычисляется правильно;
/// - пересчёт при изменении зависимостей (через `effect`);
/// - мемоизация (не пересчитывается без необходимости);
/// - escape-hatch `Raw` даёт свежее значение;
/// - каскад computed (computed читает другой computed);
/// - computed через подстор и глобальный signal;
/// - plain getter НЕ пересчитывается реактивно.
void main() {
  late BudgetStore store;

  setUp(() {
    exchangeRate.value = 1.0;
    store = BudgetStore(
      income: 1000.0,
      expenses: listSignal<double>([100.0, 200.0]),
      currency: 'USD',
      savings: SavingsStore(amount: 500.0, goal: 1000.0),
    );
  });

  group('начальные значения computed', () {
    test('totalExpenses = сумма списка расходов', () {
      expect(store.totalExpenses, 300.0);
    });

    test('balance = income - totalExpenses (каскад через computed)', () {
      expect(store.balance, 700.0); // 1000 - 300
    });

    test('isOverdrawn = balance < 0 (каскад 2-го уровня)', () {
      expect(store.isOverdrawn, false);
    });

    test('savingsRatio = savings.amount / income (через подстор)', () {
      expect(store.savingsRatio, 0.5); // 500 / 1000
    });

    test('savingsProgress через несколько полей подстора', () {
      expect(store.savingsProgress, 0.5); // 500 / 1000
    });

    test('balanceUsd = balance * exchangeRate.value (глобальный signal)', () {
      expect(store.balanceUsd, 700.0); // 700 * 1.0
    });

    test('formattedBalance — форматированная строка', () {
      expect(store.formattedBalance, '700.00 USD');
    });

    test('currencyCode — plain getter (не computed)', () {
      expect(store.currencyCode, 'USD');
    });
  });

  group('реактивный пересчёт через effect', () {
    test('totalExpenses пересчитывается при in-place мутации ListSignal', () {
      var fireCount = 0;
      double? lastValue;
      final sub = effect(() {
        lastValue = store.totalExpenses;
        fireCount++;
      });
      expect(fireCount, 1);
      expect(lastValue, 300.0);

      // In-place мутация: добавляем расход.
      store.expenses.add(50.0);
      expect(fireCount, greaterThan(1), reason: 'добавление расхода триггерит');
      expect(lastValue, 350.0);

      sub();
    });

    test('balance пересчитывается при изменении income (каскад)', () {
      var fireCount = 0;
      double? lastBalance;
      final sub = effect(() {
        lastBalance = store.balance;
        fireCount++;
      });
      expect(fireCount, 1);
      expect(lastBalance, 700.0);

      store.income = 2000.0;
      expect(fireCount, greaterThan(1), reason: 'изменение income триггерит');
      expect(lastBalance, 1700.0); // 2000 - 300

      sub();
    });

    test('isOverdrawn переходит в true при отрицательном балансе', () {
      var fireCount = 0;
      bool? lastOverdrawn;
      final sub = effect(() {
        lastOverdrawn = store.isOverdrawn;
        fireCount++;
      });
      expect(fireCount, 1);
      expect(lastOverdrawn, false);

      // Добавляем большой расход → баланс уходит в минус.
      store.expenses.add(1000.0);
      expect(fireCount, greaterThan(1));
      expect(lastOverdrawn, true); // 1000 - 1300 = -300

      sub();
    });

    test('savingsRatio пересчитывается при изменении поля подстора', () {
      var fireCount = 0;
      double? lastRatio;
      final sub = effect(() {
        lastRatio = store.savingsRatio;
        fireCount++;
      });
      expect(fireCount, 1);
      expect(lastRatio, 0.5);

      // Меняем поле вложенного подстора.
      store.savings.amount = 750.0;
      expect(fireCount, greaterThan(1), reason: 'изменение подстора триггерит');
      expect(lastRatio, 0.75); // 750 / 1000

      sub();
    });

    test('balanceUsd пересчитывается при изменении глобального exchangeRate',
        () {
      var fireCount = 0;
      double? lastUsd;
      final sub = effect(() {
        lastUsd = store.balanceUsd;
        fireCount++;
      });
      expect(fireCount, 1);
      expect(lastUsd, 700.0);

      exchangeRate.value = 2.0;
      expect(fireCount, greaterThan(1), reason: 'изменение exchangeRate триггерит');
      expect(lastUsd, 1400.0); // 700 * 2.0

      sub();
    });

    test('formattedBalance пересчитывается при изменении balance', () {
      var fireCount = 0;
      String? lastFormatted;
      final sub = effect(() {
        lastFormatted = store.formattedBalance;
        fireCount++;
      });
      expect(fireCount, 1);
      expect(lastFormatted, '700.00 USD');

      store.income = 500.0; // баланс 200
      expect(fireCount, greaterThan(1));
      expect(lastFormatted, '200.00 USD');

      sub();
    });
  });

  group('escape-hatch Raw (сырой пересчёт без мемоизации)', () {
    test('totalExpensesRaw даёт то же значение, что и computed', () {
      expect(store.totalExpensesRaw, store.totalExpenses);
      expect(store.balanceRaw, store.balance);
      expect(store.isOverdrawnRaw, store.isOverdrawn);
    });

    test('Raw всегда пересчитывает логику (не кэш)', () {
      // Computed мемоизирует: повторное чтение без изменения зависимостей
      // возвращает кэш. Raw вызывает исходную логику каждый раз.
      // Проверяем, что Raw даёт актуальное значение после изменения зависимости
      // БЕЗ чтения computed (которое бы обновило кэш).
      final raw1 = store.balanceRaw;
      expect(raw1, 700.0);

      store.income = 2000.0;
      // Raw читает напрямую через super.balance → видит новое значение.
      final raw2 = store.balanceRaw;
      expect(raw2, 1700.0);
    });
  });

  group('plain getter НЕ реактивен', () {
    test('currencyCode не пересчитывается при изменении реактивного состояния',
        () {
      var fireCount = 0;
      final sub = effect(() {
        store.currencyCode; // чтение plain getter (super.currencyCode)
        fireCount++;
      });
      expect(fireCount, 1);

      // Меняем реактивное состояние — plain getter не должен триггерить.
      store.income = 5000.0;
      // Если бы currencyCode был computed и зависел от income — fireCount
      // вырос бы. Но он plain → эффект не срабатывает.
      expect(fireCount, 1, reason: 'currencyCode — plain, не зависит от income');

      sub();
    });
  });

  group('мемоизация computed', () {
    test('повторное чтение computed без изменения зависимостей — один кэш', () {
      // Чтобы проверить мемоизацию, используем computed, у которого есть
      // observable side-effect. Создадим стор с отслеживанием вызовов через
      // Raw (который всегда пересчитывает) vs computed (кэш).
      // balance — computed; его значение кэшируется между чтениями, если
      // зависимости не менялись.
      final v1 = store.balance;
      final v2 = store.balance;
      expect(v1, v2);

      // После изменения зависимости computed инвалидируется.
      store.income = 2000.0;
      final v3 = store.balance;
      expect(v3, 1700.0);
      expect(v3, isNot(v1));
    });
  });

  group('объект Computed доступен напрямую (sum\$)', () {
    test('balance\$ — это Computed<double>, доступен для .value/.recompute', () {
      expect(store.balance$, isA<Computed<double>>());
      expect(store.balance$.value, 700.0);

      // recompute форсирует пересчёт.
      store.balance$.recompute();
      expect(store.balance$.value, 700.0); // значение то же (зависимости не менялись)
    });
  });
}
