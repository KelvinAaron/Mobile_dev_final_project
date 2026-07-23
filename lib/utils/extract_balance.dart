// extracts balance from M-Money SMS message body
int? extractBalance(String messageBody) {
  final patterns = [
    RegExp(r'Your new balance[:\s]+([\d,]+)\s*RWF', caseSensitive: false),
    RegExp(r'new balance[:\s]+([\d,]+)\s*RWF', caseSensitive: false),
    RegExp(r'Balance[:\s]+([\d,]+)\s*RWF', caseSensitive: false),
    RegExp(r'balance[:\s]+([\d,]+)\s*RWF', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(messageBody);
    final raw = match?.group(1);
    if (raw != null) {
      final balance = int.tryParse(raw.replaceAll(',', ''));
      if (balance != null && balance >= 0) return balance;
    }
  }

  return null;
}
