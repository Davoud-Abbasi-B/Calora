String persianNumber(num value) {
  final text = value is double && value != value.roundToDouble()
      ? value.toStringAsFixed(1)
      : value.round().toString();
  return persianDigits(text);
}

String persianDigits(String value) {
  const western = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return value.split('').map((character) {
    final index = western.indexOf(character);
    return index < 0 ? character : persian[index];
  }).join();
}

String westernDigits(String value) {
  const localized = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  const western = '01234567890123456789';
  return value.split('').map((character) {
    final index = localized.indexOf(character);
    return index < 0 ? character : western[index];
  }).join();
}
