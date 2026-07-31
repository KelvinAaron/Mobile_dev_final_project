import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../styles/colors.dart';
import '../utils/sqlite_date.dart';

class OverviewScreen extends StatefulWidget {
  final Database? db;
  final String userPhone;
  final String period;
  final void Function(String period) onPeriodChange;
  final int? lastSyncAt;

  const OverviewScreen({
    super.key,
    required this.db,
    required this.userPhone,
    required this.period,
    required this.onPeriodChange,
    required this.lastSyncAt,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  double _balance = 0;
  double _periodSpending = 0;
  int _transactionCount = 0;
  int _sentCount = 0;
  int _receivedCount = 0;
  Map<String, double> _percentages = {
    'moneyTransfers': 0,
    'merchantPayments': 0,
    'bundles': 0,
    'bankTransfers': 0,
    'agentTransactions': 0,
    'others': 0,
    'utilities': 0,
  };
  bool _isLoading = true;
  bool _showBalance = true;

  static const _debitTables = [
    ('Money_Transfers', "AND Transaction_Type = 'sent'"),
    ('Merchant_Payment', ''),
    ('Bundles', ''),
    ('Bank_Transfers', "AND Transaction_Type = 'sent'"),
    ('Others', ''),
    ('Agent_Transactions', ''),
    ('Utilities', ''),
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant OverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db ||
        oldWidget.userPhone != widget.userPhone ||
        oldWidget.period != widget.period ||
        oldWidget.lastSyncAt != widget.lastSyncAt) {
      _loadStats();
    }
  }

  double _asDouble(Object? v) => (v as num?)?.toDouble() ?? 0;

  Future<void> _loadStats() async {
    final db = widget.db;
    if (db == null || widget.userPhone.isEmpty) {
      setState(() => _isLoading = true);
      return;
    }

    setState(() => _isLoading = true);

    final userRows =
        await db.query('Users', where: 'Phone_Number = ?', whereArgs: [widget.userPhone], limit: 1);
    final balance = userRows.isNotEmpty ? _asDouble(userRows.first['Amount']) : 0.0;

    final now = DateTime.now();
    final startDate = widget.period == 'monthly'
        ? toSqliteDate(DateTime(now.year, now.month, 1))
        : toSqliteDate(now.subtract(Duration(days: 7)));

    double periodDebits = 0;
    final categoryTotals = <String, double>{};
    for (final (table, filter) in _debitTables) {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(Amount), 0) as total FROM $table WHERE Phone_Number = ? AND Date >= ? $filter',
        [widget.userPhone, startDate],
      );
      final total = _asDouble(rows.first['total']);
      categoryTotals[table] = total;
      periodDebits += total;
    }

    final percentages = <String, double>{
      'moneyTransfers': 0,
      'merchantPayments': 0,
      'bundles': 0,
      'bankTransfers': 0,
      'agentTransactions': 0,
      'others': 0,
      'utilities': 0,
    };
    if (periodDebits > 0) {
      percentages['moneyTransfers'] = (categoryTotals['Money_Transfers']! / periodDebits) * 100;
      percentages['merchantPayments'] = (categoryTotals['Merchant_Payment']! / periodDebits) * 100;
      percentages['bundles'] = (categoryTotals['Bundles']! / periodDebits) * 100;
      percentages['bankTransfers'] = (categoryTotals['Bank_Transfers']! / periodDebits) * 100;
      percentages['agentTransactions'] = (categoryTotals['Agent_Transactions']! / periodDebits) * 100;
      percentages['others'] = (categoryTotals['Others']! / periodDebits) * 100;
      percentages['utilities'] = (categoryTotals['Utilities']! / periodDebits) * 100;
    }

    final allIdColumns = [
      ('Transfer_Id', 'Money_Transfers'),
      ('Transfer_Id', 'Merchant_Payment'),
      ('Bundle_Id', 'Bundles'),
      ('Transfer_Id', 'Bank_Transfers'),
      ('Other_Id', 'Others'),
      ('Transaction_Id', 'Agent_Transactions'),
      ('Transaction_Id', 'Utilities'),
    ];

    Future<int> countRows({required bool sentOnly}) async {
      final parts = <String>[];
      final args = <Object?>[];
      for (final (idCol, table) in allIdColumns) {
        final typeFilter = sentOnly && (table == 'Money_Transfers' || table == 'Bank_Transfers')
            ? "AND Transaction_Type = 'sent'"
            : '';
        parts.add('SELECT $idCol FROM $table WHERE Phone_Number = ? AND Date >= ? $typeFilter');
        args.addAll([widget.userPhone, startDate]);
      }
      final rows = await db.rawQuery('SELECT COUNT(*) as count FROM (${parts.join(' UNION ALL ')})', args);
      return (rows.first['count'] as int?) ?? 0;
    }

    final transactionCount = await countRows(sentOnly: false);
    final sentCount = await countRows(sentOnly: true);
    final receivedRows = await db.rawQuery(
      '''SELECT COUNT(*) as count FROM (
        SELECT Transfer_Id FROM Money_Transfers WHERE Phone_Number = ? AND Transaction_Type = 'received' AND Date >= ?
        UNION ALL
        SELECT Transfer_Id FROM Bank_Transfers WHERE Phone_Number = ? AND Transaction_Type = 'received' AND Date >= ?
      )''',
      [widget.userPhone, startDate, widget.userPhone, startDate],
    );

    if (!mounted) return;
    setState(() {
      _balance = balance;
      _periodSpending = periodDebits;
      _percentages = percentages;
      _transactionCount = transactionCount;
      _sentCount = sentCount;
      _receivedCount = (receivedRows.first['count'] as int?) ?? 0;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.decimalPattern();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(child: Text('Loading...', style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
        ),
      );
    }

    final categories = [
      ('moneyTransfers', 'Money Transfers', AppPalette.moneyTransfers),
      ('merchantPayments', 'Merchant Payments', AppPalette.merchantPayments),
      ('bundles', 'Bundles', AppPalette.bundles),
      ('bankTransfers', 'Bank Transfers', AppPalette.bankTransfers),
      ('agentTransactions', 'Agents', AppPalette.agentTransactions),
      ('others', 'Others', AppPalette.others),
      ('utilities', 'Utilities', AppPalette.utilities),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 100),
          children: [
            Text('Finmo', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 4),
            Text('Welcome back!', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 32),
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(color: Color(0xFFFBBF24), borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available Balance', style: TextStyle(fontSize: 14, color: Color(0xFF78350F))),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _showBalance
                              ? 'RWF ${numberFormat.format(_balance)}'
                              : 'RWF ••••••',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _showBalance ? 'Hide balance' : 'Show balance',
                        onPressed: () {
                          setState(() => _showBalance = !_showBalance);
                        },
                        icon: Icon(
                          _showBalance
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.period == 'monthly' ? 'This Month' : 'This Week',
                              style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                          SizedBox(height: 4),
                          Text('-RWF ${numberFormat.format(_periodSpending)}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onPrimary)),
                        ],
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface, borderRadius: BorderRadius.circular(20)),
                        child: Text('MTN MoMo', style: TextStyle(fontSize: 12, color: Color(0xFFFBBF24), fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            _PeriodToggle(period: widget.period, onChanged: widget.onPeriodChange),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _StatCard(value: '$_transactionCount', label: 'Transactions')),
                SizedBox(width: 12),
                Expanded(child: _StatCard(value: '$_sentCount', label: 'Sent')),
                SizedBox(width: 12),
                Expanded(child: _StatCard(value: '$_receivedCount', label: 'Received')),
              ],
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spending ${widget.period == 'monthly' ? 'This Month' : 'This Week'}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 120,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final (key, _, color) in categories)
                              if ((_percentages[key] ?? 0) > 0)
                                Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Container(
                                    width: 24,
                                    height: ((_percentages[key] ?? 0) / 100 * 120).clamp(8.0, 120.0),
                                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                                  ),
                                ),
                          ],
                        ),
                      ),
                      SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (key, label, color) in categories)
                              if ((_percentages[key] ?? 0) > 0)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$label ${(_percentages[key] ?? 0) >= 1 ? (_percentages[key] ?? 0).round() : (_percentages[key] ?? 0).toStringAsFixed(2)}%',
                                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
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
          ],
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  final String period;
  final void Function(String) onChanged;

  const _PeriodToggle({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget button(String value, String label) {
      final active = period == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: active ? Color(0xFFFBBF24) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [button('weekly', 'Weekly'), SizedBox(width: 4), button('monthly', 'Monthly')]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
