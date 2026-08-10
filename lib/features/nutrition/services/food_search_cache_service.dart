import '../models/food_analysis_result.dart';
import 'persian_food_parser.dart';

class FoodSearchCacheEntry {
  const FoodSearchCacheEntry({
    required this.query,
    required this.candidates,
    required this.timestamp,
    this.selectedCandidate,
  });

  final String query;
  final List<FoodAnalysisCandidate> candidates;
  final FoodAnalysisCandidate? selectedCandidate;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'query': query,
    'candidates': candidates.map((item) => item.toJson()).toList(),
    'selectedCandidate': selectedCandidate?.toJson(),
    'timestamp': timestamp.toIso8601String(),
  };

  factory FoodSearchCacheEntry.fromJson(Map<String, dynamic> json) {
    final selected = json['selectedCandidate'];
    return FoodSearchCacheEntry(
      query: json['query'] is String ? json['query'] as String : '',
      candidates:
          (json['candidates'] is List
                  ? json['candidates'] as List
                  : const <dynamic>[])
              .whereType<Map>()
              .map(
                (item) => FoodAnalysisCandidate.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false),
      selectedCandidate: selected is Map
          ? FoodAnalysisCandidate.fromJson(Map<String, dynamic>.from(selected))
          : null,
      timestamp:
          DateTime.tryParse(
            json['timestamp'] is String ? json['timestamp'] as String : '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract interface class FoodSearchCacheService {
  Future<FoodSearchCacheEntry?> get(String query);
  Future<void> put(FoodSearchCacheEntry entry);
  Future<void> select(String query, FoodAnalysisCandidate candidate);
  Future<void> clear();
}

class CallbackFoodSearchCacheService implements FoodSearchCacheService {
  const CallbackFoodSearchCacheService({
    required this.loader,
    required this.saver,
    required this.clearer,
    this.maxAge = const Duration(days: 30),
    this.now = DateTime.now,
  });

  final Future<Map<String, dynamic>> Function() loader;
  final Future<void> Function(Map<String, dynamic>) saver;
  final Future<void> Function() clearer;
  final Duration maxAge;
  final DateTime Function() now;

  String _key(String query) => normalizePersianText(query).toLowerCase();

  @override
  Future<FoodSearchCacheEntry?> get(String query) async {
    final map = await loader();
    final raw = map[_key(query)];
    if (raw is! Map) return null;
    final entry = FoodSearchCacheEntry.fromJson(Map<String, dynamic>.from(raw));
    if (now().difference(entry.timestamp) > maxAge) return null;
    return entry;
  }

  @override
  Future<void> put(FoodSearchCacheEntry entry) async {
    final map = await loader();
    map[_key(entry.query)] = entry.toJson();
    await saver(map);
  }

  @override
  Future<void> select(String query, FoodAnalysisCandidate candidate) async {
    final existing = await get(query);
    await put(
      FoodSearchCacheEntry(
        query: query,
        candidates: existing?.candidates ?? [candidate],
        selectedCandidate: candidate,
        timestamp: now(),
      ),
    );
  }

  @override
  Future<void> clear() => clearer();
}

class MemoryFoodSearchCacheService implements FoodSearchCacheService {
  MemoryFoodSearchCacheService({
    this.maxAge = const Duration(days: 30),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final Duration maxAge;
  final DateTime Function() now;
  final Map<String, FoodSearchCacheEntry> _entries = {};
  String _key(String query) => query.trim().toLowerCase();

  @override
  Future<FoodSearchCacheEntry?> get(String query) async {
    final entry = _entries[_key(query)];
    if (entry == null || now().difference(entry.timestamp) > maxAge) {
      return null;
    }
    return entry;
  }

  @override
  Future<void> put(FoodSearchCacheEntry entry) async {
    _entries[_key(entry.query)] = entry;
  }

  @override
  Future<void> select(String query, FoodAnalysisCandidate candidate) async {
    final entry = _entries[_key(query)];
    _entries[_key(query)] = FoodSearchCacheEntry(
      query: query,
      candidates: entry?.candidates ?? [candidate],
      selectedCandidate: candidate,
      timestamp: now(),
    );
  }

  @override
  Future<void> clear() async => _entries.clear();
}
