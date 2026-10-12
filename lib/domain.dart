import 'dart:convert';

typedef Json = Map<String, dynamic>;
const jpId = '5b8d6c70-83a1-5ba8-9c2d-54b5d14e17a1';
const entityKinds = [
  'client',
  'entry',
  'shift',
  'adjustment',
  'payment',
  'category',
];

String day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String month(DateTime d) => day(d).substring(0, 7);
String brDate(String d) =>
    '${d.substring(8, 10)}/${d.substring(5, 7)}/${d.substring(0, 4)}';
String money(int cents) {
  final digits = (cents.abs() ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${cents < 0 ? '−' : ''}R\$ $digits,${(cents.abs() % 100).toString().padLeft(2, '0')}';
}

int parseMoney(String input) {
  final s = input
      .trim()
      .replaceAll('R\$', '')
      .replaceAll(' ', '')
      .replaceAll('.', '');
  if (!RegExp(r'^\d+(,\d{1,2})?$').hasMatch(s))
    throw const FormatException('Use um valor como 125,50.');
  final p = s.split(',');
  final result =
      int.parse(p[0]) * 100 +
      (p.length == 1 ? 0 : int.parse(p[1].padRight(2, '0')));
  if (result > 100000000000) throw const FormatException('Valor muito alto.');
  return result;
}

int clockMinutes(String s, {bool duration = false}) {
  if (!RegExp(r'^\d{1,3}:\d{2}$').hasMatch(s))
    throw const FormatException('Use horas e minutos: 08:30.');
  final p = s.split(':').map(int.parse).toList();
  if (p[1] > 59 || (!duration && p[0] > 23))
    throw const FormatException('Horário inválido.');
  return p[0] * 60 + p[1];
}

int workMinutes(String start, String end, int pause) {
  var n = clockMinutes(end) - clockMinutes(start);
  if (n < 0) n += 1440;
  if (pause < 0 || pause >= n)
    throw const FormatException('O intervalo deve ser menor que a jornada.');
  return n - pause;
}

int earned(int minutes, int rate) => (minutes * rate + 30) ~/ 60;
String hours(int minutes) =>
    '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}min';

enum Period { day, week, month, year }

class DateRange {
  final DateTime start, end;
  DateRange(this.start, this.end);
  factory DateRange.forDate(DateTime d, Period p) {
    final base = DateTime(d.year, d.month, d.day);
    return switch (p) {
      Period.day => DateRange(base, base.add(const Duration(days: 1))),
      Period.week => DateRange(
        base.subtract(Duration(days: base.weekday - 1)),
        base.add(Duration(days: 8 - base.weekday)),
      ),
      Period.month => DateRange(
        DateTime(d.year, d.month),
        DateTime(d.year, d.month + 1),
      ),
      Period.year => DateRange(DateTime(d.year), DateTime(d.year + 1)),
    };
  }
  bool contains(String date) =>
      date.compareTo(day(start)) >= 0 && date.compareTo(day(end)) < 0;
  String get label =>
      '${brDate(day(start))} — ${brDate(day(end.subtract(const Duration(days: 1))))}';
}

/// Immutable entity revision. Parents are all heads known at the time of editing.
class Operation {
  final String id, entity, kind, device;
  final int clock;
  final List<String> parents;
  final Json? data;
  Operation({
    required this.id,
    required this.entity,
    required this.kind,
    required this.device,
    required this.clock,
    required this.parents,
    required this.data,
  });
  Json toJson() => {
    'v': 1,
    'id': id,
    'entity': entity,
    'kind': kind,
    'device': device,
    'clock': clock,
    'parents': parents,
    'data': data,
  };
  factory Operation.fromJson(Json j) {
    if (j['v'] != 1 ||
        ![
          'client',
          'entry',
          'shift',
          'adjustment',
          'payment',
          'category',
        ].contains(j['kind']) ||
        j['clock'] is! int ||
        j['clock'] < 0) {
      throw const FormatException('Operação incompatível.');
    }
    for (final k in ['id', 'entity', 'device']) {
      if (j[k] is! String ||
          (j[k] as String).isEmpty ||
          (j[k] as String).length > 150)
        throw const FormatException('Identificador inválido.');
    }
    final op = Operation(
      id: j['id'],
      entity: j['entity'],
      kind: j['kind'],
      device: j['device'],
      clock: j['clock'],
      parents: List<String>.from(j['parents']),
      data: j['data'] == null ? null : Json.from(j['data']),
    );
    if (op.parents.contains(op.id))
      throw const FormatException('Versão circular.');
    if (op.data != null) validateData(op.kind, op.data!);
    return op;
  }
}

void validateData(String kind, Json d) {
  if (!entityKinds.contains(kind))
    throw const FormatException('Tipo de registro inválido.');
  void text(String key, {bool empty = false}) {
    if (d[key] is! String || (!empty && (d[key] as String).trim().isEmpty))
      throw FormatException('Campo obrigatório: $key.');
  }

  void number(String key, {bool zero = false}) {
    if (d[key] is! int || d[key] < (zero ? 0 : 1) || d[key] > 100000000000)
      throw FormatException('Valor inválido: $key.');
  }

  void date(String key) {
    text(key);
    final dt = DateTime.tryParse(d[key]);
    if (dt == null || day(dt) != d[key])
      throw const FormatException('Data inválida.');
  }

  for (final key in ['note', 'category']) {
    if (d[key] != null && d[key] is! String)
      throw FormatException('Texto inválido: $key.');
  }
  if (kind == 'client' || kind == 'category') {
    text('name');
    if (kind == 'client') number('rate', zero: true);
    return;
  }
  date('date');
  if (kind != 'entry') text('client');
  if (kind == 'adjustment') {
    if (d['month'] is! String ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(d['month']))
      throw const FormatException('Competência inválida.');
  }
  if (kind == 'shift') {
    number('minutes');
    number('rate');
    if (d['minutes'] > 1440)
      throw const FormatException('A jornada deve ter até 24 horas.');
    if (d['mode'] == 'clock') {
      number('pause', zero: true);
      if (workMinutes(d['start'], d['end'], d['pause']) != d['minutes'])
        throw const FormatException('Duração inconsistente.');
    } else if (d['mode'] != 'direct') {
      throw const FormatException('Modo inválido.');
    }
  } else {
    number('amount');
    if (kind == 'entry' || kind == 'adjustment') {
      text('description');
      if (d['sign'] != 1 && d['sign'] != -1)
        throw const FormatException('Tipo inválido.');
    }
    if (kind == 'payment') {
      final allocations = Json.from(d['allocations']);
      var sum = 0;
      for (final e in allocations.entries) {
        if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(e.key) ||
            e.value is! int ||
            e.value <= 0)
          throw const FormatException('Alocação inválida.');
        sum += e.value as int;
      }
      if (sum != d['amount'])
        throw const FormatException(
          'A distribuição deve corresponder ao pagamento.',
        );
    }
  }
}

class Ledger {
  final List<Operation> operations;
  final Map<String, List<Operation>> heads = {};
  final Map<String, Operation> current = {};
  Ledger(Iterable<Operation> source) : operations = source.toList() {
    final byId = <String, Operation>{};
    for (final op in operations) {
      if (byId.containsKey(op.id) &&
          jsonEncode(byId[op.id]!.toJson()) != jsonEncode(op.toJson()))
        throw const FormatException('UUID duplicado com conteúdo diferente.');
      byId[op.id] = op;
    }
    final superseded = <String>{};
    for (final op in byId.values) {
      for (final parent in op.parents) {
        final prior = byId[parent];
        if (prior == null ||
            prior.entity != op.entity ||
            prior.kind != op.kind ||
            prior.clock >= op.clock)
          throw const FormatException(
            'Histórico de versões incompleto ou inválido.',
          );
        superseded.add(parent);
      }
      heads.putIfAbsent(op.entity, () => []);
    }
    for (final op in byId.values) {
      if (!superseded.contains(op.id)) heads[op.entity]!.add(op);
    }
    for (final e in heads.entries) {
      e.value.sort((a, b) {
        final c = a.clock.compareTo(b.clock);
        return c == 0 ? a.id.compareTo(b.id) : c;
      });
      if (e.value.map((o) => o.kind).toSet().length != 1)
        throw const FormatException('Tipo de entidade inconsistente.');
      current[e.key] = e.value.last;
    }
  }
  List<Operation> get conflicts =>
      heads.values.where((h) => h.length > 1).map((h) => h.last).toList();
  List<Json> rows(String kind) => current.values
      .where((o) => o.kind == kind && o.data != null)
      .map((o) => {...o.data!, 'id': o.entity})
      .toList();
  Json? get(String id) =>
      current[id]?.data == null ? null : {...current[id]!.data!, 'id': id};
  List<Json> get transactions => [
    ...rows('entry'),
    ...rows('payment').map(
      (p) => {
        'id': p['id'],
        'payment': true,
        'amount': p['amount'],
        'sign': 1,
        'date': p['date'],
        'client': p['client'],
        'category': 'Trabalho',
        'description':
            'Pagamento • ${get(p['client'])?['name'] ?? 'Cliente removido'}',
        'note': p['note'] ?? '',
      },
    ),
  ]..sort((a, b) => (b['date'] as String).compareTo(a['date']));
  ({int income, int expenses, int balance}) finance(DateRange r) {
    var income = 0, expenses = 0;
    for (final t in transactions.where((t) => r.contains(t['date']))) {
      if (t['sign'] == 1) {
        income += t['amount'] as int;
      } else {
        expenses += t['amount'] as int;
      }
    }
    return (income: income, expenses: expenses, balance: income - expenses);
  }

  Map<String, int> debt(String client, {String? excludePayment}) {
    final values = <String, int>{};
    void add(String m, int v) =>
        values.update(m, (a) => a + v, ifAbsent: () => v);
    for (final s in rows('shift').where((s) => s['client'] == client)) {
      add(
        (s['date'] as String).substring(0, 7),
        earned(s['minutes'], s['rate']),
      );
    }
    for (final a in rows('adjustment').where((a) => a['client'] == client)) {
      add(
        a['month'] ?? (a['date'] as String).substring(0, 7),
        (a['amount'] as int) * (a['sign'] as int),
      );
    }
    for (final p in rows(
      'payment',
    ).where((p) => p['client'] == client && p['id'] != excludePayment)) {
      for (final e in Json.from(p['allocations']).entries) {
        add(e.key, -(e.value as int));
      }
    }
    return Map.fromEntries(
      values.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  int totalDebt(String client) => debt(client).values.fold(0, (a, b) => a + b);
  Map<String, int> get violations {
    final result = <String, int>{};
    final clients = <String>{};
    for (final kind in ['shift', 'adjustment', 'payment']) {
      for (final row in rows(kind)) {
        clients.add(row['client']);
        if (get(row['client']) == null) result['orphan:${row['id']}'] = 1;
      }
    }
    for (final client in clients) {
      for (final e in debt(client).entries) {
        if (e.value < 0) result['negative:$client:${e.key}'] = -e.value;
      }
    }
    return result;
  }

  Map<String, int> allocate(
    String client,
    int amount, {
    String? preferred,
    String? excludePayment,
  }) {
    final available = debt(client, excludePayment: excludePayment);
    final keys =
        available.keys
            .where((m) => preferred == null || preferred == m)
            .toList()
          ..sort();
    final result = <String, int>{};
    var left = amount;
    for (final key in keys) {
      final value = available[key]!;
      if (value <= 0) continue;
      final take = left < value ? left : value;
      if (take > 0) result[key] = take;
      left -= take;
    }
    if (left != 0 || amount <= 0)
      throw const FormatException(
        'Pagamento superior à dívida disponível. Escolha outro mês ou diminua o valor.',
      );
    return result;
  }

  List<String> get issues {
    final result = <String>[];
    for (final kind in ['shift', 'adjustment', 'payment']) {
      for (final row in rows(kind)) {
        if (get(row['client']) == null)
          result.add('Registro sem cliente: ${row['id']}');
      }
    }
    final clients = [
      ...rows('client').map((c) => c['id'] as String),
      ...rows('payment').map((p) => p['client'] as String),
    ].toSet();
    for (final id in clients) {
      for (final e in debt(id).entries) {
        if (e.value < 0)
          result.add(
            '${get(id)?['name'] ?? id} • ${e.key}: recebimentos/descontos excedem a dívida em ${money(-e.value)}. Corrija os registros.',
          );
      }
    }
    return result;
  }
}
