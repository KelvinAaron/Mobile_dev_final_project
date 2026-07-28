import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finmo/components/budget_alert_overlay.dart';
import 'package:finmo/database/database.dart';
import 'package:finmo/utils/budget_utils.dart';
import 'package:finmo/utils/extract_balance.dart';
import 'package:finmo/utils/parse_momo_message.dart';

const _phone = '250780000000';

Future<Database> _openTestDb() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await AppDatabase.instance.createTables(db);
  await db.insert('Users', {'Phone_Number': _phone, 'Name': 'Test User', 'Amount': 0});
  return db;
}

Widget _wrapOverlay(Widget child) => MaterialApp(home: Scaffold(body: Stack(children: [child])));

void main() {
  // parseMomoMessage

  group('parseMomoMessage', () {
    group('Money Transfers (received)', () {
      const body = 'You have received 2,000 RWF from Jane Smith (*********013) on your '
          'mobile money account at 2024-05-10 16:30:51. Your new balance:2000 RWF. '
          'Financial Transaction Id: 76662021700.';

      test('parses into Money_Transfers as received', () {
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Money_Transfers');
        expect(result.data['Recipient_Name'], 'Jane Smith');
        expect(result.data['Recipient_Phone'], '*********013');
        expect(result.data['Amount'], 2000);
        expect(result.data['Transaction_Type'], 'received');
        expect(result.data['Date'], '2024-05-10 16:30:51');
        expect(result.data['Transfer_Id'], startsWith('M-'));
      });
    });

    group('Money Transfers (sent)', () {
      const body = '*165*S*1000 RWF transferred to John Doe (250788123456) at '
          '2024-05-10 16:31:39. Fee was 100 RWF. New balance: 5000 RWF.';

      test('parses into Money_Transfers as sent', () {
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Money_Transfers');
        expect(result.data['Recipient_Name'], 'John Doe');
        expect(result.data['Recipient_Phone'], '250788123456');
        expect(result.data['Amount'], 1000);
        expect(result.data['Fee'], 100);
        expect(result.data['Transaction_Type'], 'sent');
        expect(result.data['Transfer_Id'], startsWith('M-'));
      });
    });

    group('Merchant payments', () {
      const body = 'TxId: 73214484437. Your payment of 1,000 RWF to Jane Smith 12845 '
          'has been completed at 2024-05-10 16:31:39. Your new balance: 1,000 RWF. Fee was 0 RWF.';

      test('parses into Merchant_Payment', () {
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Merchant_Payment');
        expect(result.data['Recipient_Name'], 'Jane Smith');
        expect(result.data['Recipient_Code'], '12845');
        expect(result.data['Amount'], 1000);
        expect(result.data['Fee'], 0);
        expect(result.data['Transfer_Id'], startsWith('MD-'));
      });
    });

    group('Agent withdrawals', () {
      const body = 'You have withdrawn 5000 RWF from Agent John at 2024-05-10 16:31:39. '
          'Fee paid: 100 RWF. Your new balance: 3000 RWF.';

      test('parses into Agent_Transactions', () {
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Agent_Transactions');
        expect(result.data['Agent_Name'], 'John');
        expect(result.data['Amount'], 5000);
        expect(result.data['Fee'], 100);
        expect(result.data['Transaction_Id'], startsWith('AG-'));
      });
    });

    group('Bank transfers', () {
      const body = '*113*A deposit of 10000 RWF has been made to your mobile money '
          'account at 2024-05-10 16:31:39. Your new balance: 15000 RWF.';

      test('parses into Bank_Transfers as received', () {
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Bank_Transfers');
        expect(result.data['Amount'], 10000);
        expect(result.data['Transaction_Type'], 'received');
        expect(result.data['Fee'], 0);
        expect(result.data['Transfer_Id'], startsWith('BKD-'));
      });
    });

    group('Bundles', () {
      test('classifies "Bundles and Packs" as DATA', () {
        const body = 'Your payment of 2000 RWF for Bundles and Packs was successful '
            'at 2024-05-10 16:31:39. Your new balance: 8000 RWF.';
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Bundles');
        expect(result.data['Bundle_Type'], 'DATA');
        expect(result.data['Amount'], 2000);
        expect(result.data['Bundle_Id'], startsWith('MTNB-'));
      });

      test('classifies "Airtime" as AIRTIME', () {
        const body = 'Your payment of 500 RWF for Airtime was successful '
            'at 2024-05-10 16:31:39. Your new balance: 7500 RWF.';
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Bundles');
        expect(result.data['Bundle_Type'], 'AIRTIME');
        expect(result.data['Amount'], 500);
      });
    });

    group('Utilities', () {
      const body = '*162*Your payment of 3000 RWF to EWSA with token 12345 has been '
          'completed at 2024-05-10 16:31:39. Fee was 0 RWF. Your new balance: 4500 RWF.';

      test('parses into Utilities', () {
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Utilities');
        expect(result.data['Name'], 'EWSA');
        expect(result.data['Amount'], 3000);
        expect(result.data['Fee'], 0);
        expect(result.data['Transaction_Id'], startsWith('UTL-'));
      });
    });

    group('Others fallback', () {
      test('extracts name/amount for *164 reversal messages, stripping thousands commas', () {
        const body = '*164*A transaction of 1,234 RWF by John Doe on your MOMO account '
            'was reversed at 2024-05-10 16:31:39.';
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Others');
        expect(result.data['Name'], 'John Doe');
        expect(result.data['Amount'], 1234);
        expect(result.data['Description'], body);
        expect(result.data['Other_Id'], startsWith('OTR-'));
      });

      test('falls back to zero amount and null name for unrecognized messages', () {
        const body = 'Your account was flagged for review at 2024-05-10 16:31:39.';
        final result = parseMomoMessage(body, _phone);
        expect(result.table, 'Others');
        expect(result.data['Name'], isNull);
        expect(result.data['Amount'], 0);
        expect(result.data['Description'], body);
      });
    });

    group('Deterministic IDs', () {
      const body = 'You have received 2,000 RWF from Jane Smith (*********013) on your '
          'mobile money account at 2024-05-10 16:30:51. Your new balance:2000 RWF.';

      test('the same message body always produces the same ID', () {
        final first = parseMomoMessage(body, _phone);
        final second = parseMomoMessage(body, _phone);
        expect(first.data['Transfer_Id'], second.data['Transfer_Id']);
      });

      test('different message bodies produce different IDs', () {
        const otherBody = 'You have received 5,000 RWF from Bob Jones (*********099) on '
            'your mobile money account at 2024-05-11 09:00:00. Your new balance:5000 RWF.';
        final first = parseMomoMessage(body, _phone);
        final second = parseMomoMessage(otherBody, _phone);
        expect(first.data['Transfer_Id'], isNot(second.data['Transfer_Id']));
      });
    });
  });

  // extractBalance

  group('extractBalance', () {
    test('extracts from "Your new balance: X RWF", stripping thousands commas', () {
      expect(extractBalance('...at 2024-05-10. Your new balance: 21,705 RWF.'), 21705);
    });

    test('extracts from "new balance: X RWF" without "Your" prefix', () {
      expect(extractBalance('Transaction complete. new balance: 5000 RWF'), 5000);
    });

    test('extracts from "Balance: X RWF"', () {
      expect(extractBalance('Balance: 100 RWF as of today'), 100);
    });

    test('extracts from lowercase "balance" with a space instead of colon', () {
      expect(extractBalance('your balance 250 RWF'), 250);
    });

    test('prefers the more specific "Your new balance" pattern when multiple could match', () {
      const body = 'Balance: 999 RWF. Your new balance: 21,705 RWF.';
      expect(extractBalance(body), 21705);
    });

    test('returns null when no balance is mentioned', () {
      expect(extractBalance('You have received 2000 RWF from Jane Smith.'), isNull);
    });

    test('returns null for malformed balance text with no digits', () {
      expect(extractBalance('Your new balance: RWF'), isNull);
    });
  });

  // checkBudgetLimits
 
  group('checkBudgetLimits', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('returns no alerts when the user has no Settings row yet', () async {
      final db = await _openTestDb();
      final alerts = await checkBudgetLimits(db, _phone);
      expect(alerts, isEmpty);
      await db.close();
    });

    test('returns no alerts when spending is under every limit', () async {
      final db = await _openTestDb();
      await db.insert('Settings', {
        'Settings_Id': 'SETTINGS-$_phone',
        'Phone_Number': _phone,
        'Money_Transfer_Limit': 1000,
      });
      await db.insert('Money_Transfers', {
        'Transfer_Id': 'M-1',
        'Phone_Number': _phone,
        'Amount': 500,
        'Transaction_Type': 'sent',
        'Date': DateTime.now().toIso8601String(),
      });

      final alerts = await checkBudgetLimits(db, _phone);
      expect(alerts, isEmpty);
      await db.close();
    });

    test('flags overall spending when General_Spending_Limit is exceeded', () async {
      final db = await _openTestDb();
      await db.insert('Settings', {
        'Settings_Id': 'SETTINGS-$_phone',
        'Phone_Number': _phone,
        'General_Spending_Limit': 1000,
      });
      await db.insert('Money_Transfers', {
        'Transfer_Id': 'M-1',
        'Phone_Number': _phone,
        'Amount': 1500,
        'Transaction_Type': 'sent',
        'Date': DateTime.now().toIso8601String(),
      });

      final alerts = await checkBudgetLimits(db, _phone);
      expect(alerts, hasLength(1));
      expect(alerts.first.category, 'Overall Monthly Spending');
      expect(alerts.first.exceeded, 500);
      await db.close();
    });

    test('flags a category-specific limit independently of the general limit', () async {
      final db = await _openTestDb();
      await db.insert('Settings', {
        'Settings_Id': 'SETTINGS-$_phone',
        'Phone_Number': _phone,
        'Money_Transfer_Limit': 500,
      });
      await db.insert('Money_Transfers', {
        'Transfer_Id': 'M-1',
        'Phone_Number': _phone,
        'Amount': 800,
        'Transaction_Type': 'sent',
        'Date': DateTime.now().toIso8601String(),
      });

      final alerts = await checkBudgetLimits(db, _phone);
      expect(alerts, hasLength(1));
      expect(alerts.first.category, 'Money Transfers');
      expect(alerts.first.exceeded, 300);
      await db.close();
    });

    test('does not count received transfers toward the Money Transfers spend', () async {
      final db = await _openTestDb();
      await db.insert('Settings', {
        'Settings_Id': 'SETTINGS-$_phone',
        'Phone_Number': _phone,
        'Money_Transfer_Limit': 500,
      });
      await db.insert('Money_Transfers', {
        'Transfer_Id': 'M-1',
        'Phone_Number': _phone,
        'Amount': 10000,
        'Transaction_Type': 'received',
        'Date': DateTime.now().toIso8601String(),
      });

      final alerts = await checkBudgetLimits(db, _phone);
      expect(alerts, isEmpty);
      await db.close();
    });

    test('ignores transactions from a previous month', () async {
      final db = await _openTestDb();
      await db.insert('Settings', {
        'Settings_Id': 'SETTINGS-$_phone',
        'Phone_Number': _phone,
        'Bundles_Limit': 100,
      });
      final lastMonth = DateTime.now().subtract(const Duration(days: 40)).toIso8601String();
      await db.insert('Bundles', {
        'Bundle_Id': 'B-1',
        'Phone_Number': _phone,
        'Bundle_Type': 'DATA',
        'Bundle_Amount': 0,
        'Amount': 5000,
        'Date': lastMonth,
      });

      final alerts = await checkBudgetLimits(db, _phone);
      expect(alerts, isEmpty);
      await db.close();
    });

    test('can flag multiple exceeded categories at once', () async {
      final db = await _openTestDb();
      await db.insert('Settings', {
        'Settings_Id': 'SETTINGS-$_phone',
        'Phone_Number': _phone,
        'Money_Transfer_Limit': 100,
        'Utilities_Limit': 100,
      });
      final now = DateTime.now().toIso8601String();
      await db.insert('Money_Transfers', {
        'Transfer_Id': 'M-1',
        'Phone_Number': _phone,
        'Amount': 200,
        'Transaction_Type': 'sent',
        'Date': now,
      });
      await db.insert('Utilities', {
        'Transaction_Id': 'UTL-1',
        'Phone_Number': _phone,
        'Name': 'EWSA',
        'Amount': 300,
        'Date': now,
      });

      final alerts = await checkBudgetLimits(db, _phone);
      final categories = alerts.map((a) => a.category).toSet();
      expect(categories, {'Money Transfers', 'Utilities'});
      await db.close();
    });
  });

  // BudgetAlertOverlay widget

  group('BudgetAlertOverlay', () {
    testWidgets('renders nothing when visible is false', (tester) async {
      await tester.pumpWidget(_wrapOverlay(BudgetAlertOverlay(
        alerts: [BudgetAlert(category: 'Money Transfers', exceeded: 500)],
        visible: false,
        onClose: () {},
      )));

      expect(find.textContaining('budget exceeded'), findsNothing);
    });

    testWidgets('renders nothing when alerts is empty even if visible is true', (tester) async {
      await tester.pumpWidget(_wrapOverlay(BudgetAlertOverlay(
        alerts: const [],
        visible: true,
        onClose: () {},
      )));

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('renders one line per alert, formatted with thousands separators', (tester) async {
      await tester.pumpWidget(_wrapOverlay(BudgetAlertOverlay(
        alerts: [
          BudgetAlert(category: 'Money Transfers', exceeded: 500),
          BudgetAlert(category: 'Utilities', exceeded: 1234),
        ],
        visible: true,
        onClose: () {},
      )));

      expect(find.text('Money Transfers budget exceeded by 500 RWF'), findsOneWidget);
      expect(find.text('Utilities budget exceeded by 1,234 RWF'), findsOneWidget);
    });

    testWidgets('calls onClose when the close button is tapped', (tester) async {
      var closed = false;
      await tester.pumpWidget(_wrapOverlay(BudgetAlertOverlay(
        alerts: [BudgetAlert(category: 'Money Transfers', exceeded: 500)],
        visible: true,
        onClose: () => closed = true,
      )));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(closed, isTrue);
    });
  });
}
