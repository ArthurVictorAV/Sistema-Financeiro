import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arthur_victor/domain.dart';
import 'package:arthur_victor/store.dart';
import 'package:arthur_victor/ui/identity.dart';
import 'package:arthur_victor/ui/reports.dart';
import 'package:arthur_victor/ui/portfolio.dart';

Store fixture() {
  final s = Store(':memory:');
  for (var month = 5; month <= 10; month++) {
    s.save('entry', {
      'date': day(DateTime(2026, month, 10)),
      'amount': month == 10 ? 176900 : 120000 + month * 7000,
      'sign': 1,
      'description': 'Serviços',
      'category': 'Trabalho',
    });
    for (final category in [
      ('Alimentação', 61000),
      ('Pessoal', 64300),
      ('Outros', 43700),
      ('Transporte', 10000),
      ('Trabalho', 5000),
    ]) {
      s.save('entry', {
        'date': day(DateTime(2026, month, 12)),
        'amount': month == 10 ? category.$2 : category.$2 * month ~/ 10,
        'sign': -1,
        'description': 'Despesa de exemplo',
        'category': category.$1,
      });
    }
  }
  s.save('shift', {
    'date': '2026-10-01',
    'client': jpId,
    'minutes': 6630 ~/ 10,
    'rate': 2500,
    'mode': 'direct',
  });
  for (final a in [
    ('Conta principal', 'bank', 240000),
    ('CDB', 'investment', 520000),
    ('Reserva em espécie', 'cash', 60000),
  ]) {
    s.save('asset', {
      'name': a.$1,
      'group': a.$2,
      'balance': a.$3,
      'date': '2026-10-30',
      'note': '',
    });
  }
  return s;
}

Widget app(Widget home) => MaterialApp(
  theme: appTheme(),
  locale: const Locale('pt', 'BR'),
  supportedLocales: const [Locale('pt', 'BR')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    if (Platform.isWindows) {
      final font = FontLoader('Roboto')
        ..addFont(
          File(
            'C:/Windows/Fonts/segoeui.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
    }
  });
  for (final size in [const Size(390, 844), const Size(1440, 1100)]) {
    testWidgets('Relatórios responsivos e categoria clicável $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = fixture();
      addTearDown(s.close);
      String? category;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: const Color(0xFF0D0F12),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ReportsView(
                      ledger: s.ledger,
                      selected: DateTime(2026, 10),
                      period: Period.month,
                      export: () {},
                      selectMonth: (_) {},
                      selectCategory: (v) => category = v,
                      selectClient: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.isWindows) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('previews').create(recursive: true);
          await File(
            'previews/relatorios-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await Scrollable.ensureVisible(
        tester.element(find.text('Alimentação').first),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alimentação').first);
      await tester.pump();
      expect(category, 'Alimentação');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Patrimônio inicia oculto, revela valores e volta a ocultar ao sair',
    (tester) async {
      final s = fixture();
      addTearDown(s.close);
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      await tester.pumpWidget(app(PortfolioPage(store: s, changes: changes)));
      await tester.pumpAndSettle();
      expect(find.text(money(820000)), findsNothing);
      await tester.tap(find.byTooltip('Mostrar valores'));
      await tester.pump();
      expect(find.text(money(820000)), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(money(820000)), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Formulário de reserva salva saldo sem lançar receita', (
    tester,
  ) async {
    final s = Store(':memory:');
    addTearDown(s.close);
    await tester.pumpWidget(app(Scaffold(body: AssetForm(store: s))));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome'),
      'Banco de teste',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Saldo atual (R\$)'),
      '123,45',
    );
    await tester.tap(find.text('Salvar saldo'));
    await tester.pumpAndSettle();
    expect(s.ledger.rows('asset').single['balance'], 12345);
    expect(s.ledger.transactions, isEmpty);
  });
}
