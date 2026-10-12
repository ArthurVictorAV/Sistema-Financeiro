import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arthur_victor/domain.dart';
import 'package:arthur_victor/store.dart';

void main() {
  late Store s;
  setUp(() => s = Store(':memory:'));
  tearDown(() => s.close());
  void extra(String date, int amount, {String who = jpId, int sign = 1}) =>
      s.save('adjustment', {
        'client': who,
        'date': date,
        'month': date.substring(0, 7),
        'amount': amount,
        'sign': sign,
        'description': 'Serviço',
        'note': '',
      });
  String pay(int value, String date, {String? month, String who = jpId}) =>
      s.save('payment', {
        'client': who,
        'date': date,
        'amount': value,
        'allocations': s.ledger.allocate(who, value, preferred: month),
        'note': '',
      });
  void debt5000() {
    extra('2026-04-01', 200000);
    extra('2026-05-01', 100000);
    extra('2026-06-01', 200000);
  }

  DateRange period(String date) =>
      DateRange.forDate(DateTime.parse(date), Period.month);
  test('1 e 10: saldo mensal não acumula e dívida anterior permanece', () {
    for (final e in [
      ('2026-01-10', 200000, 1),
      ('2026-01-11', 80000, -1),
      ('2026-02-10', 50000, 1),
      ('2026-02-11', 70000, -1),
    ]) {
      s.save('entry', {
        'date': e.$1,
        'amount': e.$2,
        'sign': e.$3,
        'description': 'Teste',
      });
    }
    extra('2026-01-05', 12300);
    expect(s.ledger.finance(period('2026-01-01')).balance, 120000);
    expect(s.ledger.finance(period('2026-02-01')).balance, -20000);
    expect(s.ledger.totalDebt(jpId), 12300);
  });
  test('2: três meses acumulam 5000', () {
    debt5000();
    expect(s.ledger.totalDebt(jpId), 500000);
  });
  test('3: pagamento parcial aplicado em abril', () {
    debt5000();
    pay(100000, '2026-07-01', month: '2026-04');
    expect(s.ledger.debt(jpId), {
      '2026-04': 100000,
      '2026-05': 100000,
      '2026-06': 200000,
    });
    expect(s.ledger.totalDebt(jpId), 400000);
  });
  test(
    '4: dinheiro recebido em julho não é receita em abril, nem duplicado',
    () {
      debt5000();
      pay(100000, '2026-07-01', month: '2026-04');
      expect(s.ledger.finance(period('2026-04-01')).income, 0);
      expect(s.ledger.finance(period('2026-07-01')).income, 100000);
      expect(s.ledger.transactions.length, 1);
    },
  );
  test('5: 08:00–12:30, R\$25 = R\$112,50', () {
    expect(workMinutes('08:00', '12:30', 0), 270);
    expect(earned(270, 2500), 11250);
  });
  test('6: mudar tarifa não recalcula jornadas antigas', () {
    s.save('shift', {
      'date': '2026-06-01',
      'client': jpId,
      'minutes': 270,
      'rate': 2500,
      'mode': 'direct',
    });
    s.save('client', {'name': 'JP', 'rate': 3000}, id: jpId);
    expect(s.ledger.totalDebt(jpId), 11250);
  });
  test('7: operações independentes, repetição e ordem convergem', () {
    final b = Store(':memory:');
    addTearDown(b.close);
    extra('2026-04-01', 20000);
    b.save('entry', {
      'date': '2026-04-02',
      'amount': 3000,
      'sign': -1,
      'description': 'Barbearia',
    });
    s.merge(b.ledger.operations);
    b.merge(s.ledger.operations.reversed.toList());
    s.merge(b.ledger.operations);
    expect(s.ledger.rows('entry').length, 1);
    expect(b.ledger.totalDebt(jpId), 20000);
    expect(s.ledger.operations.length, b.ledger.operations.length);
  });
  test('8: corrigir e cancelar pagamento atualiza as duas visões', () {
    debt5000();
    final id = pay(100000, '2026-07-01');
    s.save('payment', {
      'date': '2026-08-01',
      'client': jpId,
      'amount': 50000,
      'allocations': s.ledger.allocate(jpId, 50000, excludePayment: id),
    }, id: id);
    expect(s.ledger.totalDebt(jpId), 450000);
    expect(s.ledger.finance(period('2026-07-01')).income, 0);
    expect(s.ledger.finance(period('2026-08-01')).income, 50000);
    s.save('payment', null, id: id);
    expect(s.ledger.totalDebt(jpId), 500000);
    expect(s.ledger.transactions, isEmpty);
  });
  test('9: clientes independentes', () {
    final id = s.save('client', {'name': 'Carlos', 'rate': 0});
    extra('2026-04-01', 10000);
    extra('2026-04-01', 5000, who: id);
    pay(3000, '2026-04-10', who: id);
    expect(s.ledger.totalDebt(jpId), 10000);
    expect(s.ledger.totalDebt(id), 2000);
  });
  test('intervalos, meia-noite, arredondamentos e moeda exata', () {
    expect(workMinutes('22:00', '02:30', 30), 240);
    expect(earned(1, 100), 2);
    expect(earned(1, 30), 1);
    expect(parseMoney('1.234,56'), 123456);
    expect(() => workMinutes('08:00', '09:00', 60), throwsFormatException);
    expect(() => clockMinutes('24:01'), throwsFormatException);
  });
  test('jornada noturna pertence ao mês de início', () {
    s.save('shift', {
      'date': '2026-04-30',
      'client': jpId,
      'minutes': 240,
      'rate': 2500,
      'mode': 'clock',
      'start': '22:00',
      'end': '02:30',
      'pause': 30,
    });
    expect(s.ledger.debt(jpId), {'2026-04': 10000});
  });
  test('FIFO atravessa competências e rejeita excedentes', () {
    debt5000();
    expect(s.ledger.allocate(jpId, 250000), {
      '2026-04': 200000,
      '2026-05': 50000,
    });
    expect(() => s.ledger.allocate(jpId, 600000), throwsFormatException);
    expect(
      () => s.ledger.allocate(jpId, 300000, preferred: '2026-04'),
      throwsFormatException,
    );
  });
  test('desconto reduz dívida sem gerar entrada', () {
    extra('2026-04-01', 10000);
    extra('2026-04-02', 3000, sign: -1);
    expect(s.ledger.totalDebt(jpId), 7000);
    expect(s.ledger.transactions, isEmpty);
  });
  test('excluir serviço pago é rejeitado atomicamente', () {
    extra('2026-04-01', 10000);
    final id = s.ledger.rows('adjustment').first['id'];
    pay(10000, '2026-04-05');
    expect(() => s.save('adjustment', null, id: id), throwsFormatException);
    expect(s.ledger.rows('adjustment').length, 1);
  });
  test('conflito preserva versões e resolução manual converge', () {
    final b = Store(':memory:');
    addTearDown(b.close);
    s.save('client', {'name': 'JP Android', 'rate': 2500}, id: jpId);
    b.save('client', {'name': 'JP Windows', 'rate': 3000}, id: jpId);
    s.merge(b.ledger.operations);
    b.merge(s.ledger.operations);
    expect(s.ledger.conflicts.length, 1);
    expect(s.ledger.get(jpId), b.ledger.get(jpId));
    s.save('client', {'name': 'JP confirmado', 'rate': 2800}, id: jpId);
    b.merge(s.ledger.operations);
    expect(b.ledger.conflicts, isEmpty);
    expect(b.ledger.get(jpId)!['rate'], 2800);
  });
  test('exclusão propaga e não ressuscita por backup antigo', () {
    final id = s.save('entry', {
      'date': '2026-04-01',
      'amount': 100,
      'sign': 1,
      'description': 'A',
    });
    final backup = s.backup();
    s.save('entry', null, id: id);
    s.restore(backup);
    expect(s.ledger.rows('entry'), isEmpty);
  });
  test('pagamentos concorrentes excessivos são sinalizados e corrigíveis', () {
    extra('2026-04-01', 10000);
    final b = Store(':memory:');
    addTearDown(b.close);
    b.merge(s.ledger.operations);
    pay(8000, '2026-04-02');
    final second = b.save('payment', {
      'date': '2026-04-02',
      'client': jpId,
      'amount': 8000,
      'allocations': {'2026-04': 8000},
    });
    s.merge(b.ledger.operations);
    expect(s.ledger.issues, isNotEmpty);
    s.save('payment', null, id: second);
    expect(s.ledger.issues, isEmpty);
    expect(s.ledger.totalDebt(jpId), 2000);
  });
  test('backup checksum e restauração idempotente', () {
    debt5000();
    pay(100000, '2026-07-01');
    final backup = s.backup();
    final b = Store(':memory:');
    addTearDown(b.close);
    b.restore(backup);
    b.restore(backup);
    expect(b.ledger.totalDebt(jpId), 400000);
    expect(b.ledger.rows('payment').length, 1);
    final corrupt = Json.from(jsonDecode(backup));
    corrupt['sha256'] = 'bad';
    expect(() => b.restore(jsonEncode(corrupt)), throwsFormatException);
  });
  test('persistência sobrevive ao fechamento', () {
    final dir = Directory.systemTemp.createTempSync('av-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/data.sqlite';
    final a = Store(path);
    a.save('entry', {
      'date': '2026-01-01',
      'amount': 123,
      'sign': 1,
      'description': 'Persistente',
    });
    a.close();
    final b = Store(path);
    expect(b.ledger.transactions.single['amount'], 123);
    b.close();
  });
  test('formulário antigo não sobrescreve uma versão recebida depois', () {
    final heads = s.ledger.heads[jpId]!.map((o) => o.id).toList();
    s.save('client', {'name': 'JP atualizado', 'rate': 3000}, id: jpId);
    expect(
      () => s.save(
        'client',
        {'name': 'Versão antiga', 'rate': 2500},
        id: jpId,
        expectedHeads: heads,
      ),
      throwsStateError,
    );
    expect(s.ledger.get(jpId)!['name'], 'JP atualizado');
  });
  test('CSV usa BOM, ponto e vírgula e protege fórmula em campo', () {
    expect(csvCell('=1+1'), '"\'=1+1"');
    expect(
      exportCsv(s.ledger, period('2026-01-01')).startsWith('\uFEFF'),
      isTrue,
    );
  });
  test('semana começa segunda e datas inválidas são rejeitadas', () {
    final r = DateRange.forDate(DateTime(2026, 4, 5), Period.week);
    expect(day(r.start), '2026-03-30');
    expect(r.contains('2026-04-05'), isTrue);
    expect(r.contains('2026-04-06'), isFalse);
    expect(
      () => s.save('entry', {
        'date': '2026-02-30',
        'amount': 100,
        'sign': 1,
        'description': 'Inválido',
      }),
      throwsFormatException,
    );
  });
}
