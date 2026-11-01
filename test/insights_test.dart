import 'package:flutter_test/flutter_test.dart';
import 'package:arthur_victor/domain.dart';
import 'package:arthur_victor/insights.dart';
import 'package:arthur_victor/store.dart';

void main() {
  late Store store;
  setUp(() => store = Store(':memory:'));
  tearDown(() => store.close());
  Json reserve(int balance, {String group = 'bank'}) => {
    'name': 'Minha reserva',
    'balance': balance,
    'group': group,
    'date': '2026-10-30',
    'note': '',
  };
  test('Patrimônio soma saldos atuais sem entrar no resultado mensal', () {
    store.save('asset', reserve(200000));
    store.save('asset', reserve(500000, group: 'investment'));
    store.save('asset', reserve(30000, group: 'cash'));
    expect(Portfolio(store.ledger).total, 730000);
    expect(Portfolio(store.ledger).groupTotal('investment'), 500000);
    expect(
      store.ledger
          .finance(DateRange.forDate(DateTime(2026, 10), Period.month))
          .income,
      0,
    );
    expect(store.ledger.totalDebt(jpId), 0);
    expect(store.ledger.transactions, isEmpty);
  });
  test('Atualizar saldo substitui valor e preserva histórico', () {
    final id = store.save('asset', reserve(500000));
    store.save('asset', reserve(520000), id: id);
    expect(Portfolio(store.ledger).total, 520000);
    expect(store.ledger.operations.where((o) => o.entity == id).length, 2);
    expect(store.ledger.transactions, isEmpty);
  });
  test('Reservas sobrevivem a backup, sincronização e exclusão', () {
    final id = store.save('asset', reserve(10000, group: 'cash'));
    final backup = store.backup();
    final other = Store(':memory:');
    addTearDown(other.close);
    other.restore(backup);
    other.restore(backup);
    expect(Portfolio(other.ledger).total, 10000);
    store.save('asset', null, id: id);
    other.merge(store.ledger.operations);
    expect(Portfolio(other.ledger).total, 0);
    other.restore(backup);
    expect(Portfolio(other.ledger).total, 0);
  });
  test('Alterações concorrentes de patrimônio são preservadas', () {
    final id = store.save('asset', reserve(10000));
    final other = Store(':memory:');
    addTearDown(other.close);
    other.merge(store.ledger.operations);
    store.save('asset', reserve(20000), id: id);
    other.save('asset', reserve(30000), id: id);
    store.merge(other.ledger.operations);
    other.merge(store.ledger.operations);
    expect(store.ledger.conflicts.length, 1);
    expect(Portfolio(store.ledger).total, Portfolio(other.ledger).total);
  });
  test('Saldo zero é válido, negativo ou grupo desconhecido não', () {
    store.save('asset', reserve(0));
    expect(() => store.save('asset', reserve(-1)), throwsFormatException);
    expect(
      () => store.save('asset', reserve(1, group: 'invalid')),
      throwsFormatException,
    );
  });
  test('Aviso de atualização usa data de cada conta', () {
    store.save('asset', {...reserve(100), 'date': '2026-09-01'});
    store.save('asset', reserve(200));
    expect(Portfolio(store.ledger).staleCount(DateTime(2026, 10, 30)), 1);
  });
  test('Período anterior respeita virada de ano e fevereiro', () {
    final r = previousPeriod(DateTime(2026, 1, 31), Period.month);
    expect(day(r.start), '2025-12-01');
    expect(day(r.end), '2026-01-01');
    final feb = previousPeriod(DateTime(2026, 3, 31), Period.month);
    expect(day(feb.start), '2026-02-01');
    expect(day(feb.end), '2026-03-01');
  });
  test('Categorias são ordenadas e não misturam outros meses nem entradas', () {
    for (final e in [
      ('2026-10-01', 3000, -1, 'Transporte'),
      ('2026-10-02', 6000, -1, 'Alimentação'),
      ('2026-09-01', 90000, -1, 'Outros'),
      ('2026-10-01', 9000, 1, 'Salário'),
    ]) {
      store.save('entry', {
        'date': e.$1,
        'amount': e.$2,
        'sign': e.$3,
        'category': e.$4,
        'description': 'Teste',
      });
    }
    final result = ReportData(
      store.ledger,
      DateRange.forDate(DateTime(2026, 10), Period.month),
    );
    expect(result.categories.map((e) => e.key), ['Alimentação', 'Transporte']);
    expect(result.categories.fold<int>(0, (a, b) => a + b.value), 9000);
  });
}
