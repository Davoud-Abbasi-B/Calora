import 'package:calorie_tracker/core/utils/date_key.dart';
import 'package:calorie_tracker/core/utils/persian_date_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gregorianKey = '2026-08-10';
  final gregorianDate = DateTime(2026, 8, 10);

  test('converts the deterministic Gregorian date to Jalali', () {
    expect(jalaliNumericDate(gregorianDate), '1405/05/19');
  });

  test('formats full Jalali date with Persian weekday and digits', () {
    final formatted = formatFullDate(gregorianDate);

    expect(formatted, contains('دوشنبه'));
    expect(formatted, contains('۱۹'));
    expect(formatted, contains('مرداد'));
    expect(formatted, contains('۱۴۰۵'));
    expect(formatted, isNot(contains(RegExp(r'[0-9]'))));
  });

  test('history formatter reads but does not mutate Gregorian date keys', () {
    expect(formatDateKey(gregorianKey), formatFullDate(gregorianDate));
    expect(dateKey(gregorianDate), gregorianKey);
  });

  test('handles Jalali month, year, and leap-day boundaries', () {
    expect(jalaliNumericDate(DateTime(2026, 7, 22)), '1405/04/31');
    expect(jalaliNumericDate(DateTime(2026, 7, 23)), '1405/05/01');
    expect(jalaliNumericDate(DateTime(2025, 3, 20)), '1403/12/30');
    expect(jalaliNumericDate(DateTime(2025, 3, 21)), '1404/01/01');
  });
}
