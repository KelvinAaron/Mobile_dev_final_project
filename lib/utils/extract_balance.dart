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
      r'([\d,]+(?:\.\d+)?)\s*(?:RWF)?',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:new|available|current|remaining)\s+balance'
      r'(?:\s+is)?\s*[:=\-]?\s*(?:RWF\s*)?'
      r'([\d,]+(?:\.\d+)?)\s*(?:RWF)?',
      caseSensitive: false,
    ),
    // Examples:
    // "Your new balance: 21,705 RWF"
    // "Your balance is RWF 21,705"
    // "Available balance - 21705.00 RWF"
    RegExp(
      r'balance'
      r'(?:\s+is)?\s*[:=\-]?\s*(?:RWF\s*)?'
      r'([\d,]+(?:\.\d+)?)\s*(?:RWF)?',
      caseSensitive: false,
    ),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(normalized);
    final raw = match?.group(1);
    if (raw != null) {
      final balance = double.tryParse(raw.replaceAll(',', ''));
      if (balance != null && balance >= 0) return balance.round();
    }
  }

  return null;
}
