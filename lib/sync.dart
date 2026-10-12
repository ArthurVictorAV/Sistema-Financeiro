import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'domain.dart';
import 'store.dart';

const driveScope = 'https://www.googleapis.com/auth/drive.appdata';

class GoogleAuth {
  final Store store;
  final FlutterSecureStorage vault = const FlutterSecureStorage();
  GoogleSignInAccount? account;
  bool initialized = false;
  String? email;
  GoogleAuth(this.store);
  Future<void> initAndroid() async {
    if (initialized) return;
    final client = store.setting('androidServerId');
    if (client == null || client.isEmpty)
      throw StateError(
        'Configure o ID OAuth Web do projeto Google nas configurações.',
      );
    await GoogleSignIn.instance.initialize(serverClientId: client);
    initialized = true;
  }

  Future<String?> token({bool interactive = false}) async {
    if (Platform.isAndroid) {
      await initAndroid();
      if (interactive) {
        account = await GoogleSignIn.instance.authenticate(
          scopeHint: [driveScope],
        );
      } else {
        account ??= await GoogleSignIn.instance
            .attemptLightweightAuthentication();
      }
      if (account == null) return null;
      email = account!.email;
      var auth = await account!.authorizationClient.authorizationForScopes([
        driveScope,
      ]);
      if (auth == null && interactive)
        auth = await account!.authorizationClient.authorizeScopes([driveScope]);
      return auth?.accessToken;
    }
    final saved = await vault.read(key: 'googleTokens');
    Json? tokens = saved == null ? null : Json.from(jsonDecode(saved));
    if (tokens != null && !interactive) {
      email = tokens['email'];
      if ((tokens['expires'] as int) >
          DateTime.now().millisecondsSinceEpoch + 60000)
        return tokens['access_token'];
      if (tokens['refresh_token'] != null) {
        final response = await http
            .post(
              Uri.https('oauth2.googleapis.com', '/token'),
              body: {
                'client_id': store.setting('desktopClientId') ?? '',
                'client_secret':
                    await vault.read(key: 'desktopClientSecret') ?? '',
                'refresh_token': tokens['refresh_token'],
                'grant_type': 'refresh_token',
              },
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          tokens = {...tokens, ...Json.from(jsonDecode(response.body))};
          await persist(tokens);
          return tokens['access_token'];
        }
        if (response.statusCode >= 500)
          throw const HttpException('Google indisponível. Tente novamente.');
        if (!interactive)
          throw StateError(
            'Autorização expirada. Conecte a conta Google novamente.',
          );
      }
    }
    if (!interactive) return null;
    final id = store.setting('desktopClientId') ?? '';
    if (id.isEmpty) throw StateError('Configure o ID OAuth Desktop.');
    final random = Random.secure();
    String nonce() => base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final verifier = nonce(), state = nonce();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}/callback';
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': id,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': '$driveScope openid email',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication))
        throw StateError('Não foi possível abrir o navegador.');
      final completer = Completer<String>();
      server.listen((request) async {
        final q = request.uri.queryParameters;
        if (request.uri.path != '/callback' || q['state'] != state) {
          request.response.statusCode = 400;
          request.response.write('Solicitação inválida.');
        } else if (q['code'] == null) {
          request.response.write('Autorização cancelada. Volte ao aplicativo.');
          if (!completer.isCompleted)
            completer.completeError(StateError('Autorização cancelada.'));
        } else {
          request.response.write(
            'Conta conectada. Você pode voltar ao AVFinanças.',
          );
          if (!completer.isCompleted) completer.complete(q['code']);
        }
        await request.response.close();
      });
      final code = await completer.future.timeout(const Duration(minutes: 3));
      final response = await http
          .post(
            Uri.https('oauth2.googleapis.com', '/token'),
            body: {
              'client_id': id,
              'client_secret':
                  await vault.read(key: 'desktopClientSecret') ?? '',
              'code': code,
              'code_verifier': verifier,
              'redirect_uri': redirect,
              'grant_type': 'authorization_code',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200)
        throw StateError(
          'Google recusou a autenticação (${response.statusCode}). Confira as credenciais Desktop.',
        );
      tokens = Json.from(jsonDecode(response.body));
      // Identity comes directly from the TLS-protected Google token endpoint.
      final claims = Json.from(
        jsonDecode(
          utf8.decode(
            base64Url.decode(
              base64Url.normalize((tokens['id_token'] as String).split('.')[1]),
            ),
          ),
        ),
      );
      email = claims['email'] as String;
      tokens['email'] = email;
      await persist(tokens);
      return tokens['access_token'];
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> persist(Json tokens) async {
    tokens['expires'] =
        DateTime.now().millisecondsSinceEpoch +
        (tokens['expires_in'] as int) * 1000;
    await vault.write(key: 'googleTokens', value: jsonEncode(tokens));
  }

  Future<void> disconnect() async {
    if (Platform.isAndroid && initialized)
      await GoogleSignIn.instance.signOut();
    await vault.delete(key: 'googleTokens');
    account = null;
    email = null;
    store.setSetting('connected', 'false');
  }
}

class DriveSync extends ChangeNotifier {
  final Store store;
  late final GoogleAuth auth;
  final http.Client Function() clientFactory;
  bool busy = false;
  String status = 'Somente neste dispositivo';
  Timer? debounce, retry;
  DriveSync(
    this.store, {
    GoogleAuth? authentication,
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new {
    auth = authentication ?? GoogleAuth(store);
  }
  void changed() {
    status = 'Alterações pendentes';
    notifyListeners();
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 3), () => synchronize());
  }

  Future<void> synchronize({bool interactive = false}) async {
    if (busy || (!interactive && store.setting('connected') != 'true')) return;
    busy = true;
    status = 'Sincronizando';
    notifyListeners();
    retry?.cancel();
    final client = clientFactory();
    try {
      final token = await auth.token(interactive: interactive);
      if (token == null)
        throw StateError('Conecte sua conta Google para sincronizar.');
      final bound = store.setting('boundEmail');
      if (bound != null && bound != auth.email)
        throw StateError(
          'Este banco pertence a $bound. Use a mesma conta nos dois dispositivos.',
        );
      store.setSetting('boundEmail', auth.email!);
      store.setSetting('connected', 'true');
      final headers = {'Authorization': 'Bearer $token'};
      final incoming = <Operation>[];
      String? page;
      do {
        final response = await client
            .get(
              Uri.https('www.googleapis.com', '/drive/v3/files', {
                'spaces': 'appDataFolder',
                'q': "trashed = false and name contains 'av-op-'",
                'fields': 'nextPageToken,files(id,name)',
                'pageSize': '1000',
                if (page != null) 'pageToken': page,
              }),
              headers: headers,
            )
            .timeout(const Duration(seconds: 30));
        check(response);
        final data = Json.from(jsonDecode(response.body));
        for (final file in data['files'] as List) {
          final name = file['name'] as String;
          if (!name.startsWith('av-op-') || !name.endsWith('.json')) continue;
          final opId = name.substring(6, name.length - 5);
          if (store.ledger.operations.any((o) => o.id == opId)) continue;
          final downloaded = await client
              .get(
                Uri.https(
                  'www.googleapis.com',
                  '/drive/v3/files/${file['id']}',
                  {'alt': 'media'},
                ),
                headers: headers,
              )
              .timeout(const Duration(seconds: 30));
          check(downloaded);
          final op = Operation.fromJson(
            Json.from(jsonDecode(utf8.decode(downloaded.bodyBytes))),
          );
          if (op.id != opId)
            throw const FormatException(
              'Arquivo de sincronização inconsistente.',
            );
          incoming.add(op);
        }
        page = data['nextPageToken'];
      } while (page != null);
      // Whole batch includes parents, regardless of Drive's list order.
      if (incoming.isNotEmpty) store.merge(incoming);
      for (final op in store.pending) {
        final boundary = 'av_${op.id}';
        final metadata = jsonEncode({
          'name': 'av-op-${op.id}.json',
          'parents': ['appDataFolder'],
        });
        final body =
            '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n${jsonEncode(op.toJson())}\r\n--$boundary--';
        final response = await client
            .post(
              Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
                'uploadType': 'multipart',
                'fields': 'id',
              }),
              headers: {
                ...headers,
                'Content-Type': 'multipart/related; boundary=$boundary',
              },
              body: utf8.encode(body),
            )
            .timeout(const Duration(seconds: 30));
        check(response);
        store.markUploaded(op.id);
      }
      store.setSetting('lastSync', DateTime.now().toIso8601String());
      if (store.pending.isNotEmpty) {
        status = 'Alterações pendentes';
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 3), () => synchronize());
      } else {
        status =
            store.ledger.conflicts.isNotEmpty || store.ledger.issues.isNotEmpty
            ? 'Sincronizado • revisar conflitos'
            : 'Sincronizado';
      }
    } on SocketException {
      status = 'Aguardando internet';
      scheduleRetry();
    } on TimeoutException {
      status = 'Conexão demorou • nova tentativa em breve';
      scheduleRetry();
    } on http.ClientException {
      status = 'Aguardando internet';
      scheduleRetry();
    } catch (e) {
      status =
          'Erro de sincronização: ${e.toString().replaceFirst('Bad state: ', '').replaceFirst('FormatException: ', '')}';
    } finally {
      client.close();
      busy = false;
      notifyListeners();
    }
  }

  void scheduleRetry() =>
      retry = Timer(const Duration(seconds: 45), () => synchronize());
  void check(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw HttpException(
        r.statusCode == 401
            ? 'Autorização expirada. Reconecte a conta Google.'
            : 'Drive respondeu ${r.statusCode}. Tente sincronizar novamente.',
      );
  }

  @override
  void dispose() {
    debounce?.cancel();
    retry?.cancel();
    super.dispose();
  }
}
