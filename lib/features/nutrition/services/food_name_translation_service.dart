import 'dart:async';

import 'package:flutter/services.dart';

import 'local_food_database_service.dart';
import 'persian_food_parser.dart';

enum TranslationSource {
  cache,
  userOverride,
  exactMapping,
  onDeviceMlKit,
  unavailable,
}

enum TranslationModelStatus {
  unknown,
  notReady,
  downloading,
  ready,
  unavailable,
  downloadFailed,
  translationFailed,
}

class TranslationUiState {
  const TranslationUiState({
    this.status = TranslationModelStatus.unknown,
    this.diagnostic,
    this.translatorInitialized = false,
  }) : assert(
         status != TranslationModelStatus.ready || diagnostic == null,
         'A ready translator cannot retain a failure diagnostic.',
       );

  final TranslationModelStatus status;
  final String? diagnostic;
  final bool translatorInitialized;

  bool get isReady => status == TranslationModelStatus.ready;

  TranslationUiState copyWith({
    TranslationModelStatus? status,
    String? diagnostic,
    bool clearDiagnostic = false,
    bool? translatorInitialized,
  }) {
    final nextStatus = status ?? this.status;
    return TranslationUiState(
      status: nextStatus,
      diagnostic: nextStatus == TranslationModelStatus.ready || clearDiagnostic
          ? null
          : diagnostic ?? this.diagnostic,
      translatorInitialized:
          translatorInitialized ?? this.translatorInitialized,
    );
  }
}

class FoodTranslationResult {
  const FoodTranslationResult({
    required this.originalText,
    required this.translatedText,
    required this.source,
    required this.isAvailable,
    this.warning,
  });

  final String originalText;
  final String translatedText;
  final TranslationSource source;
  final bool isAvailable;
  final String? warning;

  String get normalizedSearchText => normalizeEnglishFoodQuery(translatedText);
}

class FoodTranslationCacheEntry {
  const FoodTranslationCacheEntry({
    required this.persianText,
    required this.englishText,
    required this.source,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final String persianText;
  final String englishText;
  final TranslationSource source;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  FoodTranslationCacheEntry touch(DateTime timestamp) =>
      FoodTranslationCacheEntry(
        persianText: persianText,
        englishText: englishText,
        source: source,
        createdAt: createdAt,
        lastUsedAt: timestamp,
      );

  Map<String, dynamic> toJson() => {
    'persianText': persianText,
    'englishText': englishText,
    'source': source.name,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt.toIso8601String(),
  };

  factory FoodTranslationCacheEntry.fromJson(Map<String, dynamic> json) {
    final createdAt =
        DateTime.tryParse(
          json['createdAt'] is String ? json['createdAt'] as String : '',
        ) ??
        DateTime(1970);
    return FoodTranslationCacheEntry(
      persianText: json['persianText'] is String
          ? json['persianText'] as String
          : '',
      englishText: json['englishText'] is String
          ? json['englishText'] as String
          : '',
      source: TranslationSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => TranslationSource.cache,
      ),
      createdAt: createdAt,
      lastUsedAt:
          DateTime.tryParse(
            json['lastUsedAt'] is String ? json['lastUsedAt'] as String : '',
          ) ??
          createdAt,
    );
  }
}

abstract class FoodTranslationCacheService {
  Future<FoodTranslationCacheEntry?> get(String normalizedPersianText);
  Future<void> put(FoodTranslationCacheEntry entry);
}

class CallbackFoodTranslationCacheService
    implements FoodTranslationCacheService {
  CallbackFoodTranslationCacheService({
    required this.loader,
    required this.saver,
    this.now = DateTime.now,
    this.maxAge = const Duration(days: 180),
  });

  final Future<Map<String, dynamic>> Function() loader;
  final Future<void> Function(Map<String, dynamic>) saver;
  final DateTime Function() now;
  final Duration maxAge;

  @override
  Future<FoodTranslationCacheEntry?> get(String normalizedPersianText) async {
    final cache = await loader();
    final raw = cache[normalizedPersianText];
    if (raw is! Map) return null;
    final entry = FoodTranslationCacheEntry.fromJson(
      Map<String, dynamic>.from(raw),
    );
    if (now().difference(entry.createdAt) > maxAge) {
      cache.remove(normalizedPersianText);
      await saver(cache);
      return null;
    }
    final touched = entry.touch(now());
    cache[normalizedPersianText] = touched.toJson();
    await saver(cache);
    return touched;
  }

  @override
  Future<void> put(FoodTranslationCacheEntry entry) async {
    final cache = await loader();
    cache[entry.persianText] = entry.toJson();
    await saver(cache);
  }
}

class MemoryFoodTranslationCacheService implements FoodTranslationCacheService {
  MemoryFoodTranslationCacheService({
    DateTime Function()? now,
    this.maxAge = const Duration(days: 180),
  }) : now = now ?? DateTime.now;

  final DateTime Function() now;
  final Duration maxAge;
  final Map<String, FoodTranslationCacheEntry> entries = {};

  @override
  Future<FoodTranslationCacheEntry?> get(String normalizedPersianText) async {
    final entry = entries[normalizedPersianText];
    if (entry == null) return null;
    if (now().difference(entry.createdAt) > maxAge) {
      entries.remove(normalizedPersianText);
      return null;
    }
    final touched = entry.touch(now());
    entries[normalizedPersianText] = touched;
    return touched;
  }

  @override
  Future<void> put(FoodTranslationCacheEntry entry) async {
    entries[entry.persianText] = entry;
  }
}

class OnDeviceTranslationAvailability {
  const OnDeviceTranslationAvailability({
    required this.isSupported,
    required this.modelsReady,
  });

  final bool isSupported;
  final bool modelsReady;
}

abstract class OnDeviceFoodNameTranslator {
  Future<OnDeviceTranslationAvailability> availability();
  Future<void> ensureModelsDownloaded();
  Future<String> translate(String persianFoodName);
  Future<void> deleteModels();
}

class MethodChannelFoodNameTranslator implements OnDeviceFoodNameTranslator {
  const MethodChannelFoodNameTranslator({
    this.channel = const MethodChannel('calorie_tracker/on_device_translation'),
  });

  final MethodChannel channel;

  @override
  Future<OnDeviceTranslationAvailability> availability() async {
    try {
      final value = await channel.invokeMethod<Object?>(
        'isTranslationSupported',
      );
      if (value is bool) {
        return OnDeviceTranslationAvailability(
          isSupported: value,
          modelsReady: false,
        );
      }
      if (value is Map) {
        return OnDeviceTranslationAvailability(
          isSupported: value['supported'] == true,
          modelsReady: value['modelsReady'] == true,
        );
      }
      return const OnDeviceTranslationAvailability(
        isSupported: false,
        modelsReady: false,
      );
    } on MissingPluginException {
      return const OnDeviceTranslationAvailability(
        isSupported: false,
        modelsReady: false,
      );
    }
  }

  @override
  Future<void> ensureModelsDownloaded() =>
      channel.invokeMethod<void>('ensureModelsDownloaded');

  @override
  Future<String> translate(String persianFoodName) async =>
      (await channel.invokeMethod<String>('translateFoodName', {
        'foodName': persianFoodName,
      })) ??
      '';

  @override
  Future<void> deleteModels() =>
      channel.invokeMethod<void>('deleteTranslationModels');
}

abstract class FoodNameTranslationService {
  Future<FoodTranslationResult> translateFoodName(String persianFoodName);
  Future<void> saveUserOverride(String persianFoodName, String englishText);
  Future<void> ensureModelsDownloaded();
  Future<OnDeviceTranslationAvailability> availability();
}

class CachedFoodNameTranslationService implements FoodNameTranslationService {
  CachedFoodNameTranslationService({
    required this.cache,
    required this.onDeviceTranslator,
    this.dictionary = const PersianFoodSearchDictionary(),
    this.onStatusChanged,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final FoodTranslationCacheService cache;
  final OnDeviceFoodNameTranslator onDeviceTranslator;
  final PersianFoodSearchDictionary dictionary;
  final void Function(TranslationModelStatus status)? onStatusChanged;
  final DateTime Function() now;
  final Map<String, Future<FoodTranslationResult>> _inFlight = {};
  Future<void>? _modelDownloadInFlight;

  @override
  Future<FoodTranslationResult> translateFoodName(String persianFoodName) {
    final normalized = normalizePersianFoodForTranslation(persianFoodName);
    return _inFlight.putIfAbsent(normalized, () async {
      try {
        return await _translate(normalized);
      } finally {
        _inFlight.remove(normalized);
      }
    });
  }

  Future<FoodTranslationResult> _translate(String normalized) async {
    final cached = await cache.get(normalized);
    if (cached != null && _isValidTranslation(normalized, cached.englishText)) {
      return FoodTranslationResult(
        originalText: normalized,
        translatedText: cached.englishText,
        source: cached.source == TranslationSource.userOverride
            ? TranslationSource.userOverride
            : TranslationSource.cache,
        isAvailable: true,
      );
    }

    final mapped = dictionary.searchPhrase(normalized);
    if (mapped != null && _isValidTranslation(normalized, mapped)) {
      return FoodTranslationResult(
        originalText: normalized,
        translatedText: _cleanEnglishTranslation(mapped),
        source: TranslationSource.exactMapping,
        isAvailable: true,
      );
    }

    late final OnDeviceTranslationAvailability status;
    try {
      status = await availability();
    } on PlatformException {
      onStatusChanged?.call(TranslationModelStatus.unavailable);
      return _unavailable(normalized, 'مترجم آفلاین در دسترس نیست.');
    }
    if (!status.isSupported) {
      onStatusChanged?.call(TranslationModelStatus.unavailable);
      return _unavailable(normalized, 'مترجم آفلاین در دسترس نیست.');
    }

    if (!status.modelsReady) {
      onStatusChanged?.call(TranslationModelStatus.downloading);
      try {
        await ensureModelsDownloaded();
      } on PlatformException {
        onStatusChanged?.call(TranslationModelStatus.downloadFailed);
        return _unavailable(
          normalized,
          'مدل ترجمه دانلود نشد. اتصال اینترنت را بررسی و دوباره تلاش کنید.',
        );
      }
    }

    try {
      final translated = _cleanEnglishTranslation(
        await onDeviceTranslator.translate(normalized),
      );
      if (!_isValidTranslation(normalized, translated)) {
        onStatusChanged?.call(TranslationModelStatus.translationFailed);
        return _unavailable(normalized, 'ترجمه نام خوراکی انجام نشد.');
      }
      final timestamp = now();
      await cache.put(
        FoodTranslationCacheEntry(
          persianText: normalized,
          englishText: translated,
          source: TranslationSource.onDeviceMlKit,
          createdAt: timestamp,
          lastUsedAt: timestamp,
        ),
      );
      onStatusChanged?.call(TranslationModelStatus.ready);
      return FoodTranslationResult(
        originalText: normalized,
        translatedText: translated,
        source: TranslationSource.onDeviceMlKit,
        isAvailable: true,
      );
    } on PlatformException {
      onStatusChanged?.call(TranslationModelStatus.translationFailed);
      return _unavailable(
        normalized,
        'ترجمه نام خوراکی انجام نشد. دوباره تلاش کنید یا عبارت را اصلاح کنید.',
      );
    }
  }

  @override
  Future<void> saveUserOverride(
    String persianFoodName,
    String englishText,
  ) async {
    final persian = normalizePersianFoodForTranslation(persianFoodName);
    final english = _cleanEnglishTranslation(englishText);
    if (!_isValidTranslation(persian, english)) {
      throw const FormatException('Invalid food translation override.');
    }
    final timestamp = now();
    await cache.put(
      FoodTranslationCacheEntry(
        persianText: persian,
        englishText: english,
        source: TranslationSource.userOverride,
        createdAt: timestamp,
        lastUsedAt: timestamp,
      ),
    );
  }

  @override
  Future<OnDeviceTranslationAvailability> availability() =>
      onDeviceTranslator.availability();

  @override
  Future<void> ensureModelsDownloaded() {
    final existing = _modelDownloadInFlight;
    if (existing != null) return existing;

    final download = _downloadModels();
    _modelDownloadInFlight = download;
    download.then<void>(
      (_) => _clearModelDownload(download),
      onError: (_, _) => _clearModelDownload(download),
    );
    return download;
  }

  Future<void> _downloadModels() async {
    onStatusChanged?.call(TranslationModelStatus.downloading);
    try {
      await onDeviceTranslator.ensureModelsDownloaded();
      onStatusChanged?.call(TranslationModelStatus.ready);
    } on MissingPluginException {
      onStatusChanged?.call(TranslationModelStatus.unavailable);
      throw PlatformException(
        code: 'UNSUPPORTED_LANGUAGE',
        message: 'UNSUPPORTED_LANGUAGE: MissingPluginException',
      );
    } on PlatformException catch (error) {
      onStatusChanged?.call(
        error.code == 'UNSUPPORTED_LANGUAGE'
            ? TranslationModelStatus.unavailable
            : TranslationModelStatus.downloadFailed,
      );
      rethrow;
    }
  }

  void _clearModelDownload(Future<void> download) {
    if (identical(_modelDownloadInFlight, download)) {
      _modelDownloadInFlight = null;
    }
  }

  FoodTranslationResult _unavailable(String original, String warning) =>
      FoodTranslationResult(
        originalText: original,
        translatedText: '',
        source: TranslationSource.unavailable,
        isAvailable: false,
        warning: warning,
      );
}

String normalizePersianFoodForTranslation(String value) {
  var normalized = normalizeFoodName(value);
  normalized = normalized.replaceFirst(
    RegExp(
      r'^(?:\d+(?:\.\d+)?|نیم|یک چهارم|سه چهارم|یک|دو|سه|چهار|پنج)\s*'
      r'(?:گرم|کیلوگرم|کیلو گرم|عدد|دانه|لیوان|پیمانه|قاشق غذاخوری|'
      r'قاشق چای خوری|کف دست|برش|کاسه|بشقاب)?\s*',
    ),
    '',
  );
  return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String normalizeEnglishFoodQuery(String value) =>
    _cleanEnglishTranslation(value).toLowerCase();

String _cleanEnglishTranslation(String value) => value
    .trim()
    .replaceAll(RegExp(r'''^["'“”]+|["'“”]+$'''), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _isValidTranslation(String original, String translated) {
  if (translated.isEmpty || translated.length > 150) return false;
  if (normalizePersianFoodForTranslation(original) ==
      normalizePersianFoodForTranslation(translated)) {
    return false;
  }
  if (RegExp(r'https?://|www\.').hasMatch(translated.toLowerCase())) {
    return false;
  }
  final letters = RegExp(r'[A-Za-z]').allMatches(translated).length;
  final persian = RegExp(r'[\u0600-\u06FF]').allMatches(translated).length;
  if (letters == 0 || persian > letters) return false;
  return true;
}
