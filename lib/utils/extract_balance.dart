// extracts balance from M-Money SMS message body
int? extractBalance(String messageBody) {
  final normalized = messageBody
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  final patterns = [
    // Prefer the transaction's resulting balance when a message contains
    // another balance value earlier in its text.
    RegExp(
      r'your\s+new\s+balance'
      r'(?:\s+is)?\s*[:=\-]?\s*(?:RWF\s*)?'
      r'([\d][\d\s,.]*)\s*(?:RWF)?',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:new|available|current|remaining)\s+balance'
      r'(?:\s+is)?\s*[:=\-]?\s*(?:RWF\s*)?'
      r'([\d][\d\s,.]*)\s*(?:RWF)?',
      caseSensitive: false,
    ),
    // Examples:
    // "Your new balance: 21,705 RWF"
    // "Your balance is RWF 21,705"
    // "Available balance - 21705.00 RWF"
    RegExp(
      r'balance'
      r'(?:\s+is)?\s*[:=\-]?\s*(?:RWF\s*)?'
      r'([\d][\d\s,.]*)\s*(?:RWF)?',
      caseSensitive: false,
    ),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(normalized);
    final raw = match?.group(1);
    if (raw != null) {
      final balance = _parseLocalizedNumber(raw);
      if (balance != null && balance >= 0) return balance.round();
    }
  }

  return null;
}

double? _parseLocalizedNumber(String raw) {
  var value = raw.replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;

  final lastComma = value.lastIndexOf(',');
  final lastDot = value.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    final decimalSeparator = lastComma > lastDot ? ',' : '.';
    final decimalIndex = value.lastIndexOf(decimalSeparator);
    final digitsAfter = value.length - decimalIndex - 1;
    if (digitsAfter <= 2) {
      final integerPart = value.substring(0, decimalIndex).replaceAll(RegExp(r'[,.]'), '');
      final decimalPart = value.substring(decimalIndex + 1);
      value = '$integerPart.$decimalPart';
    } else {
      value = value.replaceAll(RegExp(r'[,.]'), '');
    }
  } else {
    final separator = lastComma >= 0 ? ',' : (lastDot >= 0 ? '.' : null);
    if (separator != null) {
      final groups = value.split(separator);
      final isThousandsGrouping =
          groups.length > 1 && groups.skip(1).every((group) => group.length == 3);
      if (isThousandsGrouping) {
        value = groups.join();
      } else if (groups.length == 2 && groups.last.length <= 2) {
        value = '${groups.first}.${groups.last}';
      } else {
        value = groups.join();
      }
    }
  }

  return double.tryParse(value);
}

int? latestSmsBalance(
  Iterable<({String body, int? timestamp})> messages,
) {
  int? latestBalance;
  int? latestTimestamp;

  for (final message in messages) {
    final balance = extractBalance(message.body);
    if (balance == null) continue;

    final timestamp = message.timestamp;
    if (latestBalance == null ||
        (timestamp != null &&
            (latestTimestamp == null || timestamp > latestTimestamp))) {
      latestBalance = balance;
      latestTimestamp = timestamp;
    }
  }

  return latestBalance;
}
