class ActivationRecord {
  const ActivationRecord({required this.username, required this.deviceId});

  final String username;
  final String deviceId;

  Map<String, dynamic> toJson() => {
    'isActivated': true,
    'username': username,
    'deviceId': deviceId,
  };

  static ActivationRecord? fromJson(Map<String, dynamic>? json) {
    if (json?['isActivated'] != true) return null;
    final username = json?['username'];
    final deviceId = json?['deviceId'];
    if (username is! String || username.trim().isEmpty) return null;
    if (deviceId is! String || deviceId.trim().isEmpty) return null;
    return ActivationRecord(username: username, deviceId: deviceId);
  }
}

abstract interface class ActivationStore {
  ActivationRecord? loadActivation();
  Future<String> ensureActivationDeviceId();
  Future<void> saveActivation(ActivationRecord activation);
}

enum ActivationCode {
  activated,
  alreadyActivated,
  usernameAlreadyUsed,
  invalidUsername,
  invalidRequest,
  serverError,
}

class ActivationResult {
  const ActivationResult(this.code);

  final ActivationCode code;

  bool get isSuccess =>
      code == ActivationCode.activated ||
      code == ActivationCode.alreadyActivated;
}

enum ActivationFailureType { network, timeout }

class ActivationRequestException implements Exception {
  const ActivationRequestException(this.type);

  final ActivationFailureType type;
}

String normalizeActivationUsername(String value) => value.trim().toLowerCase();

String activationErrorMessage(Object failure) => switch (failure) {
  ActivationCode.invalidUsername => 'نام کاربری معتبر نیست.',
  ActivationCode.usernameAlreadyUsed =>
    'این نام کاربری قبلاً روی دستگاه دیگری فعال شده است.',
  ActivationCode.invalidRequest => 'اطلاعات فعال‌سازی معتبر نیست.',
  ActivationCode.serverError =>
    'در حال حاضر امکان فعال‌سازی وجود ندارد. دوباره تلاش کنید.',
  ActivationRequestException() =>
    'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
  _ => 'در حال حاضر امکان فعال‌سازی وجود ندارد. دوباره تلاش کنید.',
};
