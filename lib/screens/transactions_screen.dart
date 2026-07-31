import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/sqlite_date.dart';

class _Transaction {
  final String id;
  final String type; // 'sent' | 'received'
  final String? recipient;
  final String? phone;
  final double amount;
  final String category;
  final String date;
  final String table;

  _Transaction({
    required this.id,
    required this.type,
    this.recipient,
    this.phone,
    required this.amount,
    required this.category,
    required this.date,
    required this.table,
  });
}

class TransactionsScreen extends StatefulWidget {
  final Database? db;
  final String userPhone;
  final String period;
  final void Function(String period) onPeriodChange;
  final int? lastSyncAt;
  final Future<bool> Function(String table, String id) onDelete;

  const TransactionsScreen({
    super.key,
    required this.db,
    required this.userPhone,
    required this.period,
    required this.onPeriodChange,
    required this.lastSyncAt,
    required this.onDelete,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<_Transaction> _transactions = [];
  String _searchQuery = '';
  double _receivedTotal = 0;
  double _sentTotal = 0;
  bool _isLoading = true;
  DateTime _viewedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _viewedMonth.year == now.year && _viewedMonth.month == now.month;
  }

  void _goToPreviousMonth() {
    setState(() => _viewedMonth = DateTime(_viewedMonth.year, _viewedMonth.month - 1));
    _loadTransactions();
  }

  void _goToNextMonth() {
    if (_isCurrentMonth) return;
    setState(() => _viewedMonth = DateTime(_viewedMonth.year, _viewedMonth.month + 1));
    _loadTransactions();
  }

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void didUpdateWidget(covariant TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db ||
        oldWidget.userPhone != widget.userPhone ||
        oldWidget.period != widget.period ||
        oldWidget.lastSyncAt != widget.lastSyncAt) {
      _loadTransactions();
    }
  }

  double _asDouble(Object? v) => (v as num?)?.toDouble() ?? 0;

  Future<void> _loadTransactions() async {
    final db = widget.db;
    if (db == null || widget.userPhone.isEmpty) {
      setState(() => _isLoading = true);
      return;
    }

    setState(() => _isLoading = true);

    final String whereClause;
    final List<Object?> whereArgs;
    if (widget.period == 'monthly') {
      final startDate = DateTime(_viewedMonth.year, _viewedMonth.month, 1);
      final endDate = DateTime(_viewedMonth.year, _viewedMonth.month + 1, 1);
      whereClause = 'Phone_Number = ? AND Date >= ? AND Date < ?';
      whereArgs = [
        widget.userPhone,
        toSqliteDate(startDate),
        toSqliteDate(endDate),
      ];
    } else {
      final startDate = DateTime.now().subtract(Duration(days: 7));
      whereClause = 'Phone_Number = ? AND Date >= ?';
      whereArgs = [widget.userPhone, toSqliteDate(startDate)];
    }

    final all = <_Transaction>[];

    final moneyTransfers =
        await db.query('Money_Transfers', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in moneyTransfers) {
      all.add(_Transaction(
        id: row['Transfer_Id'] as String,
        type: row['Transaction_Type'] as String,
        recipient: row['Recipient_Name'] as String?,
        phone: row['Recipient_Phone'] as String?,
        amount: _asDouble(row['Amount']),
        category: 'Transfer',
        date: row['Date'] as String? ?? '',
        table: 'Money_Transfers',
      ));
    }

    final merchantPayments =
        await db.query('Merchant_Payment', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in merchantPayments) {
      all.add(_Transaction(
        id: row['Transfer_Id'] as String,
        type: 'sent',
        recipient: row['Recipient_Name'] as String?,
        phone: row['Recipient_Code'] as String?,
        amount: _asDouble(row['Amount']),
        category: 'Merchant',
        date: row['Date'] as String? ?? '',
        table: 'Merchant_Payment',
      ));
    }

    final bundles =
        await db.query('Bundles', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in bundles) {
      final isData = row['Bundle_Type'] == 'DATA';
      all.add(_Transaction(
        id: row['Bundle_Id'] as String,
        type: 'sent',
        recipient: isData ? 'MTN Data' : 'MTN Airtime',
        amount: _asDouble(row['Amount']),
        category: isData ? 'Data' : 'Airtime',
        date: row['Date'] as String? ?? '',
        table: 'Bundles',
      ));
    }

    final bankTransfers =
        await db.query('Bank_Transfers', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in bankTransfers) {
      all.add(_Transaction(
        id: row['Transfer_Id'] as String,
        type: row['Transaction_Type'] as String,
        recipient: 'Bank Transfer',
        amount: _asDouble(row['Amount']),
        category: 'Bank',
        date: row['Date'] as String? ?? '',
        table: 'Bank_Transfers',
      ));
    }

    final others =
        await db.query('Others', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in others) {
      all.add(_Transaction(
        id: row['Other_Id'] as String,
        type: 'sent',
        recipient: (row['Name'] as String?) ?? 'Other',
        amount: _asDouble(row['Amount']),
        category: 'Other',
        date: row['Date'] as String? ?? '',
        table: 'Others',
      ));
    }

    final agentTransactions =
        await db.query('Agent_Transactions', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in agentTransactions) {
      all.add(_Transaction(
        id: row['Transaction_Id'] as String,
        type: 'sent',
        recipient: (row['Agent_Name'] as String?) ?? 'Agent',
        amount: _asDouble(row['Amount']),
        category: 'Agent',
        date: row['Date'] as String? ?? '',
        table: 'Agent_Transactions',
      ));
    }

    final utilities =
        await db.query('Utilities', where: whereClause, whereArgs: whereArgs, orderBy: 'Date DESC', limit: 100);
    for (final row in utilities) {
      all.add(_Transaction(
        id: row['Transaction_Id'] as String,
        type: 'sent',
        recipient: row['Name'] as String?,
        amount: _asDouble(row['Amount']),
        category: 'Utility',
        date: row['Date'] as String? ?? '',
        table: 'Utilities',
      ));
    }

    all.sort((a, b) {
      final dateA = DateTime.tryParse(a.date) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = DateTime.tryParse(b.date) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    final received = all.where((t) => t.type == 'received').fold<double>(0, (sum, t) => sum + t.amount);
    final sent = all.where((t) => t.type == 'sent').fold<double>(0, (sum, t) => sum + t.amount);

    if (!mounted) return;
    setState(() {
      _transactions = all;
      _receivedTotal = received;
      _sentTotal = sent;
      _isLoading = false;
    });
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Unknown date';
    final date = DateTime.tryParse(dateString);
    if (date == null) return 'Unknown date';
    final now = DateTime.now();
    final diffDays = now.difference(date).inDays.abs() + 1;
    if (diffDays == 1) return 'Today';
    if (diffDays == 2) return 'Yesterday';
    if (diffDays <= 7) return '${diffDays - 1} days ago';
    return DateFormat.yMd().format(date);
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Airtime':
      case 'Data':
        return Icons.smartphone;
      case 'Utility':
        return Icons.bolt;
      case 'Merchant':
        return Icons.shopping_cart;
      case 'Bank':
        return Icons.account_balance;
      case 'Agent':
        return Icons.store;
      case 'Other':
        return Icons.category;
      default:
        return Icons.attach_money;
    }
  }

  Future<void> _confirmDelete(_Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete transaction?'),
        content: Text(
          'This permanently removes the transaction from this device and your cloud backup.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.onDelete(
        transaction.table,
        transaction.id,
      );
      await _loadTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction deleted. Cloud synchronization is scheduled.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete transaction. Check your connection and try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.decimalPattern();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _transactions.where((t) {
      final q = _searchQuery.toLowerCase();
      return (t.recipient ?? '').toLowerCase().contains(q) || t.category.toLowerCase().contains(q);
    }).toList();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(child: Text('Loading transactions...', style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Transactions', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                  SizedBox(height: 4),
                  if (widget.period == 'monthly')
                    Row(
                      children: [
                        _MonthNavButton(icon: Icons.chevron_left, onTap: _goToPreviousMonth),
                        SizedBox(
                          width: 120,
                          child: Text(
                            DateFormat('MMMM yyyy').format(_viewedMonth),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ),
                        _MonthNavButton(
                          icon: Icons.chevron_right,
                          onTap: _isCurrentMonth ? null : _goToNextMonth,
                        ),
                      ],
                    )
                  else
                    Text('This Week', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _PeriodToggle(period: widget.period, onChanged: widget.onPeriodChange),
            ),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 48,
                padding: EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search transactions...',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          border: InputBorder.none,
                        ),
                        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.arrow_downward,
                      iconBg: isDark ? Color(0xFF17362F) : Color(0xFFD1FAE5),
                      iconColor: Color(0xFF059669),
                      label: 'Received',
                      amount: 'RWF ${numberFormat.format(_receivedTotal)}',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.arrow_upward,
                      iconBg: isDark ? Color(0xFF3B2227) : Color(0xFFFEE2E2),
                      iconColor: Color(0xFFDC2626),
                      label: 'Sent',
                      amount: 'RWF ${numberFormat.format(_sentTotal)}',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text('No transactions found', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)))
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 100),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        final isReceived = t.type == 'received';
                        return Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isReceived
                                          ? (isDark ? Color(0xFF17362F) : Color(0xFFD1FAE5))
                                          : (isDark ? Color(0xFF3B2227) : Color(0xFFFEE2E2)),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        isReceived ? Icons.arrow_downward : _categoryIcon(t.category),
                                        size: 20,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.recipient ?? 'Unknown',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                                        ),
                                        if (t.phone != null)
                                          Text(t.phone!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${isReceived ? '+' : '-'}RWF ${numberFormat.format(t.amount)}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isReceived ? Color(0xFF059669) : Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark ? Color(0xFF2D2813) : Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(t.category,
                                            style: TextStyle(fontSize: 10, color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    tooltip: 'Delete transaction',
                                    onPressed: () => _confirmDelete(t),
                                    icon: Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDate(t.date), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? Color(0xFF17362F) : Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('Completed',
                                        style: TextStyle(fontSize: 10, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String amount;

  const _SummaryCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Center(child: Icon(icon, size: 20, color: iconColor)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    maxLines: 1,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MonthNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.all(4),
        child: Icon(icon, size: 20, color: enabled ? Theme.of(context).colorScheme.onSurfaceVariant : Color(0xFFD1D5DB)),
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
