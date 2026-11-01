import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'domain.dart';
import 'store.dart';
import 'sync.dart';
import 'ui/identity.dart';
import 'ui/record_form.dart';
import 'ui/reports.dart';
import 'ui/portfolio.dart';
export 'ui/identity.dart' show appTheme;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  Store? store;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      final loaded = Store('${directory.path}/arthur_victor.sqlite');
      if (mounted) setState(() => store = loaded);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AVFinanças',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: store != null
        ? Home(store: store!)
        : Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Brand(size: 120),
                  const SizedBox(height: 24),
                  error == null
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Não foi possível abrir seus dados. Nenhum banco foi substituído.\n$error',
                          ),
                        ),
                ],
              ),
            ),
          ),
  );
}

class Home extends StatefulWidget {
  final Store store;
  const Home({super.key, required this.store});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  late final DriveSync sync;
  int tab = 0;
  DateTime selected = DateTime.now();
  Period period = Period.month;
  String search = '', filter = 'Todos';
  String? categoryFilter;
  String? client;
  bool accumulated = true;
  Ledger get ledger => widget.store.ledger;
  DateRange get range => DateRange.forDate(selected, period);
  static const labels = [
    'Início',
    'Lançamentos',
    'Trabalho',
    'Relatórios',
    'Configurações',
  ];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.swap_vert,
    Icons.work_outline,
    Icons.bar_chart,
    Icons.settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync = DriveSync(widget.store)..addListener(refresh);
    widget.store.onChange = () {
      refresh();
      sync.changed();
    };
    unawaited(sync.synchronize());
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      unawaited(sync.synchronize());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.onChange = null;
    sync.removeListener(refresh);
    sync.dispose();
    super.dispose();
  }

  void notify(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> action(FutureOr<void> Function() callback) async {
    try {
      await callback();
    } catch (e) {
      notify(
        e
            .toString()
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> edit(
    String kind, {
    Json? data,
    int sign = 1,
    String? person,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => RecordForm(
        store: widget.store,
        kind: kind,
        initial: data,
        sign: sign,
        client: person ?? client,
      ),
    );
    if (result == true) notify('Salvo no dispositivo.');
  }

  Future<void> remove(String kind, Json row) async {
    if (await confirm(
      'Excluir registro?',
      kind == 'payment'
          ? 'O recebimento será removido das finanças e a dívida voltará a ficar pendente. A exclusão também será sincronizada.'
          : 'A exclusão também será sincronizada com o outro dispositivo.',
    )) {
      await action(() => widget.store.save(kind, null, id: row['id']));
    }
  }

  Future<void> quickAdd() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in [
              ('Nova entrada', 'entry', 1, Icons.south_west),
              ('Nova saída', 'entry', -1, Icons.north_east),
              ('Registrar horas', 'shift', 1, Icons.schedule),
              ('Registrar pagamento', 'payment', 1, Icons.payments_outlined),
              ('Adicionar ajuste', 'adjustment', 1, Icons.tune),
            ])
              ListTile(
                leading: Icon(option.$4, color: gold),
                title: Text(option.$1),
                onTap: () {
                  Navigator.pop(c);
                  edit(option.$2, sign: option.$3);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 236,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFF292C31))),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    const Brand(size: 80),
                    const SizedBox(height: 12),
                    const Text(
                      'AVFinanças',
                      style: TextStyle(
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'FINANÇAS & TRABALHO',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 40),
                    for (var i = 0; i < labels.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selected: tab == i,
                          selectedTileColor: gold.withValues(alpha: .12),
                          selectedColor: gold,
                          leading: Icon(icons[i]),
                          title: Text(labels[i]),
                          onTap: () => setState(() {
                            tab = i;
                            client = null;
                          }),
                        ),
                      ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        sync.status,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 20, 20, 8),
                    child: Row(
                      children: [
                        if (!wide)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Brand(size: 38),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                labels[tab],
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                tab == 0
                                    ? 'Seu mês, com clareza.'
                                    : 'Controle simples. Dados sempre com você.',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: sync.status,
                          onPressed: sync.busy
                              ? null
                              : () => sync.synchronize(),
                          icon: sync.busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_sync_outlined),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: ListView(
                        key: ValueKey('$tab-$client'),
                        padding: EdgeInsets.fromLTRB(
                          wide ? 32 : 16,
                          16,
                          wide ? 32 : 16,
                          100,
                        ),
                        children: [
                          if (ledger.conflicts.isNotEmpty ||
                              ledger.issues.isNotEmpty)
                            Card(
                              color: const Color(0xFF3A2920),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.warning_amber,
                                  color: gold,
                                ),
                                title: const Text('Há alterações para revisar'),
                                subtitle: const Text(
                                  'Os totais são provisórios até a revisão dos conflitos.',
                                ),
                                onTap: () => setState(() => tab = 4),
                              ),
                            ),
                          if (tab < 4)
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: tab == 3 ? 1180 : double.infinity,
                                ),
                                child: dateControls(),
                              ),
                            ),
                          const SizedBox(height: 16),
                          ...switch (tab) {
                            0 => dashboard(),
                            1 => entries(),
                            2 => work(),
                            3 => reports(),
                            _ => settings(),
                          },
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (i) => setState(() {
                tab = i;
                client = null;
              }),
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
      floatingActionButton: tab == 4
          ? null
          : FloatingActionButton.extended(
              onPressed: quickAdd,
              backgroundColor: gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Novo registro'),
            ),
    );
  }

  Widget dateControls() => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SegmentedButton<Period>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: Period.day, label: Text('Dia')),
          ButtonSegment(value: Period.week, label: Text('Semana')),
          ButtonSegment(value: Period.month, label: Text('Mês')),
          ButtonSegment(value: Period.year, label: Text('Ano')),
        ],
        selected: {period},
        onSelectionChanged: (v) => setState(() => period = v.first),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(range.label),
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: selected,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d != null) setState(() => selected = d);
        },
      ),
      TextButton(
        onPressed: () => setState(() {
          selected = DateTime.now();
          period = Period.month;
        }),
        child: const Text('Mês atual'),
      ),
    ],
  );
  Widget heading(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
  Widget empty(String title, String subtitle, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Icon(icon, size: 36, color: gold),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    ),
  );
  Widget metric(String title, String value, Color color, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
  Widget metrics() {
    final f = ledger.finance(range);
    return LayoutBuilder(
      builder: (c, b) {
        final cards = [
          metric(
            'Entradas recebidas',
            money(f.income),
            green,
            Icons.south_west,
          ),
          metric('Saídas pagas', money(f.expenses), red, Icons.north_east),
          metric(
            'Resultado do período',
            money(f.balance),
            f.balance < 0 ? red : gold,
            Icons.account_balance_wallet_outlined,
          ),
        ];
        return b.maxWidth > 700
            ? Row(children: [for (final card in cards) Expanded(child: card)])
            : Column(children: cards);
      },
    );
  }

  List<Widget> dashboard() => [
    metrics(),
    const Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 20),
      child: Text(
        'Resultado das movimentações do período. Dívidas a receber não entram no saldo.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ),
    heading(
      'Últimos lançamentos',
      trailing: TextButton(
        onPressed: () => setState(() => tab = 1),
        child: const Text('Ver todos'),
      ),
    ),
    if (!ledger.transactions.any((t) => range.contains(t['date'])))
      empty(
        'Um novo começo',
        'Toque em + para registrar sua primeira entrada ou saída.',
        Icons.receipt_long_outlined,
      ),
    ...ledger.transactions
        .where((t) => range.contains(t['date']))
        .take(6)
        .map(transactionTile),
    heading('A receber • todos os meses'),
    ...ledger.rows('client').map(clientTile),
  ];
  Widget transactionTile(Json t) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: (t['sign'] == 1 ? green : red).withValues(alpha: .1),
        child: Icon(
          t['sign'] == 1 ? Icons.south_west : Icons.north_east,
          color: t['sign'] == 1 ? green : red,
        ),
      ),
      title: Text(t['description']),
      subtitle: Text(
        '${brDate(t['date'])} • ${t['category'] ?? 'Outros'}${t['payment'] == true ? ' • vinculado ao cliente' : ''}',
      ),
      trailing: Text(
        money((t['amount'] as int) * (t['sign'] as int)),
        style: TextStyle(
          color: t['sign'] == 1 ? green : red,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => edit(
        t['payment'] == true ? 'payment' : 'entry',
        data: ledger.get(t['id']),
      ),
    ),
  );
  List<Widget> entries() {
    final list = ledger.transactions
        .where(
          (t) =>
              range.contains(t['date']) &&
              ('$t'.toLowerCase().contains(search.toLowerCase())) &&
              (categoryFilter == null ||
                  (t['category'] ?? 'Outros') == categoryFilter) &&
              (filter == 'Todos' ||
                  (filter == 'Entradas' ? t['sign'] == 1 : t['sign'] == -1)),
        )
        .toList();
    return [
      if (categoryFilter != null)
        Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            label: Text('Categoria: $categoryFilter'),
            onDeleted: () => setState(() => categoryFilter = null),
          ),
        ),
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Pesquisar descrição, pessoa ou categoria',
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final s in ['Todos', 'Entradas', 'Saídas'])
            ChoiceChip(
              label: Text(s),
              selected: filter == s,
              onSelected: (_) => setState(() => filter = s),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        empty(
          'Nenhum lançamento',
          'Os registros deste período aparecerão aqui.',
          Icons.receipt_long_outlined,
        ),
      ...list.map(transactionTile),
    ];
  }

  Widget clientTile(Json c) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: gold.withValues(alpha: .12),
        foregroundColor: gold,
        child: Text((c['name'] as String).substring(0, 1).toUpperCase()),
      ),
      title: Text(c['name']),
      subtitle: Text(
        c['rate'] == 0
            ? 'Valor por hora não definido'
            : '${money(c['rate'])} / hora',
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(ledger.totalDebt(c['id'])),
            style: const TextStyle(
              color: gold,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const Text(
            'a receber',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      onTap: () => setState(() {
        tab = 2;
        client = c['id'];
        accumulated = true;
      }),
    ),
  );
  List<Widget> work() {
    if (client == null || ledger.get(client!) == null)
      return [
        heading(
          'Patrões e clientes',
          trailing: IconButton(
            tooltip: 'Cadastrar cliente',
            onPressed: () => edit('client'),
            icon: const Icon(Icons.person_add_alt),
          ),
        ),
        ...ledger.rows('client').map(clientTile),
      ];
    final c = ledger.get(client!)!;
    final debts = ledger.debt(client!);
    final shown = accumulated
        ? debts
        : Map.fromEntries(debts.entries.where((e) => e.key == month(selected)));
    final history = <Json>[
      for (final k in ['shift', 'adjustment', 'payment'])
        ...ledger
            .rows(k)
            .where(
              (r) =>
                  r['client'] == client &&
                  (accumulated || range.contains(r['date'])),
            )
            .map((r) => {...r, 'kind': k}),
    ]..sort((a, b) => (b['date'] as String).compareTo(a['date']));
    return [
      Row(
        children: [
          IconButton(
            tooltip: 'Voltar aos clientes',
            onPressed: () => setState(() => client = null),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              c['name'],
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Editar cliente',
            onPressed: () => edit('client', data: c),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      if ((c['note'] ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(c['note'], style: const TextStyle(color: Colors.grey)),
        ),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Mês selecionado'),
            selected: !accumulated,
            onSelected: (_) => setState(() => accumulated = false),
          ),
          ChoiceChip(
            label: const Text('Total acumulado'),
            selected: accumulated,
            onSelected: (_) => setState(() => accumulated = true),
          ),
        ],
      ),
      metric(
        accumulated
            ? 'Total acumulado a receber'
            : 'A receber • ${month(selected)}',
        money(shown.values.fold(0, (a, b) => a + b)),
        gold,
        Icons.payments_outlined,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => edit('shift'),
            icon: const Icon(Icons.schedule),
            label: const Text('Adicionar horas'),
          ),
          OutlinedButton.icon(
            onPressed: () => edit('payment'),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Registrar pagamento'),
          ),
          OutlinedButton.icon(
            onPressed: () => edit('adjustment'),
            icon: const Icon(Icons.tune),
            label: const Text('Adicionar ajuste'),
          ),
        ],
      ),
      heading('Dívidas por competência'),
      if (shown.isEmpty)
        empty(
          'Nenhuma dívida neste período',
          'Adicione uma jornada ou um serviço extra.',
          Icons.work_outline,
        ),
      ...shown.entries.map((e) {
        final paid = ledger
            .rows('payment')
            .where((p) => p['client'] == client)
            .fold<int>(
              0,
              (v, p) => v + ((p['allocations'] as Map)[e.key] as int? ?? 0),
            );
        return Card(
          child: ListTile(
            title: Text('${e.key.substring(5)}/${e.key.substring(0, 4)}'),
            subtitle: Text(
              e.value == 0
                  ? 'Pago'
                  : paid > 0
                  ? 'Parcialmente pago'
                  : 'Pendente',
            ),
            trailing: Text(
              money(e.value),
              style: TextStyle(color: e.value == 0 ? green : gold),
            ),
          ),
        );
      }),
      heading(
        accumulated ? 'Histórico completo' : 'Histórico • ${range.label}',
      ),
      ...history.map((r) {
        final k = r['kind'];
        final amount = k == 'shift'
            ? earned(r['minutes'], r['rate'])
            : r['amount'] as int;
        return Card(
          child: ListTile(
            title: Text(
              k == 'shift'
                  ? 'Jornada • ${hours(r['minutes'])}'
                  : k == 'payment'
                  ? 'Pagamento recebido'
                  : r['description'],
            ),
            subtitle: Text(
              '${brDate(r['date'])}${k == 'adjustment' ? ' • competência ${r['month']}' : ''}${k == 'payment' ? ' • ${(r['allocations'] as Map).keys.join(', ')}' : ''}\n${r['note'] ?? ''}',
            ),
            trailing: Text(
              money(amount),
              style: TextStyle(color: k == 'payment' ? green : gold),
            ),
            onTap: () => edit(k, data: r),
          ),
        );
      }),
    ];
  }

  List<Widget> reports() => [
    ReportsView(
      ledger: ledger,
      selected: selected,
      period: period,
      export: () => action(
        () => saveFile(
          'relatorio-${day(selected)}.csv',
          exportCsv(ledger, range),
        ),
      ),
      selectMonth: (d) => setState(() {
        selected = d;
        period = Period.month;
      }),
      selectCategory: (category) => setState(() {
        categoryFilter = category;
        search = '';
        filter = 'Saídas';
        tab = 1;
      }),
      selectClient: (id) => setState(() {
        client = id;
        tab = 2;
        accumulated = true;
      }),
    ),
  ];

  Future<void> saveFile(String name, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar arquivo',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [name.split('.').last],
      bytes: bytes,
    );
    if (path == null) return;
    if (Platform.isWindows) await File(path).writeAsBytes(bytes, flush: true);
    notify('Arquivo exportado.');
  }

  Future<void> restore() async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (file == null) return;
    final text = utf8.decode(
      file.files.single.bytes ??
          await File(file.files.single.path!).readAsBytes(),
    );
    final ops = widget.store.validateBackup(text);
    if (!await confirm(
      'Restaurar backup?',
      '${ops.length} versões serão mescladas com seus dados. Registros idênticos não serão duplicados. Alterações concorrentes serão preservadas para revisão.',
    ))
      return;
    final dir = await getApplicationSupportDirectory();
    await File(
      '${dir.path}/antes-restauracao-${DateTime.now().millisecondsSinceEpoch}.json',
    ).writeAsString(widget.store.backup(), flush: true);
    widget.store.restore(text);
    notify('Backup restaurado.');
  }

  List<Widget> settings() => [
    Card(
      child: ListTile(
        leading: const Icon(Icons.savings_outlined, color: gold),
        title: const Text('Patrimônio'),
        subtitle: const Text(
          'Contas, investimentos e dinheiro guardado • valores ocultos ao abrir',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PortfolioPage(store: widget.store, changes: sync),
          ),
        ),
      ),
    ),

    const Center(child: Brand(size: 100)),
    const SizedBox(height: 12),
    const Center(
      child: Text(
        'AVFinanças',
        style: TextStyle(letterSpacing: 3, fontSize: 18),
      ),
    ),
    const Center(
      child: Text(
        'Finanças & trabalho • versão 0.2.0',
        style: TextStyle(color: Colors.grey),
      ),
    ),
    heading('Sua conta e seus dados'),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sync.status, style: const TextStyle(color: gold)),
            const SizedBox(height: 8),
            Text(
              widget.store.setting('boundEmail') ??
                  'Conta Google não conectada',
            ),
            Text(
              'Última sincronização: ${widget.store.setting('lastSync') == null ? 'ainda não realizada' : brDate(widget.store.setting('lastSync')!.substring(0, 10)) + ' ' + widget.store.setting('lastSync')!.substring(11, 16)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: sync.busy
                      ? null
                      : () => sync.synchronize(interactive: true),
                  child: const Text('Conectar Google'),
                ),
                OutlinedButton(
                  onPressed: sync.busy ? null : () => sync.synchronize(),
                  child: const Text('Sincronizar agora'),
                ),
                TextButton(
                  onPressed: sync.busy
                      ? null
                      : () => action(() async {
                          await sync.auth.disconnect();
                          sync.status = 'Somente neste dispositivo';
                          refresh();
                        }),
                  child: const Text('Desconectar'),
                ),
              ],
            ),
            TextButton(
              onPressed: oauthSettings,
              child: const Text('Configurar credenciais OAuth'),
            ),
          ],
        ),
      ),
    ),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Exportar backup completo'),
            subtitle: const Text(
              'JSON portátil com verificação de integridade',
            ),
            onTap: () => action(
              () => saveFile(
                'arthur-victor-${day(DateTime.now())}.json',
                widget.store.backup(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restaurar backup'),
            subtitle: const Text(
              'Mescla o histórico e evita registros duplicados',
            ),
            onTap: () => action(restore),
          ),
        ],
      ),
    ),
    heading('Organização'),
    Card(
      child: ListTile(
        leading: const Icon(Icons.people_outline),
        title: const Text('Gerenciar clientes e valores por hora'),
        onTap: () => setState(() {
          tab = 2;
          client = null;
        }),
      ),
    ),
    heading(
      'Categorias',
      trailing: IconButton(
        tooltip: 'Nova categoria',
        onPressed: () => edit('category'),
        icon: const Icon(Icons.add),
      ),
    ),
    Wrap(
      spacing: 8,
      children: [
        for (final c in const [
          'Alimentação',
          'Transporte',
          'Pessoal',
          'Trabalho',
          'Serviços',
          'Outros',
        ])
          Chip(label: Text(c)),
        ...ledger
            .rows('category')
            .map(
              (c) => ActionChip(
                label: Text(c['name']),
                onPressed: () => edit('category', data: c),
              ),
            ),
      ],
    ),
    if (ledger.conflicts.isNotEmpty || ledger.issues.isNotEmpty)
      heading('Revisar alterações'),
    ...ledger.issues.map(
      (i) => Card(
        color: const Color(0xFF3A2920),
        child: Padding(padding: const EdgeInsets.all(16), child: Text(i)),
      ),
    ),
    ...ledger.conflicts.map(
      (o) => Card(
        child: ListTile(
          leading: const Icon(Icons.merge_type, color: gold),
          title: Text(
            o.data?['description'] ??
                o.data?['name'] ??
                '${o.kind} • ${o.entity}',
          ),
          subtitle: Text(
            '${ledger.heads[o.entity]!.length} versões concorrentes preservadas',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => resolve(o),
        ),
      ),
    ),
    const SizedBox(height: 24),
    const Text(
      'Funciona offline. A sincronização ocorre enquanto o aplicativo está aberto. Faça também backups fora do aplicativo.',
      style: TextStyle(color: Colors.grey),
    ),
  ];
  Future<void> resolve(Operation op) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Escolher versão'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Uma versão provisória está nos totais. Escolha a correta; o histórico das demais continuará preservado.',
                ),
                for (final revision in ledger.heads[op.entity]!)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dispositivo ${revision.device}'),
                          SelectableText(
                            revision.data == null
                                ? 'Registro excluído'
                                : const JsonEncoder.withIndent(
                                    '  ',
                                  ).convert(revision.data),
                          ),
                          TextButton(
                            onPressed: () => action(() {
                              widget.store.save(
                                op.kind,
                                revision.data,
                                id: op.entity,
                              );
                              Navigator.pop(c);
                            }),
                            child: const Text('Usar esta versão'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
  }

  Future<void> oauthSettings() async {
    final android = TextEditingController(
      text: widget.store.setting('androidServerId') ?? '',
    );
    final desktop = TextEditingController(
      text: widget.store.setting('desktopClientId') ?? '',
    );
    final secret = TextEditingController(
      text: await sync.auth.vault.read(key: 'desktopClientSecret') ?? '',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Credenciais do projeto Google'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Use o mesmo projeto Google Cloud nos dois dispositivos. Consulte o README para configurar pacote, certificado e tela de consentimento.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: android,
                  decoration: const InputDecoration(
                    labelText: 'ID Web (serverClientId do Android)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: desktop,
                  decoration: const InputDecoration(
                    labelText: 'ID Desktop (Windows)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Client secret da credencial Desktop',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O valor Desktop é guardado no cofre do sistema. Nunca informe um segredo de servidor Web.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => action(() async {
              widget.store.setSetting('androidServerId', android.text.trim());
              widget.store.setSetting('desktopClientId', desktop.text.trim());
              await sync.auth.vault.write(
                key: 'desktopClientSecret',
                value: secret.text.trim(),
              );
              if (c.mounted) Navigator.pop(c);
              notify(
                'Credenciais salvas. Reinicie o aplicativo antes de conectar.',
              );
            }),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    android.dispose();
    desktop.dispose();
    secret.dispose();
  }
}
