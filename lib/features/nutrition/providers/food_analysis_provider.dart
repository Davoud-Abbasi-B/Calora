import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_analysis_result.dart';
import '../services/food_analysis_service.dart';
import '../services/hybrid_food_analysis_service.dart';
import 'nutrition_providers.dart';

class FoodAnalysisState {
  const FoodAnalysisState({this.batch, this.isLoading = false, this.message});
  final FoodAnalysisBatchResult? batch;
  final bool isLoading;
  final String? message;

  FoodAnalysisState copyWith({
    FoodAnalysisBatchResult? batch,
    bool clearBatch = false,
    bool? isLoading,
    String? message,
    bool clearMessage = false,
  }) => FoodAnalysisState(
    batch: clearBatch ? null : batch ?? this.batch,
    isLoading: isLoading ?? this.isLoading,
    message: clearMessage ? null : message ?? this.message,
  );
}

class FoodAnalysisNotifier extends StateNotifier<FoodAnalysisState> {
  FoodAnalysisNotifier(this.service) : super(const FoodAnalysisState());
  final HybridFoodAnalysisService service;

  Future<void> analyze(String input) async {
    if (state.isLoading) return;
    if (input.trim().isEmpty) {
      state = const FoodAnalysisState(
        message: 'لطفاً خوراکی و مقدار آن را وارد کنید.',
      );
      return;
    }
    state = const FoodAnalysisState(isLoading: true);
    try {
      final batch = await service.analyze(input.trim());
      state = FoodAnalysisState(
        batch: batch,
        message: batch.needsUserAction
            ? 'برای موارد حل‌نشده، یکی از گزینه‌های زیر را انتخاب کنید.'
            : null,
      );
    } catch (error) {
      state = FoodAnalysisState(message: foodAnalysisErrorMessage(error));
    }
  }

  Future<void> resolveCandidate(
    UnresolvedFoodItem item,
    FoodAnalysisCandidate candidate,
  ) async {
    final result = await service.resolveCandidate(item, candidate);
    if (result != null) replace(item, [result]);
  }

  Future<void> resolvePortion(UnresolvedFoodItem item, double grams) async {
    final result = await service.resolveLocalPortion(item, grams);
    if (result != null) replace(item, [result]);
  }

  Future<void> retryWithTranslation(
    UnresolvedFoodItem item,
    String phrase, {
    required bool saveForLater,
  }) async {
    state = state.copyWith(isLoading: true, clearMessage: true);
    try {
      final result = await service.analyzeWithUserTranslation(
        item,
        phrase,
        saveForLater: saveForLater,
      );
      replace(item, result.items, unresolved: result.unresolvedItems);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        message: foodAnalysisErrorMessage(error),
      );
    }
  }

  void replace(
    UnresolvedFoodItem item,
    List<FoodAnalysisResult> items, {
    List<UnresolvedFoodItem> unresolved = const [],
  }) {
    final batch = state.batch;
    if (batch == null) return;
    final next = FoodAnalysisBatchResult(
      originalInput: batch.originalInput,
      items: [...batch.items, ...items],
      warnings: batch.warnings,
      unresolvedItems: [
        ...batch.unresolvedItems.where((value) => !identical(value, item)),
        ...unresolved,
      ],
    );
    state = FoodAnalysisState(
      batch: next,
      message: next.needsUserAction
          ? 'برای موارد حل‌نشده، یکی از گزینه‌های زیر را انتخاب کنید.'
          : null,
    );
  }

  void clear() => state = const FoodAnalysisState();
}

final foodAnalysisStateProvider =
    StateNotifierProvider<FoodAnalysisNotifier, FoodAnalysisState>((ref) {
      return FoodAnalysisNotifier(ref.watch(hybridFoodAnalysisServiceProvider));
    });
