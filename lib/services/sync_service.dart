import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database.dart';

// Local SQLite table name compared to the Firestore subcollection name.
const Map<String, String> _collectionForTable = {
  'Money_Transfers': 'money_transfers',
  'Merchant_Payment': 'merchant_payments',
  'Bundles': 'bundles',
  'Bank_Transfers': 'bank_transfers',
  'Others': 'others',
  'Agent_Transactions': 'agent_transactions',
  'Utilities': 'utilities',
};

const List<String> _settingsFields = [
  'General_Spending_Limit',
  'Money_Transfer_Limit',
  'Bank_Transfer_Limit',
  'Merchant_Limit',
  'Bundles_Limit',
  'Utilities_Limit',
  'Agent_Limit',
  'Others_Limit',
];

// Pushes local data to online.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> pushLocalToCloud({
    required Database db,
    required String uid,
    required String phoneNumber,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);

    final userRows = await db.query('Users', where: 'Phone_Number = ?', whereArgs: [phoneNumber], limit: 1);
    final settingsRows =
        await db.query('Settings', where: 'Phone_Number = ?', whereArgs: [phoneNumber], limit: 1);

    final profile = <String, Object?>{'Phone_Number': phoneNumber};
    if (userRows.isNotEmpty) {
      profile['Name'] = userRows.first['Name'];
      profile['Amount'] = userRows.first['Amount'];
    }
    if (settingsRows.isNotEmpty) {
      for (final field in _settingsFields) {
        profile[field] = settingsRows.first[field];
      }
    }
    await userDoc.set(profile, SetOptions(merge: true));

    var pushedCount = 0;
    for (final table in AppDatabase.transactionTables.keys) {
      final idColumn = AppDatabase.transactionTables[table]!;
      final collectionName = _collectionForTable[table]!;
      final rows = await db.query(table, where: 'Phone_Number = ?', whereArgs: [phoneNumber]);
      if (rows.isEmpty) continue;

      for (var i = 0; i < rows.length; i += 500) {
        final chunk = rows.sublist(i, i + 500 > rows.length ? rows.length : i + 500);
        final batch = _firestore.batch();
        for (final row in chunk) {
          final id = row[idColumn] as String;
          batch.set(
            userDoc.collection(collectionName).doc(id),
            Map<String, Object?>.from(row),
            SetOptions(merge: true),
          );
        }
        await batch.commit();
        pushedCount += chunk.length;
      }
    }

    return pushedCount;
  }

  // Pulls all cloud data down into the local SQLite DB(for example on a new phone or when logged out).
  Future<String?> pullCloudToLocal({
    required Database db,
    required String uid,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);
    final profileSnap = await userDoc.get();
    if (!profileSnap.exists) return null;

    final profile = profileSnap.data()!;
    final phoneNumber = profile['Phone_Number'] as String?;
    if (phoneNumber == null) return null;

    await db.insert(
      'Users',
      {
        'Phone_Number': phoneNumber,
        'Name': profile['Name'],
        'Firebase_Uid': uid,
        'Amount': profile['Amount'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (profile.containsKey('General_Spending_Limit')) {
      final settingsRow = <String, Object?>{
        'Settings_Id': 'SETTINGS-$phoneNumber',
        'Phone_Number': phoneNumber,
      };
      for (final field in _settingsFields) {
        settingsRow[field] = profile[field] ?? 0;
      }
      await db.insert('Settings', settingsRow, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final table in AppDatabase.transactionTables.keys) {
      final collectionName = _collectionForTable[table]!;
      final snap = await userDoc.collection(collectionName).get();
      for (final doc in snap.docs) {
        await db.insert(table, Map<String, Object?>.from(doc.data()), conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    return phoneNumber;
  }
}
