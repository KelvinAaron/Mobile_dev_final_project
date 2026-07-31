import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database.dart';
import '../utils/extract_balance.dart';
import '../utils/parse_momo_message.dart';
import '../utils/sqlite_date.dart';

class SmsSyncResult {
  final int insertedCount;
  final int maxMsgDate;

  SmsSyncResult({required this.insertedCount, required this.maxMsgDate});
}

class SmsService {
  SmsService._();

  static final SmsService instance = SmsService._();

  final Telephony _telephony = Telephony.instance;

  // Reads M-Money SMS from the inbox extracting balance and transactions.
  Future<SmsSyncResult?> readMMoneyMessages({
    required Database db,
    required String userPhone,
    int minDate = 0,
  }) async {
    if (!Platform.isAndroid) return null;

    var filter = SmsFilter.where(SmsColumn.ADDRESS).equals('M-Money');
    final scopedFilter =
        minDate > 0 ? filter.and(SmsColumn.DATE).greaterThanOrEqualTo(minDate.toString()) : filter;

    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: scopedFilter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
    );

    int? latestBalance;
    for (final msg in messages.reversed) {
      final balance = extractBalance(msg.body ?? '');
      if (balance != null) {
        latestBalance = balance;
        break;
      }
    }
    if (latestBalance != null) {
      await db.update(
        'Users',
        {'Amount': latestBalance},
        where: 'Phone_Number = ?',
        whereArgs: [userPhone],
      );
    }

    var insertedCount = 0;
    var maxMsgDate = minDate;
    for (final msg in messages) {
      final msgDate = msg.date ?? DateTime.now().millisecondsSinceEpoch;
      if (msgDate > maxMsgDate) maxMsgDate = msgDate;

      final parsed = parseMomoMessage(msg.body ?? '', userPhone);
      final data = Map<String, Object?>.from(parsed.data);
      final parsedDate = data['Date'] as String?;
      if (parsedDate == null || parsedDate.trim().isEmpty) {
        data['Date'] = toSqliteDate(
          DateTime.fromMillisecondsSinceEpoch(msgDate),
        );
      }
      final idColumn = AppDatabase.transactionTables[parsed.table]!;
      final documentId = data[idColumn] as String;
      final deleted = await db.query(
        'Deletion_Tombstones',
        columns: ['Document_Id'],
        where: 'Table_Name = ? AND Document_Id = ?',
        whereArgs: [parsed.table, documentId],
        limit: 1,
      );
      if (deleted.isNotEmpty) {
        // Also repairs the narrow race where an SMS scan began just before the
        // user confirmed deletion.
        await db.delete(
          parsed.table,
          where: '$idColumn = ?',
          whereArgs: [documentId],
        );
        continue;
      }
      final rowId = await db.insert(
        parsed.table,
        data,
        // Replaces a previously imported copy whose parser-derived Date was
        // null, while keeping the deterministic transaction ID.
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (rowId != 0) insertedCount++;
    }

    return SmsSyncResult(insertedCount: insertedCount, maxMsgDate: maxMsgDate);
  }
}
