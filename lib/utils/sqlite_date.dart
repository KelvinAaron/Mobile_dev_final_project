/// SQLite stores Finmo timestamps as `yyyy-MM-dd HH:mm:ss`.
///
/// Keeping query boundaries in the same text format makes chronological text
/// comparisons reliable and avoids mixing a space with ISO-8601's `T`.
String toSqliteDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
}
