import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:arthur_victor/domain.dart';
import 'package:arthur_victor/store.dart';
import 'package:arthur_victor/sync.dart';

class TestAuth extends GoogleAuth {
  TestAuth(super.store) {
    email = 'teste@example.com';
  }
  @override
  Future<String?> token({bool interactive = false}) async => 'test-token';
}

class TestDrive {
  final files = <String, Json>{};
  bool failUploadOnce = false;
  http.Client client() => MockClient((request) async {
    expect(request.headers['Authorization'], 'Bearer test-token');
    if (request.method == 'POST') {
      final parts = request.body.split('\r\n');
      final objects = parts
          .where((p) => p.startsWith('{'))
          .map((p) => Json.from(jsonDecode(p)))
          .toList();
      final id = 'file-${files.length}';
      files[id] = {'name': objects[0]['name'], 'op': objects[1]};
      if (failUploadOnce) {
        failUploadOnce = false;
        return http.Response('lost acknowledgement', 503);
      }
      return http.Response(jsonEncode({'id': id}), 200);
    }
    if (request.url.queryParameters['alt'] == 'media')
      return http.Response(
        jsonEncode(files[request.url.pathSegments.last]!['op']),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    return http.Response(
      jsonEncode({
        'files': files.entries
            .map((e) => {'id': e.key, 'name': e.value['name']})
            .toList(),
      }),
      200,
    );
  });
}

void main() {
  test(
    'Drive transporte: dois dispositivos offline convergem e repetição é idempotente',
    () async {
      final a = Store(':memory:'), b = Store(':memory:'), remote = TestDrive();
      final sa = DriveSync(
            a,
            authentication: TestAuth(a),
            clientFactory: remote.client,
          ),
          sb = DriveSync(
            b,
            authentication: TestAuth(b),
            clientFactory: remote.client,
          );
      addTearDown(() {
        sa.dispose();
        sb.dispose();
        a.close();
        b.close();
      });
      a.save('entry', {
        'date': '2026-04-01',
        'amount': 10000,
        'sign': 1,
        'description': 'Android',
      });
      b.save('entry', {
        'date': '2026-04-02',
        'amount': 3000,
        'sign': -1,
        'description': 'Windows',
      });
      await sa.synchronize(interactive: true);
      await sb.synchronize(interactive: true);
      await sa.synchronize();
      await sa.synchronize();
      await sb.synchronize();
      expect(sa.status, 'Sincronizado');
      expect(sb.status, 'Sincronizado');
      expect(a.ledger.transactions.length, 2);
      expect(b.ledger.transactions.length, 2);
      expect(a.pending, isEmpty);
      expect(b.pending, isEmpty);
    },
  );
  test(
    'Drive: falha após criação remota preserva outbox e retry não duplica entidade',
    () async {
      final a = Store(':memory:'),
          b = Store(':memory:'),
          remote = TestDrive()..failUploadOnce = true;
      final sa = DriveSync(
            a,
            authentication: TestAuth(a),
            clientFactory: remote.client,
          ),
          sb = DriveSync(
            b,
            authentication: TestAuth(b),
            clientFactory: remote.client,
          );
      addTearDown(() {
        sa.dispose();
        sb.dispose();
        a.close();
        b.close();
      });
      a.save('entry', {
        'date': '2026-04-01',
        'amount': 100,
        'sign': 1,
        'description': 'Uma entrada',
      });
      await sa.synchronize(interactive: true);
      expect(sa.status, startsWith('Erro'));
      expect(a.pending, isNotEmpty);
      await sa.synchronize();
      await sb.synchronize(interactive: true);
      expect(b.ledger.transactions.length, 1);
      expect(a.pending, isEmpty);
    },
  );
}
