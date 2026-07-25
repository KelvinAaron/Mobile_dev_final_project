import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../styles/colors.dart';

class SpendingScreen extends StatefulWidget {
  final Database? db;
  final String userPhone;
  final String period;
  final void Function(String period)? onPeriodChange;
  final int? lastSyncAt;

  const SpendingScreen({
    super.key,
    required this.db,
    required this.userPhone,
    required this.period,
    this.onPeriodChange,
    required this.lastSyncAt,
  });

  @override
  State<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends State<SpendingScreen> {
  bool _isLoading = true;
  Map<String, double> _totals = {
    'moneyTransfers': 0,
    'bankTransfers': 0,
    'airtime': 0,
    'merchants': 0,
    'utilities': 0,
    'others': 0,
    'agents': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadTotals();
  }

  @override
  void didUpdateWidget(covariant SpendingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db ||
        oldWidget.userPhone != widget.userPhone ||
        oldWidget.period != widget.period ||
        oldWidget.lastSyncAt != widget.lastSyncAt) {
      _loadTotals();
    }
  }

  double _asDouble(Object? v) => (v as num?)?.toDouble() ?? 0;

  Future<void> _loadTotals() async {
    final db = widget.db;
    if (db == null || widget.userPhone.isEmpty) {
      setState(() => _isLoading = true);
      return;
    }

    setState(() => _isLoading = true);

    final now = DateTime.now();
    final startDate = widget.period == 'monthly'
        ? DateTime(now.year, now.month, 1).toIso8601String()
        : now.subtract(const Duration(days: 7)).toIso8601String();

    Future<double> total(String table, String filter) async {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(Amount),0) as total FROM $table WHERE Phone_Number = ? AND Date >= ? $filter',
        [widget.userPhone, startDate],
      );
      return _asDouble(rows.first['total']);
    }

    final moneyTransfers = await total('Money_Transfers', "AND Transaction_Type = 'sent'");
    final bankTransfers = await total('Bank_Transfers', "AND Transaction_Type = 'sent'");
    final airtime = await total('Bundles', '');
    final merchants = await total('Merchant_Payment', '');
    final utilities = await total('Utilities', '');
    final others = await total('Others', '');
    final agents = await total('Agent_Transactions', '');

    if (!mounted) return;
    setState(() {
      _totals = {
        'moneyTransfers': moneyTransfers,
        'bankTransfers': bankTransfers,
        'airtime': airtime,
        'merchants': merchants,
        'utilities': utilities,
        'others': others,
        'agents': agents,
      };
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.decimalPattern();
    final totalAll = _totals.values.fold<double>(0, (a, b) => a + b);
    final safeTotal = totalAll > 0 ? totalAll : 1;

    Widget row(String label, double value, Color color) {
      final pct = (value / safeTotal * 100).round();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
              ],
            ),
            const SizedBox(height: 6),
            Text('RWF ${numberFormat.format(value)}', style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (value / safeTotal).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 6),
            Text('$pct%', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFEF3C7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
          children: [
            const Text('Spending Breakdown', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
            const SizedBox(height: 4),
            Text(
              widget.period == 'monthly' ? 'This Month' : 'Last 7 days',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            if (widget.onPeriodChange != null) _PeriodToggle(period: widget.period, onChanged: widget.onPeriodChange!),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Categories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Text('Loading...', style: TextStyle(color: Color(0xFF6B7280)))
                  else ...[
                    row('Money Transfers', _totals['moneyTransfers']!, AppPalette.moneyTransfers),
                    row('Bank Transfers', _totals['bankTransfers']!, AppPalette.bankTransfers),
                    row('Airtime', _totals['airtime']!, AppPalette.bundles),
                    row('Merchants', _totals['merchants']!, AppPalette.merchantPayments),
                    row('Utilities', _totals['utilities']!, AppPalette.utilities),
                    row('Others', _totals['others']!, AppPalette.others),
                    row('Agents', _totals['agents']!, AppPalette.agentTransactions),
                  ],
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
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFFBBF24) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? const Color(0xFF1F2937) : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [button('weekly', 'Weekly'), const SizedBox(width: 4), button('monthly', 'Monthly')]),
    );
  }
}
