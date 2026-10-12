import 'package:flutter/material.dart';
import '../domain.dart';
import '../store.dart';
import 'identity.dart';

class RecordForm extends StatefulWidget {
  final Store store;
  final String kind;
  final Json? initial;
  final int sign;
  final String? client;
  const RecordForm({
    super.key,
    required this.store,
    required this.kind,
    this.initial,
    this.sign = 1,
    this.client,
  });
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final fields = <String, TextEditingController>{};
  late final List<String> openedHeads;
  late int sign;
  late String date, reference, mode, category;
  String? client, preferred, error;
  bool saving = false;
  Ledger get ledger => widget.store.ledger;
  String get kind => widget.kind;
  String get title => switch (kind) {
    'entry' => 'Lançamento',
    'client' => 'Cliente / patrão',
    'shift' => 'Registrar horas',
    'payment' => 'Registrar pagamento',
    'category' => 'Categoria',
    _ => 'Adicionar ajuste',
  };
  TextEditingController field(String k, [String value = '']) =>
      fields.putIfAbsent(k, () => TextEditingController(text: value));
  String amountText(int n) =>
      '${n ~/ 100},${(n % 100).toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    final d = widget.initial ?? {};
    openedHeads = ledger.heads[d['id']]?.map((o) => o.id).toList() ?? [];
    sign = d['sign'] ?? widget.sign;
    date = d['date'] ?? day(DateTime.now());
    reference = d['month'] ?? date.substring(0, 7);
    mode = d['mode'] ?? 'clock';
    category = d['category'] ?? 'Outros';
    client = d['client'] ?? widget.client;
    if (client == null &&
        ledger.rows('client').isNotEmpty &&
        ['shift', 'payment', 'adjustment'].contains(kind))
      client = ledger.rows('client').first['id'];
    field('name', d['name'] ?? '');
    field('description', d['description'] ?? '');
    field('note', d['note'] ?? '');
    field('amount', d['amount'] == null ? '' : amountText(d['amount']));
    field(
      'rate',
      amountText(
        d['rate'] ?? (client == null ? 0 : ledger.get(client!)?['rate'] ?? 0),
      ),
    );
    field('start', d['start'] ?? '08:00');
    field('end', d['end'] ?? '12:00');
    field(
      'pause',
      d['pause'] == null
          ? '00:00'
          : '${(d['pause'] as int) ~/ 60}:${((d['pause'] as int) % 60).toString().padLeft(2, '0')}',
    );
    field(
      'duration',
      d['minutes'] == null
          ? '04:00'
          : '${(d['minutes'] as int) ~/ 60}:${((d['minutes'] as int) % 60).toString().padLeft(2, '0')}',
    );
    if (kind == 'payment' && d['allocations'] != null) preferred = 'keep';
  }

  @override
  void dispose() {
    for (final c in fields.values) c.dispose();
    super.dispose();
  }

  Widget input(String key, String label, {bool numeric = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: field(key),
      decoration: InputDecoration(labelText: label),
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) => setState(() {}),
    ),
  );
  int minutes() => mode == 'direct'
      ? clockMinutes(field('duration').text, duration: true)
      : workMinutes(
          field('start').text,
          field('end').text,
          clockMinutes(field('pause').text, duration: true),
        );
  Map<String, int> paymentAllocations(int amount) {
    if (preferred == 'keep') {
      if (amount != widget.initial!['amount'])
        throw const FormatException(
          'Para alterar o valor, escolha um mês ou a distribuição pelas dívidas mais antigas.',
        );
      return Map<String, int>.from(widget.initial!['allocations']);
    }
    return ledger.allocate(
      client!,
      amount,
      preferred: preferred,
      excludePayment: widget.initial?['id'],
    );
  }

  Widget preview() {
    try {
      if (kind == 'shift') {
        final n = minutes();
        if (n <= 0 || n > 1440)
          throw const FormatException('Informe de 1 minuto a 24 horas.');
        return Text(
          '${hours(n)} • ${money(earned(n, parseMoney(field('rate').text)))}',
          style: const TextStyle(
            color: gold,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
        );
      }
      if (kind == 'payment' && client != null) {
        final allocations = paymentAllocations(
          parseMoney(field('amount').text),
        );
        return Text(
          allocations.entries
              .map((e) => '${e.key}: ${money(e.value)}')
              .join('\n'),
          style: const TextStyle(color: green),
        );
      }
    } catch (e) {
      return Text(
        e.toString().replaceFirst('FormatException: ', ''),
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> pickDate({bool monthOnly = false}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(monthOnly ? '$reference-01' : date),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null)
      setState(() {
        if (monthOnly) {
          reference = month(d);
        } else {
          date = day(d);
        }
      });
  }

  void save() {
    if (saving) return;
    setState(() => saving = true);
    try {
      Json data;
      if (kind == 'client' || kind == 'category') {
        data = {
          'name': field('name').text.trim(),
          if (kind == 'client') 'rate': parseMoney(field('rate').text),
          'note': field('note').text.trim(),
        };
      } else {
        data = {
          'date': date,
          'note': field('note').text.trim(),
          if (client != null) 'client': client,
        };
        if (kind == 'shift') {
          data.addAll({
            'minutes': minutes(),
            'rate': parseMoney(field('rate').text),
            'mode': mode,
            if (mode == 'clock') ...{
              'start': field('start').text,
              'end': field('end').text,
              'pause': clockMinutes(field('pause').text, duration: true),
            },
          });
        } else {
          final amount = parseMoney(field('amount').text);
          data['amount'] = amount;
          if (kind == 'payment') {
            if (client == null)
              throw const FormatException('Selecione um cliente.');
            if (ledger.conflicts.any(
              (o) =>
                  o.kind == 'payment' ||
                  o.kind == 'shift' ||
                  o.kind == 'adjustment',
            ))
              throw const FormatException(
                'Resolva os conflitos antes de registrar ou editar pagamentos.',
              );
            data['allocations'] = paymentAllocations(amount);
          } else {
            data.addAll({
              'sign': sign,
              'description': field('description').text.trim(),
              if (kind == 'entry') 'category': category,
              if (kind == 'adjustment') 'month': reference,
            });
          }
        }
      }
      widget.store.save(
        kind,
        data,
        id: widget.initial?['id'],
        expectedHeads: openedHeads,
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        error = e
            .toString()
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Bad state: ', '');
        saving = false;
      });
    }
  }

  Future<void> delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text(
          kind == 'payment'
              ? 'A entrada financeira será removida e a dívida voltará a ficar pendente.'
              : 'A exclusão será sincronizada. O histórico técnico é preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      widget.store.save(
        kind,
        null,
        id: widget.initial!['id'],
        expectedHeads: openedHeads,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ledger.rows('client');
    final categories = {
      ...[
        'Alimentação',
        'Transporte',
        'Pessoal',
        'Trabalho',
        'Serviços',
        'Outros',
      ],
      ...ledger.rows('category').map((c) => c['name'] as String),
      category,
    };
    final months = client == null
        ? <String>{}
        : {
            ...ledger.debt(client!, excludePayment: widget.initial?['id']).keys,
            if (preferred != null && preferred != 'keep') preferred!,
          };
    return AlertDialog(
      title: Text(widget.initial == null ? title : 'Editar • $title'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kind == 'client' || kind == 'category') input('name', 'Nome'),
              if (kind == 'entry' || kind == 'adjustment')
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 1,
                        label: Text(
                          kind == 'entry' ? 'Entrada' : 'Valor extra',
                        ),
                      ),
                      ButtonSegment(
                        value: -1,
                        label: Text(kind == 'entry' ? 'Saída' : 'Desconto'),
                      ),
                    ],
                    selected: {sign},
                    onSelectionChanged: (v) => setState(() => sign = v.first),
                  ),
                ),
              if (kind != 'client' && kind != 'category')
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: clients.any((c) => c['id'] == client)
                        ? client
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: kind == 'entry'
                          ? 'Pessoa / projeto (opcional)'
                          : 'Patrão / cliente',
                    ),
                    items: [
                      if (kind == 'entry')
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Sem vínculo'),
                        ),
                      ...clients.map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id'],
                          child: Text(c['name']),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      client = v == '' ? null : v;
                      preferred = null;
                      if (kind == 'shift')
                        field('rate').text = amountText(
                          ledger.get(client!)?['rate'] ?? 0,
                        );
                    }),
                  ),
                ),
              if (kind != 'client' && kind != 'category')
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: OutlinedButton.icon(
                    onPressed: () => pickDate(),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      '${kind == 'payment' ? 'Recebido em' : 'Data'}: ${brDate(date)}',
                    ),
                  ),
                ),
              if (kind == 'shift') ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'clock',
                      label: Text('Entrada e saída'),
                    ),
                    ButtonSegment(
                      value: 'direct',
                      label: Text('Horas diretas'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => setState(() => mode = v.first),
                ),
                const SizedBox(height: 16),
                if (mode == 'clock') ...[
                  input('start', 'Entrada (08:00)'),
                  input('end', 'Saída (12:30)'),
                  input('pause', 'Intervalo (00:00)'),
                ] else
                  input('duration', 'Horas trabalhadas (05:30)'),
              ],
              if (kind == 'shift' || kind == 'client')
                input(
                  'rate',
                  kind == 'client'
                      ? 'Valor padrão / hora (opcional)'
                      : 'Valor / hora (R\$)',
                  numeric: true,
                ),
              if (kind == 'entry' || kind == 'payment' || kind == 'adjustment')
                input('amount', 'Valor (R\$)', numeric: true),
              if (kind == 'entry' || kind == 'adjustment')
                input('description', 'Descrição'),
              if (kind == 'entry')
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => category = v!),
                  ),
                ),
              if (kind == 'adjustment')
                OutlinedButton(
                  onPressed: () => pickDate(monthOnly: true),
                  child: Text('Competência: $reference'),
                ),
              if (kind == 'payment') ...[
                DropdownButtonFormField<String>(
                  initialValue: preferred ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aplicar pagamento em',
                  ),
                  items: [
                    if (widget.initial != null &&
                        client == widget.initial!['client'])
                      const DropdownMenuItem(
                        value: 'keep',
                        child: Text('Manter distribuição atual'),
                      ),
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Dívidas mais antigas primeiro'),
                    ),
                    ...months.map(
                      (m) => DropdownMenuItem(value: m, child: Text(m)),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => preferred = v == '' ? null : v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A entrada financeira usa a data do recebimento. O mês do serviço permanece o mesmo.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              if (kind != 'category') input('note', 'Observação (opcional)'),
              preview(),
              if (kind == 'shift')
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Saída anterior à entrada indica o dia seguinte. A competência é a data de início.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!, style: const TextStyle(color: red)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: saving ? null : delete,
            child: const Text('Excluir', style: TextStyle(color: red)),
          ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
