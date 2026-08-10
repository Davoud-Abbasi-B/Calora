import 'package:calorie_tracker/features/nutrition/services/food_name_translation_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached translation skips ML Kit and updates last use', () async {
    final now = DateTime(2026, 8, 2);
    final cache = MemoryFoodTranslationCacheService(now: () => now);
    await cache.put(
      FoodTranslationCacheEntry(
        persianText: 'چیپس سیب زمینی',
        englishText: 'potato chips',
        source: TranslationSource.onDeviceMlKit,
        createdAt: now.subtract(const Duration(days: 2)),
        lastUsedAt: now.subtract(const Duration(days: 1)),
      ),
    );
    final device = _Translator('wrong');
    final service = CachedFoodNameTranslationService(
      cache: cache,
      onDeviceTranslator: device,
      now: () => now,
    );

    final result = await service.translateFoodName('چیپس سیب زمینی');

    expect(result.translatedText, 'potato chips');
    expect(result.source, TranslationSource.cache);
    expect(device.translateCalls, 0);
    expect(cache.entries['چیپس سیب زمینی']?.lastUsedAt, now);
  });

  test('user correction has priority over on-device translation', () async {
    final device = _Translator('machine phrase');
    final service = CachedFoodNameTranslationService(
      cache: MemoryFoodTranslationCacheService(),
      onDeviceTranslator: device,
    );
    await service.saveUserOverride('چیپس سیب زمینی', 'potato crisps');

    final result = await service.translateFoodName('چیپس سیب زمینی');

    expect(result.translatedText, 'potato crisps');
    expect(result.source, TranslationSource.userOverride);
    expect(device.translateCalls, 0);
  });

  test('duplicate requests share download and translation work', () async {
    final device = _Translator(
      'potato chips',
      delay: const Duration(milliseconds: 10),
    );
    final service = CachedFoodNameTranslationService(
      cache: MemoryFoodTranslationCacheService(),
      onDeviceTranslator: device,
    );

    await Future.wait([
      service.translateFoodName('چیپس سیب زمینی'),
      service.translateFoodName('چیپس سیب زمینی'),
    ]);

    expect(device.downloadCalls, 1);
    expect(device.translateCalls, 1);
  });

  test('service stays lazy until a translation is requested', () async {
    final device = _TrackingTranslator();
    CachedFoodNameTranslationService(
      cache: MemoryFoodTranslationCacheService(),
      onDeviceTranslator: device,
    );

    await Future<void>.delayed(Duration.zero);

    expect(device.events, isEmpty);
  });

  test('translation starts only after model download succeeds', () async {
    final device = _TrackingTranslator();
    final service = CachedFoodNameTranslationService(
      cache: MemoryFoodTranslationCacheService(),
      onDeviceTranslator: device,
    );

    final result = await service.translateFoodName('خوراک آزمایشی ویژه');

    expect(result.translatedText, 'test food');
    expect(device.events, [
      'availability',
      'download:start',
      'download:success',
      'translate',
    ]);
  });

  test(
    'different concurrent requests share the active model download',
    () async {
      final device = _Translator(
        'test food',
        delay: const Duration(milliseconds: 10),
      );
      final service = CachedFoodNameTranslationService(
        cache: MemoryFoodTranslationCacheService(),
        onDeviceTranslator: device,
      );

      await Future.wait([
        service.translateFoodName('خوراک آزمایشی اول'),
        service.translateFoodName('خوراک آزمایشی دوم'),
      ]);

      expect(device.downloadCalls, 1);
      expect(device.translateCalls, 2);
    },
  );

  test(
    'platform diagnostics are not exposed in translation warnings',
    () async {
      final service = CachedFoodNameTranslationService(
        cache: MemoryFoodTranslationCacheService(),
        onDeviceTranslator: _FailingTranslator(),
      );

      final result = await service.translateFoodName('خوراک ناشناخته');

      expect(result.isAvailable, isFalse);
      expect(result.warning, isNot(contains('MODEL_DOWNLOAD_FAILED')));
      expect(result.warning, isNot(contains('PlatformException')));
      expect(result.warning, contains('دوباره تلاش کنید'));
    },
  );

  test('model download can be retried after a synchronous failure', () async {
    final device = _RetryTranslator();
    final service = CachedFoodNameTranslationService(
      cache: MemoryFoodTranslationCacheService(),
      onDeviceTranslator: device,
    );

    final first = await service.translateFoodName('خوراک ناشناخته');
    final second = await service.translateFoodName('خوراک ناشناخته');

    expect(first.isAvailable, isFalse);
    expect(second.translatedText, 'unknown food');
    expect(device.downloadCalls, 2);
  });
}

class _FailingTranslator implements OnDeviceFoodNameTranslator {
  @override
  Future<OnDeviceTranslationAvailability> availability() async =>
      const OnDeviceTranslationAvailability(
        isSupported: true,
        modelsReady: false,
      );

  @override
  Future<void> ensureModelsDownloaded() => throw PlatformException(
    code: 'MODEL_DOWNLOAD_FAILED',
    message: 'MODEL_DOWNLOAD_FAILED: MlKitException',
  );

  @override
  Future<String> translate(String persianFoodName) async => '';

  @override
  Future<void> deleteModels() async {}
}

class _RetryTranslator implements OnDeviceFoodNameTranslator {
  var ready = false;
  var downloadCalls = 0;

  @override
  Future<OnDeviceTranslationAvailability> availability() async =>
      OnDeviceTranslationAvailability(isSupported: true, modelsReady: ready);

  @override
  Future<void> ensureModelsDownloaded() {
    downloadCalls++;
    if (downloadCalls == 1) {
      throw PlatformException(code: 'MODEL_DOWNLOAD_FAILED');
    }
    ready = true;
    return Future<void>.value();
  }

  @override
  Future<String> translate(String persianFoodName) async => 'unknown food';

  @override
  Future<void> deleteModels() async {}
}

class _Translator implements OnDeviceFoodNameTranslator {
  _Translator(this.output, {this.delay = Duration.zero});
  final String output;
  final Duration delay;
  bool ready = false;
  int downloadCalls = 0;
  int translateCalls = 0;

  @override
  Future<OnDeviceTranslationAvailability> availability() async =>
      OnDeviceTranslationAvailability(isSupported: true, modelsReady: ready);

  @override
  Future<void> ensureModelsDownloaded() async {
    downloadCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    ready = true;
  }

  @override
  Future<String> translate(String persianFoodName) async {
    translateCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return output;
  }

  @override
  Future<void> deleteModels() async => ready = false;
}

class _TrackingTranslator implements OnDeviceFoodNameTranslator {
  final events = <String>[];
  var ready = false;

  @override
  Future<OnDeviceTranslationAvailability> availability() async {
    events.add('availability');
    return OnDeviceTranslationAvailability(
      isSupported: true,
      modelsReady: ready,
    );
  }

  @override
  Future<void> ensureModelsDownloaded() async {
    events.add('download:start');
    await Future<void>.delayed(Duration.zero);
    ready = true;
    events.add('download:success');
  }

  @override
  Future<String> translate(String persianFoodName) async {
    events.add('translate');
    return 'test food';
  }

  @override
  Future<void> deleteModels() async => ready = false;
}
