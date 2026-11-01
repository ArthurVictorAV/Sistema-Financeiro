import 'package:flutter/material.dart';
import '../domain.dart';
import '../insights.dart';
import 'identity.dart';

class ReportsView extends StatelessWidget {
  final Ledger ledger;
  final DateTime selected;
  final Period period;
  final VoidCallback export;
  final ValueChanged<DateTime> selectMonth;
  final ValueChanged<String> selectCategory, selectClient;
  const ReportsView({
    super.key,
    required this.ledger,
    required this.selected,
    required this.period,
    required this.export,
    required this.selectMonth,
    required this.selectCategory,
    required this.selectClient,
  });
  @override
  Widget build(BuildContext context) {
    final range = DateRange.forDate(selected, period);
    final current = ledger.finance(range);
    final previous = ledger.finance(previousPeriod(selected, period));
    final report = ReportData(ledger, range);
    final categories = report.categories;
    final work = report.work;
    final minutes = work.fold<int>(0, (v, w) => v + (w['minutes'] as int));
    final pending = work.fold<int>(0, (v, w) => v + (w['pending'] as int));
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seu dinheiro, em perspectiva',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Entenda o período. Compare os resultados.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: export,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Exportar CSV'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            AdaptivePanels(
              children: [
                InsightMetric(
                  label: 'Entradas recebidas',
                  value: money(current.income),
                  detail: _comparison(current.income, previous.income),
                  color: green,
                  icon: Icons.south_west,
                ),
                InsightMetric(
                  label: 'Despesas pagas',
                  value: money(current.expenses),
                  detail: _comparison(current.expenses, previous.expenses),
                  color: red,
                  icon: Icons.north_east,
                ),
                InsightMetric(
                  label: 'Resultado do período',
                  value: money(current.balance),
                  detail: current.balance >= 0
                      ? 'Entradas menos despesas'
                      : 'As despesas superaram as entradas',
                  color: current.balance < 0 ? red : gold,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            AdaptivePanels(
              breakpoint: 940,
              children: [
                ReportPanel(
                  title: 'Entradas × despesas',
                  subtitle: 'Últimos 6 meses • toque em um mês para consultar',
                  child: MonthlyChart(
                    ledger: ledger,
                    selected: selected,
                    onSelect: selectMonth,
                  ),
                ),
                ReportPanel(
                  title: 'Para onde foi o dinheiro?',
                  subtitle:
                      '${categories.length} categorias no período selecionado',
                  child: categories.isEmpty
                      ? const ReportEmpty(
                          'Nenhuma despesa neste período.',
                          Icons.donut_large_outlined,
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < categories.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () =>
                                      selectCategory(categories[i].key),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                categories[i].key,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Text(money(categories[i].value)),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: LinearProgressIndicator(
                                                value:
                                                    categories[i].value /
                                                    current.expenses,
                                                minHeight: 6,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                color: i == 0
                                                    ? gold
                                                    : const Color(0xFF797C84),
                                                backgroundColor: const Color(
                                                  0xFF282B31,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 38,
                                              child: Text(
                                                '${(categories[i].value * 100 / current.expenses).round()}%',
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ReportPanel(
              title: 'Leitura do período',
              subtitle: 'Calculada a partir dos seus registros',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _insight(
                    Icons.compare_arrows,
                    'O resultado mudou ${money(current.balance - previous.balance)} em relação ao período anterior.',
                  ),
                  if (categories.isNotEmpty)
                    _insight(
                      Icons.pie_chart_outline,
                      '${categories.first.key} foi o maior gasto: ${money(categories.first.value)}.',
                    ),
                  if (current.income == 0 && current.expenses == 0)
                    _insight(
                      Icons.event_note_outlined,
                      'Registre entradas e despesas para começar a acompanhar sua evolução.',
                    ),
                  _insight(
                    Icons.info_outline,
                    'Resultado do período não é o saldo de todas as suas contas. Suas reservas ficam em Configurações → Patrimônio.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Seu trabalho',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Produção e recebimentos do período; pendências de todos os meses.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            AdaptivePanels(
              children: [
                InsightMetric(
                  label: 'Tempo trabalhado',
                  value: hours(minutes),
                  detail: 'Jornadas do período',
                  color: gold,
                  icon: Icons.schedule,
                ),
                InsightMetric(
                  label: 'Ainda a receber',
                  value: money(pending),
                  detail: 'Todos os meses • fora do saldo disponível',
                  color: gold,
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (work.isEmpty)
              const ReportEmpty(
                'Cadastre um cliente para acompanhar seu trabalho.',
                Icons.work_outline,
              ),
            ...work.map(
              (w) => Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => selectClient(w['id']),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: gold.withValues(alpha: .1),
                              child: const Icon(
                                Icons.person_outline,
                                color: gold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                w['name'],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 32,
                          runSpacing: 18,
                          children: [
                            for (final item in [
                              ('Horas', hours(w['minutes'])),
                              ('Produzido + ajustes', money(w['produced'])),
                              ('Recebido', money(w['received'])),
                              ('Pendente acumulado', money(w['pending'])),
                            ])
                              SizedBox(
                                width: 180,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$1,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item.$2,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _comparison(int value, int old) => old == 0
      ? 'Anterior: ${money(old)} • sem base percentual'
      : '${value >= old ? '+' : '−'}${((value - old).abs() * 100 / old).toStringAsFixed(1).replaceAll('.', ',')}% em relação ao período anterior';
  Widget _insight(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: gold),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
      ],
    ),
  );
}

class AdaptivePanels extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  const AdaptivePanels({
    super.key,
    required this.children,
    this.breakpoint = 760,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < breakpoint
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: children[i]),
              ],
            ],
          ),
  );
}

class InsightMetric extends StatelessWidget {
  final String label, value, detail;
  final Color color;
  final IconData icon;
  const InsightMetric({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: const TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class ReportPanel extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const ReportPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    ),
  );
}

class ReportEmpty extends StatelessWidget {
  final String message;
  final IconData icon;
  const ReportEmpty(this.message, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Center(
      child: Column(
        children: [
          Icon(icon, color: Colors.grey, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

class MonthlyChart extends StatelessWidget {
  final Ledger ledger;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const MonthlyChart({
    super.key,
    required this.ledger,
    required this.selected,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    const names = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    final months = List.generate(
      6,
      (i) => DateTime(selected.year, selected.month - 5 + i),
    );
    final data = months
        .map((m) => ledger.finance(DateRange.forDate(m, Period.month)))
        .toList();
    final maximum = data.fold<int>(
      0,
      (v, d) => [v, d.income, d.expenses].reduce((a, b) => a > b ? a : b),
    );
    if (maximum == 0)
      return const ReportEmpty(
        'Sem movimentações nos últimos 6 meses.',
        Icons.bar_chart,
      );
    return Column(
      children: [
        const Row(
          children: [
            Icon(Icons.circle, size: 8, color: green),
            SizedBox(width: 6),
            Text('Entradas', style: TextStyle(fontSize: 12)),
            SizedBox(width: 20),
            Icon(Icons.circle, size: 8, color: red),
            SizedBox(width: 6),
            Text('Despesas', style: TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Escala até ${money(maximum)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < months.length; i++)
                Expanded(
                  child: Tooltip(
                    message:
                        '${names[months[i].month - 1]} ${months[i].year}\nEntradas: ${money(data[i].income)}\nDespesas: ${money(data[i].expenses)}',
                    child: InkWell(
                      onTap: () => onSelect(months[i]),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 172,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 172 * data[i].income / maximum,
                                      decoration: BoxDecoration(
                                        color: green,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Container(
                                      height: 172 * data[i].expenses / maximum,
                                      decoration: BoxDecoration(
                                        color: red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              names[months[i].month - 1],
                              style: TextStyle(
                                fontSize: 12,
                                color: i == 5 ? gold : Colors.grey,
                              ),
                            ),
                            Text(
                              '${months[i].year}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Uma escala para todos os meses. Meses sem registros ficam vazios.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
