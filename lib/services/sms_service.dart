import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/extract_balance.dart';
import '../utils/parse_momo_message.dart';

class SmsSyncResult {
  final int insertedCount;
  final int maxMsgDate;

  SmsSyncResult({required this.insertedCount, required this.maxMsgDate});
}

class SmsService {
  SmsService._();

  static final SmsService instance = SmsService._();

  final Telephony _telephony = Telephony.instance;

  /// Reads M-Money SMS from the inbox extracting balance and transactions.
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
    for (final msg in messages) {
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
      final rowId = await db.insert(
        parsed.table,
        parsed.data,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (rowId != 0) insertedCount++;
    }

    return SmsSyncResult(insertedCount: insertedCount, maxMsgDate: maxMsgDate);
  }
}
