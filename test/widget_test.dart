import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arthur_victor/main.dart';
import 'package:arthur_victor/store.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('navegação e formulário em $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = Store(':memory:');
      addTearDown(store.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Home(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Entradas recebidas'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Novo registro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nova saída'));
      await tester.pumpAndSettle();
      expect(find.text('Valor (R\$)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Valor (R\$)'),
        '30,00',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Descrição'),
        'Barbearia',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(store.ledger.transactions.single['amount'], 3000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
