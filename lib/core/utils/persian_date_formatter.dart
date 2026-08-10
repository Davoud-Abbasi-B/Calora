import 'package:shamsi_date/shamsi_date.dart';

import 'persian_format.dart';

String jalaliNumericDate(DateTime date) {
  final formatter = Jalali.fromDateTime(date).formatter;
  return '${formatter.yyyy}/${formatter.mm}/${formatter.dd}';
}

String formatFullDate(DateTime date) {
  final formatter = Jalali.fromDateTime(date).formatter;
  return persianDigits(
    '${_normalizedWeekday(formatter.wN)} ${formatter.d} '
    '${formatter.mN} ${formatter.yyyy}',
  );
}

String formatDateKey(String dateKey) => formatFullDate(dateFromKey(dateKey));

DateTime dateFromKey(String key) => DateTime.tryParse(key) ?? DateTime(1970);

String _normalizedWeekday(String value) => switch (value) {
  'یک شنبه' => 'یکشنبه',
  'دو شنبه' => 'دوشنبه',
  'سه شنبه' => 'سه‌شنبه',
  'چهار شنبه' => 'چهارشنبه',
  'پنج شنبه' => 'پنجشنبه',
  _ => value,
};
