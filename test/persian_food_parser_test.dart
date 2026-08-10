import 'package:calorie_tracker/features/nutrition/services/persian_food_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = PersianFoodParser();

  test('parses Persian foods, digits, separators, and units', () {
    final foods = parser.parse('۱۰ گرم پنیر لیقوان و ۵۰ گرم نان بربری');
    expect(foods, hasLength(2));
    expect(foods.first.quantity, 10);
    expect(foods.first.unit, FoodUnit.gram);
    expect(foods.last.normalizedFoodName, 'نان بربری');
    expect(parser.parse('١٫٥ کیلوگرم سینه مرغ').single.quantity, 1.5);
    expect(parser.parse('نیم لیوان شیر').single.quantity, 0.5);
  });

  test('does not invent a quantity', () {
    expect(parser.parse('نان بربری').single.isQuantityAmbiguous, isTrue);
  });

  test('normalizes spacing, half-space, and Arabic letter variants', () {
    final variants = [
      'نان جو',
      'نان‌جو',
      'نان  جو',
      'نان جو'.replaceAll('ی', 'ي'),
    ];
    for (final value in variants) {
      expect(parser.parse(value).single.normalizedFoodName, 'نان جو');
    }
    expect(parser.parse('۱۰۰ گرم كلم').single.normalizedFoodName, 'کلم');
  });

  test('parses representative single and multiple food inputs', () {
    expect(parser.parse('۲ عدد تخم مرغ').single.quantity, 2);
    expect(parser.parse('100 گرم برنج').single.unit, FoodUnit.gram);
    expect(parser.parse('یک موز').single.unit, FoodUnit.item);
    expect(parser.parse('۲ عدد تخم مرغ و ۱۰۰ گرم نان'), hasLength(2));
    expect(parser.parse('یک موز + یک لیوان شیر'), hasLength(2));
  });

  test('keeps food name intact when milliliter is unsupported', () {
    final parsed = parser.parse('۲۵۰ میلی‌لیتر شیر').single;
    expect(parsed.unit, FoodUnit.unsupported);
    expect(parsed.normalizedFoodName, 'شیر');
    expect(parsed.hasUnsupportedUnit, isTrue);
  });
}
