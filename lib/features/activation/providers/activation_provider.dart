import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/activation_models.dart';
import '../services/activation_service.dart';

final activationServiceProvider = Provider<ActivationService>(
  (ref) => const ActivationService(),
);

final activationProvider =
    NotifierProvider<ActivationNotifier, ActivationViewState>(
      ActivationNotifier.new,
    );

class ActivationViewState {
  const ActivationViewState({
    this.activation,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final ActivationRecord? activation;
  final bool isSubmitting;
  final String? errorMessage;

  bool get isActivated => activation != null;
}

class ActivationNotifier extends Notifier<ActivationViewState> {
  @override
  ActivationViewState build() => ActivationViewState(
    activation: ref.watch(localStorageServiceProvider).loadActivation(),
  );

  Future<bool> activate(String input) async {
    if (state.isSubmitting) return false;
    final username = normalizeActivationUsername(input);
    if (username.isEmpty) {
      state = ActivationViewState(
        activation: state.activation,
        errorMessage: activationErrorMessage(ActivationCode.invalidUsername),
      );
      return false;
    }

    state = ActivationViewState(
      activation: state.activation,
      isSubmitting: true,
    );
    final store = ref.read(localStorageServiceProvider);
    try {
      final deviceId = await store.ensureActivationDeviceId();
      final result = await ref
          .read(activationServiceProvider)
          .activate(username: username, deviceId: deviceId);
      if (!result.isSuccess) {
        state = ActivationViewState(
          activation: state.activation,
          errorMessage: activationErrorMessage(result.code),
        );
        return false;
      }
      final activation = ActivationRecord(
        username: username,
        deviceId: deviceId,
      );
      await store.saveActivation(activation);
      state = ActivationViewState(activation: activation);
      return true;
    } on ActivationRequestException catch (error) {
      state = ActivationViewState(
        activation: state.activation,
        errorMessage: activationErrorMessage(error),
      );
      return false;
    } catch (_) {
      state = ActivationViewState(
        activation: state.activation,
        errorMessage: activationErrorMessage(ActivationCode.serverError),
      );
      return false;
    }
  }
}
