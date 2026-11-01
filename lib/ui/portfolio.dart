import 'package:flutter/material.dart';
import '../domain.dart';
import '../insights.dart';
import '../store.dart';
import 'identity.dart';
import 'reports.dart';

class PortfolioPage extends StatefulWidget {
  final Store store;
  final Listenable changes;
  const PortfolioPage({super.key, required this.store, required this.changes});
  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage>
    with WidgetsBindingObserver {
  bool visible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted)
      setState(() => visible = false);
  }

  String display(int value) => visible ? money(value) : '••••••';
  Future<void> edit([Json? account]) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => AssetForm(store: widget.store, initial: account),
    );
    if (mounted) setState(() {});
  }

  IconData icon(String group) => switch (group) {
    'bank' => Icons.account_balance_outlined,
    'investment' => Icons.trending_up,
    'cash' => Icons.payments_outlined,
    _ => Icons.savings_outlined,
  };
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.changes,
    builder: (context, _) {
      final ledger = widget.store.ledger;
      final portfolio = Portfolio(ledger);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Patrimônio'),
          actions: [
            IconButton(
              tooltip: visible ? 'Ocultar valores' : 'Mostrar valores',
              onPressed: () => setState(() => visible = !visible),
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => edit(),
          icon: const Icon(Icons.add),
          label: const Text('Adicionar conta ou reserva'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1020),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tudo o que você já tem.',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Uma visão das suas contas, investimentos e dinheiro guardado.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: gold.withValues(alpha: .4)),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF29261E), Color(0xFF17191D)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL INFORMADO',
                          style: TextStyle(
                            color: gold,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          display(portfolio.total),
                          key: const Key('portfolio-total'),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${portfolio.accounts.length} contas e reservas • valores em reais',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Soma dos saldos mais recentes. Não inclui o resultado mensal nem dívidas de clientes.',
                          style: TextStyle(color: Colors.grey, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AdaptivePanels(
                    children: [
                      InsightMetric(
                        label: 'Em contas bancárias',
                        value: display(portfolio.groupTotal('bank')),
                        detail: 'Informe apenas o saldo em conta',
                        color: gold,
                        icon: icon('bank'),
                      ),
                      InsightMetric(
                        label: 'Investido',
                        value: display(portfolio.groupTotal('investment')),
                        detail: 'Valor atual das aplicações',
                        color: green,
                        icon: icon('investment'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AdaptivePanels(
                    children: [
                      InsightMetric(
                        label: 'Dinheiro guardado',
                        value: display(portfolio.groupTotal('cash')),
                        detail: 'Dinheiro físico e reservas em espécie',
                        color: gold,
                        icon: icon('cash'),
                      ),
                      InsightMetric(
                        label: 'Outras reservas',
                        value: display(portfolio.groupTotal('other')),
                        detail: 'Valores que não estão nos demais grupos',
                        color: gold,
                        icon: icon('other'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (portfolio.staleCount(DateTime.now()) > 0)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.update, color: gold),
                        title: Text(
                          '${portfolio.staleCount(DateTime.now())} saldos sem atualização há mais de 30 dias',
                        ),
                        subtitle: const Text(
                          'Confira os valores no banco ou onde você guarda sua reserva.',
                        ),
                      ),
                    ),
                  if (ledger.conflicts.any((o) => o.kind == 'asset'))
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.warning_amber, color: gold),
                        title: Text('Há versões diferentes de uma reserva'),
                        subtitle: Text(
                          'Total provisório. Revise o conflito em Configurações antes de usar esse total.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Suas contas e reservas',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (portfolio.accounts.isEmpty)
                    const ReportEmpty(
                      'Comece adicionando uma conta, investimento ou dinheiro guardado.',
                      Icons.savings_outlined,
                    ),
                  ...portfolio.accounts.map((a) {
                    final revisions =
                        ledger.operations
                            .where((o) => o.entity == a['id'] && o.data != null)
                            .toList()
                          ..sort((a, b) => b.clock.compareTo(a.clock));
                    final stale =
                        DateTime.now()
                            .difference(DateTime.parse(a['date']))
                            .inDays >
                        30;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 7),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: gold.withValues(alpha: .1),
                                  child: Icon(icon(a['group']), color: gold),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a['name'],
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        assetGroups[a['group']]!,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Atualizar saldo de ${a['name']}',
                                  onPressed: () => edit(a),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              display(a['balance']),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Saldo em ${brDate(a['date'])}${stale ? ' • conferir atualização' : ''}',
                              style: TextStyle(
                                color: stale ? gold : Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            if (visible && (a['note'] ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(a['note']),
                              ),
                            if (revisions.length > 1)
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                  'Histórico de atualizações',
                                  style: TextStyle(fontSize: 13),
                                ),
                                children: [
                                  for (final revision in revisions.take(8))
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        'Saldo em ${brDate(revision.data!['date'])}',
                                      ),
                                      trailing: Text(
                                        display(revision.data!['balance']),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  const Text(
                    'Atualização manual: o aplicativo não consulta seus bancos. Não repita aqui o mesmo dinheiro em mais de uma conta. Transferências entre suas reservas não são receita.',
                    style: TextStyle(color: Colors.grey, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ocultar valores dá discrição à tela; não é bloqueio por senha. As reservas fazem parte do backup e da sincronização.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AssetForm extends StatefulWidget {
  final Store store;
  final Json? initial;
  const AssetForm({super.key, required this.store, this.initial});
  @override
  State<AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<AssetForm> {
  late final TextEditingController name, balance, note;
  late final List<String> heads;
  late String group;
  DateTime date = DateTime.now();
  String? error;
  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    name = TextEditingController(text: a?['name'] ?? '');
    final cents = a?['balance'] as int?;
    balance = TextEditingController(
      text: cents == null
          ? ''
          : '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}',
    );
    note = TextEditingController(text: a?['note'] ?? '');
    group = a?['group'] ?? 'bank';
    heads =
        widget.store.ledger.heads[a?['id']]?.map((o) => o.id).toList() ?? [];
  }

  @override
  void dispose() {
    name.dispose();
    balance.dispose();
    note.dispose();
    super.dispose();
  }

  void save() {
    try {
      widget.store.save(
        'asset',
        {
          'name': name.text.trim(),
          'balance': parseMoney(balance.text),
          'group': group,
          'date': day(date),
          'note': note.text.trim(),
        },
        id: widget.initial?['id'],
        expectedHeads: heads,
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(
        () => error = e
            .toString()
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<void> remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remover esta reserva?'),
        content: const Text(
          'Ela deixará de compor seu patrimônio. Seus lançamentos financeiros não serão alterados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      widget.store.save(
        'asset',
        null,
        id: widget.initial!['id'],
        expectedHeads: heads,
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Nova conta ou reserva' : 'Atualizar saldo',
    ),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informe o saldo atual, não o valor que você adicionou. Isso não cria uma entrada ou despesa.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: Conta principal, CDB, Reserva em espécie',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: group,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: assetGroups.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => group = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: balance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Saldo atual (R\$)',
                hintText: '0,00',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => date = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text('Saldo em ${brDate(day(date))}'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!, style: const TextStyle(color: red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.initial != null)
        TextButton(
          onPressed: remove,
          child: const Text('Remover', style: TextStyle(color: red)),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: save, child: const Text('Salvar saldo')),
    ],
  );
}
