import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'domain.dart';

/// SQLite is the source of truth; event writes and upload flags are transactional.
class Store {
  final Database db;
  late final String device;
  late Ledger ledger;
  void Function()? onChange;
  Store(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA foreign_keys=ON');
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > 1)
      throw StateError(
        'Banco de uma versão mais recente. Atualize o aplicativo.',
      );
    if (version == 0) {
      db.execute('BEGIN IMMEDIATE');
      try {
        db.execute(
          'CREATE TABLE operations (id TEXT PRIMARY KEY, entity TEXT NOT NULL, body TEXT NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0 CHECK(uploaded IN (0,1)))',
        );
        db.execute('CREATE INDEX operations_entity ON operations(entity)');
        db.execute(
          'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        db.execute('PRAGMA user_version=1');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
    device = setting('device') ?? const Uuid().v4();
    setSetting('device', device);
    reload();
    if (ledger.operations.isEmpty) {
      // Identical seed on both installations: no duplicate JP after first sync.
      merge([
        Operation(
          id: '47ca6cf2-5b15-55ab-8eca-9e19e7eb3053',
          entity: jpId,
          kind: 'client',
          device: '00000000-0000-0000-0000-000000000000',
          clock: 0,
          parents: [],
          data: {'name': 'JP', 'rate': 0, 'note': ''},
        ),
      ], uploaded: false);
    }
  }
  void reload() => ledger = Ledger(
    db
        .select('SELECT body FROM operations')
        .map(
          (r) => Operation.fromJson(Json.from(jsonDecode(r['body'] as String))),
        ),
  );
  String? setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) => db.execute(
    'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  List<Operation> get pending => db
      .select('SELECT body FROM operations WHERE uploaded=0')
      .map((r) => Operation.fromJson(Json.from(jsonDecode(r['body']))))
      .toList();
  void markUploaded(String id) =>
      db.execute('UPDATE operations SET uploaded=1 WHERE id=?', [id]);
  String save(
    String kind,
    Json? data, {
    String? id,
    List<String>? expectedHeads,
  }) {
    if (!entityKinds.contains(kind))
      throw const FormatException('Tipo de registro inválido.');
    if (id != null && expectedHeads != null) {
      final actual = ledger.heads[id]?.map((o) => o.id).toSet() ?? <String>{};
      if (actual.length != expectedHeads.length ||
          !actual.containsAll(expectedHeads)) {
        throw StateError(
          'Este registro mudou enquanto o formulário estava aberto. Feche e abra novamente para revisar a versão atual.',
        );
      }
    }
    if (data != null) {
      data = {...data}..remove('id');
      validateData(kind, data);
      if (kind == 'adjustment' &&
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(data['month'] ?? ''))
        throw const FormatException('Competência inválida.');
    }
    final entity = id ?? const Uuid().v4();
    if (ledger.current[entity] != null && ledger.current[entity]!.kind != kind)
      throw StateError('Tipo de registro incompatível.');
    final clock =
        ledger.operations.fold<int>(0, (v, o) => v > o.clock ? v : o.clock) + 1;
    final op = Operation(
      id: const Uuid().v4(),
      entity: entity,
      kind: kind,
      device: device,
      clock: clock,
      parents: ledger.heads[entity]?.map((o) => o.id).toList() ?? [],
      data: data,
    );
    final next = Ledger([...ledger.operations, op]);
    // Corrections to remote inconsistencies are allowed if they do not introduce new ones.
    final before = ledger.violations;
    for (final violation in next.violations.entries) {
      if (violation.value > (before[violation.key] ?? 0)) {
        throw const FormatException(
          'Esta alteração deixaria uma dívida negativa ou um registro sem cliente. Corrija os pagamentos/descontos vinculados antes de alterar o serviço.',
        );
      }
    }
    merge([op], uploaded: false);
    return entity;
  }

  void merge(List<Operation> incoming, {bool uploaded = true}) {
    final existing = {for (final o in ledger.operations) o.id: o};
    for (final op in incoming) {
      Operation.fromJson(op.toJson());
      final old = existing[op.id];
      if (old != null && jsonEncode(old.toJson()) != jsonEncode(op.toJson()))
        throw const FormatException('Operação duplicada inconsistente.');
      existing[op.id] = op;
    }
    Ledger(existing.values); // Validate the entire DAG before mutating SQLite.
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final op in incoming) {
        db.execute(
          'INSERT OR IGNORE INTO operations(id,entity,body,uploaded) VALUES(?,?,?,?)',
          [op.id, op.entity, jsonEncode(op.toJson()), uploaded ? 1 : 0],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    reload();
    onChange?.call();
  }

  String backup() {
    final payload = jsonEncode({
      'schema': 1,
      'operations': ledger.operations.map((o) => o.toJson()).toList(),
    });
    return jsonEncode({
      'format': 'arthur-victor-backup',
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
  }

  List<Operation> validateBackup(String text) {
    final envelope = Json.from(jsonDecode(text));
    if (envelope['format'] != 'arthur-victor-backup' ||
        envelope['payload'] is! String ||
        sha256.convert(utf8.encode(envelope['payload'])).toString() !=
            envelope['sha256'])
      throw const FormatException('Backup corrompido ou incompatível.');
    final body = Json.from(jsonDecode(envelope['payload']));
    if (body['schema'] != 1)
      throw const FormatException('Versão do backup não suportada.');
    final ops = (body['operations'] as List)
        .map((o) => Operation.fromJson(Json.from(o)))
        .toList();
    Ledger(ops);
    return ops;
  }

  /// Restore merges history without destructive replacement; restored records are uploaded.
  void restore(String text) => merge(validateBackup(text), uploaded: false);
  void close() => db.close();
}

String csvCell(Object? value) {
  var s = value?.toString() ?? '';
  if (RegExp(r'^[=+@\-\t\r]').hasMatch(s) &&
      !RegExp(r'^-?\d+,\d{2}$').hasMatch(s))
    s = "'$s";
  return '"${s.replaceAll('"', '""')}"';
}

String exportCsv(Ledger ledger, DateRange range) {
  String decimal(int cents) =>
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100},${(cents.abs() % 100).toString().padLeft(2, '0')}';
  final rows = <List<Object?>>[
    [
      'Tipo',
      'Data',
      'Cliente / descrição',
      'Categoria / competência',
      'Minutos',
      'Valor em reais',
    ],
    ...ledger.transactions
        .where((t) => range.contains(t['date']))
        .map(
          (t) => [
            t['sign'] == 1 ? 'Entrada' : 'Saída',
            brDate(t['date']),
            t['description'],
            t['category'] ?? '',
            '',
            '${t['sign'] == -1 ? '-' : ''}${(t['amount'] as int) ~/ 100},${((t['amount'] as int) % 100).toString().padLeft(2, '0')}',
          ],
        ),
    ...ledger
        .rows('shift')
        .where((s) => range.contains(s['date']))
        .map(
          (s) => [
            'Jornada',
            brDate(s['date']),
            ledger.get(s['client'])?['name'],
            '',
            s['minutes'],
            decimal(earned(s['minutes'], s['rate'])),
          ],
        ),
    ...ledger
        .rows('client')
        .expand(
          (c) => ledger
              .debt(c['id'])
              .entries
              .map(
                (e) => [
                  'Dívida acumulada',
                  '',
                  c['name'],
                  e.key,
                  '',
                  decimal(e.value),
                ],
              ),
        ),
  ];
  return '\uFEFF${rows.map((r) => r.map(csvCell).join(';')).join('\r\n')}';
}
