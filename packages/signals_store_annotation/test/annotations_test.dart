import 'package:signals_store_annotation/signals_store_annotation.dart';
import 'package:test/test.dart';

void main() {
  test('@Store has root flag defaulting to false', () {
    const store = Store(name: 'AppStore');
    expect(store.root, false);
    expect(store.abstract, false);
  });

  test('@Store(root: true) keeps the flag', () {
    const store = Store(name: 'AppStore', root: true);
    expect(store.root, true);
  });

  test('@DerivedStore carries name', () {
    const derived = DerivedStore(name: 'TodoDetailsStore');
    expect(derived.name, 'TodoDetailsStore');
  });
}
