import 'package:sqflite/sqflite.dart';

class BudgetAlert {
  final String category;
  final double exceeded;

  BudgetAlert({required this.category, required this.exceeded});
}

double _asDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

// spending per category
Future<List<BudgetAlert>> checkBudgetLimits(Database db, String userPhone) async {
  final alerts = <BudgetAlert>[];

  final settingsRows = await db.query(
    'Settings',
    where: 'Phone_Number = ?',
    whereArgs: [userPhone],
    limit: 1,
  );
  if (settingsRows.isEmpty) return alerts;
  final settings = settingsRows.first;

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

  Future<double> categoryTotal(String table, String filter) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(Amount), 0) as total FROM $table WHERE Phone_Number = ? AND Date >= ? $filter',
      [userPhone, monthStart],
    );
    return _asDouble(rows.first['total']);
  }

  final generalLimit = _asDouble(settings['General_Spending_Limit']);
  if (generalLimit > 0) {
    const categoryQueries = [
      ('Money_Transfers', "AND Transaction_Type = 'sent'"),
      ('Merchant_Payment', ''),
      ('Bundles', ''),
      ('Bank_Transfers', "AND Transaction_Type = 'sent'"),
      ('Others', ''),
      ('Agent_Transactions', ''),
      ('Utilities', ''),
    ];
    double totalSpending = 0;
    for (final (table, filter) in categoryQueries) {
      totalSpending += await categoryTotal(table, filter);
    }
    if (totalSpending > generalLimit) {
      alerts.add(BudgetAlert(
        category: 'Overall Monthly Spending',
        exceeded: totalSpending - generalLimit,
      ));
    }
  }

  Future<void> checkCategory(
    String limitKey,
    String category,
    String table, {
    String filter = '',
  }) async {
    final limit = _asDouble(settings[limitKey]);
    if (limit <= 0) return;
    final total = await categoryTotal(table, filter);
    if (total > limit) {
      alerts.add(BudgetAlert(category: category, exceeded: total - limit));
    }
  }

  await checkCategory('Money_Transfer_Limit', 'Money Transfers', 'Money_Transfers',
      filter: "AND Transaction_Type = 'sent'");
  await checkCategory('Bank_Transfer_Limit', 'Bank Transfers', 'Bank_Transfers',
      filter: "AND Transaction_Type = 'sent'");
  await checkCategory('Merchant_Limit', 'Merchant Payments', 'Merchant_Payment');
  await checkCategory('Bundles_Limit', 'Bundles', 'Bundles');
  await checkCategory('Utilities_Limit', 'Utilities', 'Utilities');
  await checkCategory('Agent_Limit', 'Agents', 'Agent_Transactions');
  await checkCategory('Others_Limit', 'Others', 'Others');

  return alerts;
}
