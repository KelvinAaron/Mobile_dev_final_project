// generates same id using const data
String _simpleHash(String str) {
  int hash = 0;
  for (final codeUnit in str.codeUnits) {
    hash = ((hash << 5) - hash + codeUnit).toSigned(32);
  }
  final hex = hash.abs().toRadixString(16);
  return hex.length <= 8 ? hex : hex.substring(0, 8);
}

String _generateIdFromMessage(String body, String? date, String prefix) {
  final hash = _simpleHash('$body|${date ?? ''}');
  return '$prefix-$hash';
}

class ParsedMomoMessage {
  final String table;
  final Map<String, Object?> data;

  ParsedMomoMessage({required this.table, required this.data});
}

String? _firstMatch(RegExp pattern, String body, {int group = 1}) {
  return pattern.firstMatch(body)?.group(group);
}

int _parseAmount(String? raw) {
  if (raw == null) return 0;
  return int.tryParse(raw.replaceAll(',', '')) ?? 0;
}

final _dateRegex = RegExp(r'at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})');
final _phoneRegex = RegExp(r'\((\**\d+)\)');


// pass the momo message into various categories
ParsedMomoMessage parseMomoMessage(String body, String userNumber) {
  // --- MONEY TRANSFERS (RECEIVED) ---
  if (body.contains('You have received')) {
    final name = _firstMatch(RegExp(r'from (\w+\s\w+)'), body);
    final amount = _parseAmount(_firstMatch(RegExp(r'received ([\d,]+) RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final phone = _firstMatch(_phoneRegex, body);
    final id = _generateIdFromMessage(body, date, 'M');

    return ParsedMomoMessage(table: 'Money_Transfers', data: {
      'Transfer_Id': id,
      'Phone_Number': userNumber,
      'Recipient_Name': name,
      'Recipient_Phone': phone,
      'Amount': amount,
      'Transaction_Type': 'received',
      'Date': date,
    });
  }

  // money transfers (sent)
  if (body.contains('*165*')) {
    final name = _firstMatch(RegExp(r'to (\w+\s\w+)'), body);
    final amount = _parseAmount(_firstMatch(RegExp(r'S\*(\d+)\s*RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final fee = _parseAmount(_firstMatch(RegExp(r'Fee was:? (\d+) RWF'), body));
    final phone = _firstMatch(_phoneRegex, body);
    final id = _generateIdFromMessage(body, date, 'M');

    return ParsedMomoMessage(table: 'Money_Transfers', data: {
      'Transfer_Id': id,
      'Phone_Number': userNumber,
      'Recipient_Name': name,
      'Recipient_Phone': phone,
      'Amount': amount,
      'Transaction_Type': 'sent',
      'Fee': fee,
      'Date': date,
    });
  }

  // code payments
  if (RegExp(r'^TxId').hasMatch(body)) {
    final name = _firstMatch(RegExp(r'to (\w+\s\w+)'), body);
    final amount = _parseAmount(_firstMatch(RegExp(r'of ([\d,]+) RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final fee = _parseAmount(_firstMatch(RegExp(r'Fee was:? (\d+) RWF'), body));
    final code = _firstMatch(RegExp(r'to [A-Za-z ]+ (\d+) has been completed'), body);
    final id = _generateIdFromMessage(body, date, 'MD');

    return ParsedMomoMessage(table: 'Merchant_Payment', data: {
      'Transfer_Id': id,
      'Phone_Number': userNumber,
      'Recipient_Name': name,
      'Recipient_Code': code,
      'Amount': amount,
      'Fee': fee,
      'Date': date,
    });
  }

  // agent transfers
  if (body.contains('Agent')) {
    final agentName = _firstMatch(RegExp(r'Agent (\w+)'), body);
    final amount = _parseAmount(_firstMatch(RegExp(r'withdrawn (\d+) RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final fee = _parseAmount(_firstMatch(RegExp(r'Fee paid: (\d+) RWF'), body));
    final id = _generateIdFromMessage(body, date, 'AG');

    return ParsedMomoMessage(table: 'Agent_Transactions', data: {
      'Transaction_Id': id,
      'Phone_Number': userNumber,
      'Agent_Name': agentName,
      'Amount': amount,
      'Fee': fee,
      'Date': date,
    });
  }

  // bank transfers
  if (body.contains('*113*')) {
    final amount = _parseAmount(_firstMatch(RegExp(r'deposit of (\d+) RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final id = _generateIdFromMessage(body, date, 'BKD');

    return ParsedMomoMessage(table: 'Bank_Transfers', data: {
      'Transfer_Id': id,
      'Phone_Number': userNumber,
      'Amount': amount,
      'Transaction_Type': 'received',
      'Fee': 0,
      'Date': date,
    });
  }

  // mtn bundles / airtime
  if (body.contains('Bundles and Packs') || body.contains('Airtime')) {
    final type = body.contains('Bundles and Packs') ? 'DATA' : 'AIRTIME';
    final amount = _parseAmount(_firstMatch(RegExp(r'payment of (\d+) RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final id = _generateIdFromMessage(body, date, 'MTNB');

    return ParsedMomoMessage(table: 'Bundles', data: {
      'Bundle_Id': id,
      'Phone_Number': userNumber,
      'Bundle_Type': type,
      'Bundle_Amount': 0,
      'Amount': amount,
      'Date': date,
    });
  }

  // utilities
  if (body.contains('*162*') &&
      !body.contains('Airtime') &&
      !body.contains('Bundles and Packs')) {
    final name = _firstMatch(RegExp(r'to (.+?) with'), body);
    final amount = _parseAmount(_firstMatch(RegExp(r'payment of (\d+) RWF'), body));
    final date = _firstMatch(_dateRegex, body);
    final fee = _parseAmount(_firstMatch(RegExp(r'Fee was (\d+) RWF'), body));
    final id = _generateIdFromMessage(body, date, 'UTL');

    return ParsedMomoMessage(table: 'Utilities', data: {
      'Transaction_Id': id,
      'Phone_Number': userNumber,
      'Name': name,
      'Amount': amount,
      'Fee': fee,
      'Date': date,
    });
  }

  // other
  String? name;
  int amount = 0;
  final date = _firstMatch(_dateRegex, body);
  if (body.contains('*164')) {
    name = _firstMatch(RegExp(r'by (.*?) on your MOMO', caseSensitive: false), body);
    amount = _parseAmount(
      _firstMatch(RegExp(r'A transaction of (\d+(?:,\d{3})?) RWF', caseSensitive: false), body),
    );
  }

  final id = _generateIdFromMessage(body, date, 'OTR');
  return ParsedMomoMessage(table: 'Others', data: {
    'Other_Id': id,
    'Phone_Number': userNumber,
    'Name': name,
    'Description': body,
    'Amount': amount,
    'Date': date,
  });
}
