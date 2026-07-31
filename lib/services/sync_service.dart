import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database.dart';

// Local SQLite table name similar to the Firestore subcollection name.
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

  static String normalizePhoneNumber(String phoneNumber) {
    var digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10 && digits.startsWith('0')) {
      digits = '250${digits.substring(1)}';
    } else if (digits.length == 9) {
      digits = '250$digits';
    }
    return digits;
  }

  Future<bool> deleteTransaction({
    required Database db,
    required String uid,
    required String phoneNumber,
    required String table,
    required String id,
  }) async {
    final idColumn = AppDatabase.transactionTables[table];
    final collectionName = _collectionForTable[table];
    if (idColumn == null || collectionName == null) {
      throw ArgumentError('Unsupported transaction table: $table');
    }

    await db.transaction((txn) async {
      await txn.insert(
        'Deletion_Tombstones',
        {
          'Firebase_Uid': uid,
          'Table_Name': table,
          'Collection_Name': collectionName,
          'Document_Id': id,
          'Cloud_Deleted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        table,
        where: '$idColumn = ? AND Phone_Number = ?',
        whereArgs: [id, phoneNumber],
      );
    });

    // Cloud I/O must never delay the local UI. The tombstone makes this safe:
    // it is retried during every sync and prevents the row being re-created.
    unawaited(
      _flushDeletionTombstones(
        db: db,
        uid: uid,
      ).catchError((Object _) {
        // The durable tombstone will retry on the next sync.
      }),
    );
    return false;
  }

  Future<void> _flushDeletionTombstones({
    required Database db,
    required String uid,
  }) async {
    final pending = await db.query(
      'Deletion_Tombstones',
      where: 'Firebase_Uid = ? AND Cloud_Deleted = 0',
      whereArgs: [uid],
    );
    for (final tombstone in pending) {
      final collectionName = tombstone['Collection_Name'] as String;
      final documentId = tombstone['Document_Id'] as String;
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection(collectionName)
            .doc(documentId)
            .delete();
        await db.update(
          'Deletion_Tombstones',
          {'Cloud_Deleted': 1},
          where: 'Firebase_Uid = ? AND Table_Name = ? AND Document_Id = ?',
          whereArgs: [uid, tombstone['Table_Name'], documentId],
        );
      } catch (_) {
        // Keep the tombstone pending. A later manual or automatic sync retries.
      }
    }
  }

  Future<int> pushLocalToCloud({
    required Database db,
    required String uid,
    required String phoneNumber,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);
    await _flushDeletionTombstones(db: db, uid: uid);

    await pushProfileToCloud(
      db: db,
      uid: uid,
      phoneNumber: phoneNumber,
    );

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

  Future<void> pushProfileToCloud({
    required Database db,
    required String uid,
    required String phoneNumber,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);
    final userRows = await db.query('Users', where: 'Phone_Number = ?', whereArgs: [phoneNumber], limit: 1);
    final settingsRows =
        await db.query('Settings', where: 'Phone_Number = ?', whereArgs: [phoneNumber], limit: 1);

    final profile = <String, Object?>{
      'Firebase_Uid': uid,
      'Phone_Number': phoneNumber,
      'Updated_At': FieldValue.serverTimestamp(),
    };
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
        final tombstone = await db.query(
          'Deletion_Tombstones',
          columns: ['Document_Id'],
          where: 'Firebase_Uid = ? AND Table_Name = ? AND Document_Id = ?',
          whereArgs: [uid, table, doc.id],
          limit: 1,
        );
        if (tombstone.isNotEmpty) continue;
        await db.insert(table, Map<String, Object?>.from(doc.data()), conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    return phoneNumber;
  }
}
