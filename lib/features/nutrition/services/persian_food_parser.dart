enum FoodUnit {
  gram('گرم'),
  kilogram('کیلوگرم'),
  item('عدد'),
  glass('لیوان'),
  cup('پیمانه'),
  tablespoon('قاشق غذاخوری'),
  teaspoon('قاشق چای‌خوری'),
  palm('کف دست'),
  slice('برش'),
  bowl('کاسه'),
  plate('بشقاب'),
  unsupported('');

  const FoodUnit(this.label);
  final String label;
}

class ParsedFoodInput {
  const ParsedFoodInput({
    required this.originalSegment,
    required this.normalizedFoodName,
    required this.quantity,
    required this.unit,
    required this.quantityText,
  });

  final String originalSegment;
  final String normalizedFoodName;
  final double? quantity;
  final FoodUnit? unit;
  final String quantityText;

  bool get isQuantityAmbiguous => quantity == null;
  bool get hasUnsupportedUnit => unit == FoodUnit.unsupported;
}

class PersianFoodParser {
  const PersianFoodParser();

  List<ParsedFoodInput> parse(String input) {
    final normalized = normalizePersianText(input)
        .replaceAll(RegExp(r'\s*(?:،|,|\+)\s*'), '|')
        .replaceAll(RegExp(r'\s+(?:به همراه|همراه)\s+'), '|')
        .replaceAll(
          RegExp(r'\s+با\s+(?=(?:نیم|یک چهارم|سه چهارم|یک|دو|سه|چهار|پنج|\d))'),
          '|',
        )
        .replaceAll(RegExp(r'\s+و\s+'), '|');

    return normalized
        .split('|')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .map(_parseSegment)
        .toList(growable: false);
  }

  ParsedFoodInput _parseSegment(String segment) {
    final quantityMatch = RegExp(
      r'^(نیم|یک چهارم|سه چهارم|یک|دو|سه|چهار|پنج|\d+(?:\.\d+)?)\s*',
    ).firstMatch(segment);
    if (quantityMatch == null) {
      return ParsedFoodInput(
        originalSegment: segment,
        normalizedFoodName: normalizeFoodName(segment),
        quantity: null,
        unit: null,
        quantityText: 'مقدار نامشخص',
      );
    }

    final rawQuantity = quantityMatch.group(1)!;
    final quantity = _quantityValue(rawQuantity);
    var remainder = segment.substring(quantityMatch.end).trim();
    final matchedUnit = _matchUnit(remainder);
    FoodUnit unit;
    if (matchedUnit != null) {
      unit = matchedUnit.$1;
      remainder = remainder.substring(matchedUnit.$2).trim();
    } else {
      final firstWord = remainder.split(' ').firstOrNull ?? '';
      final looksLikeFoodDirectly = _commonFoodPrefixes.any(
        (prefix) => remainder.startsWith(prefix),
      );
      if (looksLikeFoodDirectly) {
        unit = FoodUnit.item;
      } else if (firstWord.isNotEmpty) {
        unit = FoodUnit.unsupported;
        remainder = remainder.substring(firstWord.length).trim();
      } else {
        unit = FoodUnit.unsupported;
      }
    }

    final quantityDisplay = _persianNumber(rawQuantity);
    return ParsedFoodInput(
      originalSegment: segment,
      normalizedFoodName: normalizeFoodName(remainder),
      quantity: quantity,
      unit: unit,
      quantityText: unit == FoodUnit.unsupported
          ? '$quantityDisplay واحد نامشخص'
          : '$quantityDisplay ${unit.label}',
    );
  }

  (FoodUnit, int)? _matchUnit(String value) {
    const aliases = <String, FoodUnit>{
      'قاشق غذا خوری': FoodUnit.tablespoon,
      'قاشق غذاخوری': FoodUnit.tablespoon,
      'قاشق چای خوری': FoodUnit.teaspoon,
      'قاشق چایخوری': FoodUnit.teaspoon,
      'قاشق چای‌خوری': FoodUnit.teaspoon,
      'کیلو گرم': FoodUnit.kilogram,
      'کیلوگرم': FoodUnit.kilogram,
      'میلی لیتر': FoodUnit.unsupported,
      'کف دست': FoodUnit.palm,
      'پیمانه': FoodUnit.cup,
      'لیوان': FoodUnit.glass,
      'بشقاب': FoodUnit.plate,
      'کاسه': FoodUnit.bowl,
      'برش': FoodUnit.slice,
      'عدد': FoodUnit.item,
      'دانه': FoodUnit.item,
      'گرم': FoodUnit.gram,
    };
    final entries = aliases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      if (value.startsWith(entry.key)) return (entry.value, entry.key.length);
    }
    return null;
  }
}

String normalizePersianText(String value) {
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var output = value
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('ۀ', 'ه')
      .replaceAll('\u200c', ' ')
      .replaceAll('٫', '.')
      .replaceAll('٬', '')
      .replaceAll('،', ' ، ');
  for (var index = 0; index < 10; index++) {
    output = output
        .replaceAll(persianDigits[index], '$index')
        .replaceAll(arabicDigits[index], '$index');
  }
  output = output
      .replaceAll('یک‌چهارم', 'یک چهارم')
      .replaceAll('سه‌چهارم', 'سه چهارم');
  return output.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String normalizeFoodName(String value) => normalizePersianText(value)
    .replaceAll(RegExp(r'^(از|حدود)\s+'), '')
    .replaceAll(RegExp(r'\s+(پخته شده)$'), ' پخته')
    .trim()
    .toLowerCase();

double _quantityValue(String value) => switch (value) {
  'نیم' => 0.5,
  'یک چهارم' => 0.25,
  'سه چهارم' => 0.75,
  'یک' => 1,
  'دو' => 2,
  'سه' => 3,
  'چهار' => 4,
  'پنج' => 5,
  _ => double.parse(value),
};

String _persianNumber(String value) {
  const words = {
    'نیم': 'نیم',
    'یک چهارم': 'یک‌چهارم',
    'سه چهارم': 'سه‌چهارم',
    'یک': 'یک',
    'دو': 'دو',
    'سه': 'سه',
    'چهار': 'چهار',
    'پنج': 'پنج',
  };
  if (words.containsKey(value)) return words[value]!;
  const english = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var output = value;
  for (var index = 0; index < 10; index++) {
    output = output.replaceAll(english[index], persian[index]);
  }
  return output;
}

const _commonFoodPrefixes = [
  'تخم مرغ',
  'تخم‌مرغ',
  'موز',
  'سیب',
  'پرتقال',
  'خرما',
  'نان',
];
