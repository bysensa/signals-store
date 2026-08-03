// ignore_for_file: lines_longer_than_80_chars

import 'package:signals/signals.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';

part 'budget_store.g.dart';

/// Демонстрационный стор для проверки генерации Computed-полей.
///
/// Покрывает все ключевые сценарии детектора реактивности:
/// - computed, читающий abstract-поля и Signal-коллекции;
/// - computed-каскад (computed читает другой computed);
/// - computed, читающий поля вложенного подстора (глубокая цепочка);
/// - computed, читающий глобальный signal через `.value`;
/// - computed, делегирующий в helper-метод;
/// - plain getter (без reactive-ссылок) для контраста.

/// Глобальный signal-курс валюты (USD). Демонстрирует детекцию через `.value`
/// на внешнем signal-объекте (G12).
final exchangeRate = signal<double>(1.0);

/// Подстор накоплений.
///
/// concrete-поле в [BudgetStoreImpl] — доступ к его полям реактивен через
/// собственные signals.
@Store(name: 'SavingsStore')
abstract class SavingsImpl {
  /// Сумма накоплений.
  abstract double amount;

  /// Цель накоплений (для расчёта прогресса).
  abstract double goal;
}

/// Главный стор бюджета.
@Store(name: 'BudgetStore')
abstract class BudgetStoreImpl {
  /// Доход.
  abstract double income;

  /// Список расходов (реактивная коллекция через ListSignal).
  final ListSignal<double> expenses;

  /// Валюта (НЕ реактивно в геттерах — plain).
  final String currency;

  /// Вложенный стор накоплений (concrete-поле — подстор).
  final SavingsImpl savings;

  BudgetStoreImpl({
    required this.expenses,
    required this.currency,
    required this.savings,
  });

  // --- Computed-геттеры (читают реактивное состояние) ---

  /// Сумма всех расходов. Читает `expenses` (ListSignal) через `.fold`.
  double get totalExpenses => expenses.fold(0.0, (sum, e) => sum + e);

  /// Баланс: доход минус расходы. Каскад — читает computed `totalExpenses`.
  double get balance => income - totalExpenses;

  /// В минусе ли баланс. Каскад 2-го уровня — читает computed `balance`.
  bool get isOverdrawn => balance < 0;

  /// Доля накоплений от дохода. Читает поле подстора `savings.amount`.
  double get savingsRatio => income <= 0 ? 0.0 : savings.amount / income;

  /// Прогресс к цели накоплений (через подстор). Демонстрирует доступ к
  /// нескольким полям подстора.
  double get savingsProgress =>
      savings.goal <= 0 ? 0.0 : (savings.amount / savings.goal).clamp(0.0, 1.0);

  /// Баланс в USD. Читает глобальный signal `exchangeRate` через `.value`
  /// (G12 — детекция внешнего signal).
  double get balanceUsd => balance * exchangeRate.value;

  /// Форматированный баланс. Передаёт reactive `balance` как аргумент в
  /// helper-метод `_format` (dataflow через аргумент вызова: чтение `balance`
  /// в позиции аргумента реактивно, поэтому геттер становится computed).
  String get formattedBalance => _format(balance);

  /// Helper-метод для форматирования произвольной суммы. Сам по себе НЕ
  /// реактивен (параметр `value` — не свойство стора), но вызывается из
  /// computed-геттеров с reactive аргументами. Чтение reactive-значения
  /// происходит в точке вызова (передача аргумента), а не в теле helper'а —
  /// детектор корректно это определяет.
  String _format(double value) => '${value.toStringAsFixed(2)} $currency';

  // --- Plain getter (НЕ reactive) ---

  /// Короткое обозначение валюты. Читает только `currency` (concrete-поле,
  /// не стор и не Signal) → НЕ становится computed.
  String get currencyCode => currency.toUpperCase();
}
