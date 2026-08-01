// ignore_for_file: lines_longer_than_80_chars

import 'package:signals/signals.dart';
import 'package:signals_store_annotation/signals_store_annotation.dart';

part 'stores.g.dart';

/// Описание стора: два независимых имени — два класса-реализации.
@Store(name: 'FirstSomeStore')
@Store(name: 'SecondSomeStore')
abstract class SomeStoreImpl {
  abstract String name;
}
