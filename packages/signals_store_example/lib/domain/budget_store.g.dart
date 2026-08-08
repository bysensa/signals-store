// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'budget_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

/// @Store-generated реализация стора «SavingsStore».
///
/// Реактивные (abstract) поля [SavingsImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class SavingsStore extends SavingsImpl {
  SavingsStore({required double amount, required double goal})
    : amount$ = Signal<double>(
        amount,
        options: SignalOptions<double>(name: 'SavingsStore.amount'),
      ),
      goal$ = Signal<double>(
        goal,
        options: SignalOptions<double>(name: 'SavingsStore.goal'),
      );

  final Signal<double> amount$;
  final Signal<double> goal$;

  @override
  double get amount => amount$.value;
  @override
  set amount(double value) => amount$.value = value;
  @override
  double get goal => goal$.value;
  @override
  set goal(double value) => goal$.value = value;

  void dispose() {
    amount$.dispose();
    goal$.dispose();
  }
}

/// @Store-generated реализация стора «BudgetStore».
///
/// Реактивные (abstract) поля [BudgetStoreImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class BudgetStore extends BudgetStoreImpl {
  BudgetStore({
    required double income,
    required super.currency,
    required super.expenses,
    required super.savings,
  }) : income$ = Signal<double>(
         income,
         options: SignalOptions<double>(name: 'BudgetStore.income'),
       );

  final Signal<double> income$;

  @override
  double get income => income$.value;
  @override
  set income(double value) => income$.value = value;

  late final Computed<double> balance$ = computed(
    () => balanceRaw,
    options: ComputedOptions<double>(name: 'BudgetStore.balance'),
  );
  late final Computed<double> balanceUsd$ = computed(
    () => balanceUsdRaw,
    options: ComputedOptions<double>(name: 'BudgetStore.balanceUsd'),
  );
  late final Computed<String> formattedBalance$ = computed(
    () => formattedBalanceRaw,
    options: ComputedOptions<String>(name: 'BudgetStore.formattedBalance'),
  );
  late final Computed<bool> isOverdrawn$ = computed(
    () => isOverdrawnRaw,
    options: ComputedOptions<bool>(name: 'BudgetStore.isOverdrawn'),
  );
  late final Computed<double> savingsProgress$ = computed(
    () => savingsProgressRaw,
    options: ComputedOptions<double>(name: 'BudgetStore.savingsProgress'),
  );
  late final Computed<double> savingsRatio$ = computed(
    () => savingsRatioRaw,
    options: ComputedOptions<double>(name: 'BudgetStore.savingsRatio'),
  );
  late final Computed<double> totalExpenses$ = computed(
    () => totalExpensesRaw,
    options: ComputedOptions<double>(name: 'BudgetStore.totalExpenses'),
  );

  @override
  double get balance => balance$.value;
  @override
  double get balanceRaw => super.balance;
  @override
  double get balanceUsd => balanceUsd$.value;
  @override
  double get balanceUsdRaw => super.balanceUsd;
  @override
  String get formattedBalance => formattedBalance$.value;
  @override
  String get formattedBalanceRaw => super.formattedBalance;
  @override
  bool get isOverdrawn => isOverdrawn$.value;
  @override
  bool get isOverdrawnRaw => super.isOverdrawn;
  @override
  double get savingsProgress => savingsProgress$.value;
  @override
  double get savingsProgressRaw => super.savingsProgress;
  @override
  double get savingsRatio => savingsRatio$.value;
  @override
  double get savingsRatioRaw => super.savingsRatio;
  @override
  double get totalExpenses => totalExpenses$.value;
  @override
  double get totalExpensesRaw => super.totalExpenses;
  @override
  String get currencyCode => super.currencyCode;

  void dispose() {
    income$.dispose();
    balance$.dispose();
    balanceUsd$.dispose();
    formattedBalance$.dispose();
    isOverdrawn$.dispose();
    savingsProgress$.dispose();
    savingsRatio$.dispose();
    totalExpenses$.dispose();
  }
}
