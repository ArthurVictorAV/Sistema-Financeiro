import 'domain.dart';

class Portfolio {
  final List<Json> accounts;
  Portfolio(Ledger ledger)
    : accounts = ledger.rows('asset')
        ..sort((a, b) => (b['balance'] as int).compareTo(a['balance']));
  int groupTotal(String group) => accounts
      .where((a) => a['group'] == group)
      .fold<int>(0, (total, a) => total + (a['balance'] as int));
  int get total =>
      accounts.fold<int>(0, (total, a) => total + (a['balance'] as int));
  int staleCount(DateTime now) => accounts
      .where(
        (a) =>
            DateTime(
              now.year,
              now.month,
              now.day,
            ).difference(DateTime.parse(a['date'])).inDays >
            30,
      )
      .length;
}

DateRange previousPeriod(DateTime selected, Period period) {
  final start = DateRange.forDate(selected, period).start;
  return DateRange.forDate(switch (period) {
    Period.day => start.subtract(const Duration(days: 1)),
    Period.week => start.subtract(const Duration(days: 7)),
    Period.month => DateTime(start.year, start.month - 1),
    Period.year => DateTime(start.year - 1),
  }, period);
}

class ReportData {
  final Ledger ledger;
  final DateRange range;
  ReportData(this.ledger, this.range);
  List<MapEntry<String, int>> get categories {
    final groups = <String, int>{};
    for (final t in ledger.transactions.where(
      (t) => range.contains(t['date']) && t['sign'] == -1,
    )) {
      final name = (t['category'] as String?)?.trim();
      final key = name == null || name.isEmpty ? 'Outros' : name;
      groups.update(
        key,
        (v) => v + (t['amount'] as int),
        ifAbsent: () => t['amount'],
      );
    }
    return groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  List<Json> get work =>
      ledger.rows('client').map((c) {
        final shifts = ledger
            .rows('shift')
            .where((s) => s['client'] == c['id'] && range.contains(s['date']));
        final minutes = shifts.fold<int>(
          0,
          (v, s) => v + (s['minutes'] as int),
        );
        final produced = shifts.fold<int>(
          0,
          (v, s) => v + earned(s['minutes'], s['rate']),
        );
        final adjustments = ledger
            .rows('adjustment')
            .where((a) => a['client'] == c['id'] && range.contains(a['date']))
            .fold<int>(
              0,
              (v, a) => v + (a['amount'] as int) * (a['sign'] as int),
            );
        final received = ledger
            .rows('payment')
            .where((p) => p['client'] == c['id'] && range.contains(p['date']))
            .fold<int>(0, (v, p) => v + (p['amount'] as int));
        return {
          'id': c['id'],
          'name': c['name'],
          'minutes': minutes,
          'produced': produced + adjustments,
          'received': received,
          'pending': ledger.totalDebt(c['id']),
        };
      }).toList()..sort(
        (a, b) => (b['pending'] as int).compareTo(a['pending'] as int),
      );
}
