import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calorie_tracker/app.dart';
import 'package:calorie_tracker/core/providers/app_providers.dart';
import 'package:calorie_tracker/data/local/local_storage_service.dart';
import 'package:calorie_tracker/data/local/storage_keys.dart';
import 'package:calorie_tracker/features/activation/models/activation_models.dart';
import 'package:calorie_tracker/features/activation/providers/activation_provider.dart';
import 'package:calorie_tracker/features/activation/screens/activation_screen.dart';
import 'package:calorie_tracker/features/activation/services/activation_service.dart';
import 'package:calorie_tracker/features/onboarding/onboarding_screen.dart';
import 'package:calorie_tracker/features/settings/models/calorie_targets.dart';
import 'package:calorie_tracker/features/settings/providers/calorie_targets_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('activation API', () {
    final cases = <String, ActivationCode>{
      'ACTIVATED': ActivationCode.activated,
      'ALREADY_ACTIVATED': ActivationCode.alreadyActivated,
      'INVALID_USERNAME': ActivationCode.invalidUsername,
      'USERNAME_ALREADY_USED': ActivationCode.usernameAlreadyUsed,
      'INVALID_REQUEST': ActivationCode.invalidRequest,
      'SERVER_ERROR': ActivationCode.serverError,
    };

    for (final entry in cases.entries) {
      test('maps ${entry.key}', () async {
        final expectedSuccess =
            entry.value == ActivationCode.activated ||
            entry.value == ActivationCode.alreadyActivated;
        final service = ActivationService(
          transport: _ResponseTransport(
            ActivationHttpResponse(
              statusCode: 200,
              body: jsonEncode({'success': expectedSuccess, 'code': entry.key}),
            ),
          ),
        );

        final result = await service.activate(
          username: 'qauser',
          deviceId: 'device-id',
        );

        expect(result.code, entry.value);
        expect(result.isSuccess, expectedSuccess);
      });
    }

    test('POST 302 follows with GET and returns ACTIVATED', () async {
      final transport = _SequenceTransport([
        const ActivationHttpResponse(
          statusCode: 302,
          body: '',
          location:
              'https://script.googleusercontent.com/macros/echo?token=private',
        ),
        const ActivationHttpResponse(
          statusCode: 200,
          body: '{"success":true,"code":"ACTIVATED"}',
        ),
      ]);

      final result = await ActivationService(
        transport: transport,
      ).activate(username: 'qauser', deviceId: 'device-id');

      expect(result.code, ActivationCode.activated);
      expect(transport.methods, ['POST', 'GET']);
      expect(
        transport.methods.where((method) => method == 'POST'),
        hasLength(1),
      );
      expect(transport.bodies.first, isNotNull);
      expect(transport.bodies.last, isNull);
      expect(transport.uris.last.host, 'script.googleusercontent.com');
    });

    test('redirected ALREADY_ACTIVATED is successful', () async {
      final transport = _redirectTransport(
        '{"success":true,"code":"ALREADY_ACTIVATED"}',
      );

      final result = await ActivationService(
        transport: transport,
      ).activate(username: 'qauser', deviceId: 'device-id');

      expect(result.code, ActivationCode.alreadyActivated);
      expect(result.isSuccess, isTrue);
    });

    test('redirected INVALID_USERNAME remains a backend failure', () async {
      final transport = _redirectTransport(
        '{"success":false,"code":"INVALID_USERNAME"}',
      );

      final result = await ActivationService(
        transport: transport,
      ).activate(username: 'invalid', deviceId: 'device-id');

      expect(result.code, ActivationCode.invalidUsername);
      expect(result.isSuccess, isFalse);
    });

    test(
      'redirect without Location fails safely without another request',
      () async {
        final transport = _SequenceTransport([
          const ActivationHttpResponse(statusCode: 302, body: ''),
        ]);

        final result = await ActivationService(
          transport: transport,
        ).activate(username: 'qauser', deviceId: 'device-id');

        expect(result.code, ActivationCode.serverError);
        expect(transport.methods, ['POST']);
      },
    );

    test('redirect loop fails safely within the limit', () async {
      final transport = _SequenceTransport([
        const ActivationHttpResponse(
          statusCode: 302,
          body: '',
          location: 'https://script.googleusercontent.com/one',
        ),
        const ActivationHttpResponse(
          statusCode: 302,
          body: '',
          location: activationEndpoint,
        ),
      ]);

      final result = await ActivationService(
        transport: transport,
      ).activate(username: 'qauser', deviceId: 'device-id');

      expect(result.code, ActivationCode.serverError);
      expect(transport.methods, ['POST', 'GET']);
    });

    test('redirect limit prevents an unbounded chain', () async {
      final transport = _SequenceTransport([
        const ActivationHttpResponse(
          statusCode: 302,
          body: '',
          location: 'https://script.googleusercontent.com/one',
        ),
        const ActivationHttpResponse(
          statusCode: 302,
          body: '',
          location: 'https://script.googleusercontent.com/two',
        ),
      ]);

      final result = await ActivationService(
        transport: transport,
        maxRedirects: 1,
      ).activate(username: 'qauser', deviceId: 'device-id');

      expect(result.code, ActivationCode.serverError);
      expect(transport.methods, ['POST', 'GET']);
    });

    test('non-HTTPS redirect is rejected', () async {
      final transport = _SequenceTransport([
        const ActivationHttpResponse(
          statusCode: 302,
          body: '',
          location: 'http://script.googleusercontent.com/unsafe',
        ),
      ]);

      final result = await ActivationService(
        transport: transport,
      ).activate(username: 'qauser', deviceId: 'device-id');

      expect(result.code, ActivationCode.serverError);
      expect(transport.methods, ['POST']);
    });

    test('malformed redirected body becomes a safe server error', () async {
      final transport = _redirectTransport('<html>not json</html>');

      final result = await ActivationService(
        transport: transport,
      ).activate(username: 'qauser', deviceId: 'device-id');

      expect(result.code, ActivationCode.serverError);
    });

    test('maps network failure without exposing transport details', () async {
      const service = ActivationService(transport: _NetworkFailureTransport());
      await expectLater(
        service.activate(username: 'qauser', deviceId: 'device-id'),
        throwsA(
          isA<ActivationRequestException>().having(
            (error) => error.type,
            'type',
            ActivationFailureType.network,
          ),
        ),
      );
      expect(
        activationErrorMessage(
          const ActivationRequestException(ActivationFailureType.network),
        ),
        'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
      );
    });

    test('maps timeout to the friendly connectivity message', () async {
      const service = ActivationService(transport: _TimeoutTransport());
      await expectLater(
        service.activate(username: 'qauser', deviceId: 'device-id'),
        throwsA(
          isA<ActivationRequestException>().having(
            (error) => error.type,
            'type',
            ActivationFailureType.timeout,
          ),
        ),
      );
    });

    test('maps backend failures to the required Persian copy', () {
      expect(
        activationErrorMessage(ActivationCode.invalidUsername),
        'نام کاربری معتبر نیست.',
      );
      expect(
        activationErrorMessage(ActivationCode.usernameAlreadyUsed),
        'این نام کاربری قبلاً روی دستگاه دیگری فعال شده است.',
      );
      expect(
        activationErrorMessage(ActivationCode.invalidRequest),
        'اطلاعات فعال‌سازی معتبر نیست.',
      );
      expect(
        activationErrorMessage(ActivationCode.serverError),
        'در حال حاضر امکان فعال‌سازی وجود ندارد. دوباره تلاش کنید.',
      );
    });
  });

  group('activation persistence and controller', () {
    late Directory directory;
    late Box<dynamic> box;
    late LocalStorageService storage;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('activation_test_');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        'activation_${DateTime.now().microsecondsSinceEpoch}',
      );
      storage = LocalStorageService(box);
    });

    tearDown(() async {
      await box.deleteFromDisk();
      await directory.delete(recursive: true);
    });

    test('deviceId is generated once and reused', () async {
      var generations = 0;
      final first = await storage.ensureActivationDeviceId(
        generator: () {
          generations++;
          return 'generated-device-id';
        },
      );
      final second = await storage.ensureActivationDeviceId(
        generator: () {
          generations++;
          return 'different-device-id';
        },
      );

      expect(first, 'generated-device-id');
      expect(second, first);
      expect(generations, 1);
    });

    test(
      'local activation persists without touching existing app data',
      () async {
        final existingTargets = {
          'trainingDayCalories': 2400,
          'restDayCalories': 1900,
        };
        final existingDrafts = <String, dynamic>{'2026-08-10': <dynamic>[]};
        await box.put(StorageKeys.calorieTargets, existingTargets);
        await box.put(StorageKeys.dailyNutritionDrafts, existingDrafts);

        const activation = ActivationRecord(
          username: 'qauser',
          deviceId: 'device-id',
        );
        await storage.saveActivation(activation);

        expect(storage.loadActivation()?.username, 'qauser');
        expect(storage.loadActivation()?.deviceId, 'device-id');
        expect(box.get(StorageKeys.calorieTargets), existingTargets);
        expect(box.get(StorageKeys.dailyNutritionDrafts), existingDrafts);
      },
    );

    test(
      'double submit shares one request and retries reuse deviceId',
      () async {
        await storage.ensureActivationDeviceId(
          generator: () => 'persistent-device-id',
        );
        final transport = _ControlledTransport();
        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            activationServiceProvider.overrideWithValue(
              ActivationService(transport: transport),
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(activationProvider.notifier);

        final first = notifier.activate('  QAUser  ');
        final duplicate = notifier.activate('ignored');
        await Future<void>.delayed(Duration.zero);
        expect(transport.calls, 1);
        transport.complete(
          const ActivationHttpResponse(
            statusCode: 200,
            body: '{"success":false,"code":"SERVER_ERROR"}',
          ),
        );
        expect(await first, isFalse);
        expect(await duplicate, isFalse);

        final retry = notifier.activate('QAUser');
        await Future<void>.delayed(Duration.zero);
        expect(transport.calls, 2);
        transport.complete(
          const ActivationHttpResponse(
            statusCode: 200,
            body: '{"success":true,"code":"ACTIVATED"}',
          ),
        );
        expect(await retry, isTrue);
        expect(transport.deviceIds, [
          'persistent-device-id',
          'persistent-device-id',
        ]);
        expect(transport.usernames, ['qauser', 'qauser']);
        expect(storage.loadActivation()?.username, 'qauser');
      },
    );

    test('ALREADY_ACTIVATED persists and restart makes no API call', () async {
      await storage.ensureActivationDeviceId(
        generator: () => 'persistent-device-id',
      );
      final transport = _ControlledTransport();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          activationServiceProvider.overrideWithValue(
            ActivationService(transport: transport),
          ),
        ],
      );
      final activation = container
          .read(activationProvider.notifier)
          .activate('QAUser');
      await Future<void>.delayed(Duration.zero);
      transport.complete(
        const ActivationHttpResponse(
          statusCode: 200,
          body: '{"success":true,"code":"ALREADY_ACTIVATED"}',
        ),
      );
      expect(await activation, isTrue);
      expect(storage.loadActivation()?.username, 'qauser');
      container.dispose();

      final restartTransport = _ControlledTransport();
      final restart = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          activationServiceProvider.overrideWithValue(
            ActivationService(transport: restartTransport),
          ),
        ],
      );
      addTearDown(restart.dispose);

      expect(restart.read(activationProvider).isActivated, isTrue);
      expect(restartTransport.calls, 0);
    });

    test(
      'local activation is persisted only after redirected final success',
      () async {
        await storage.ensureActivationDeviceId(
          generator: () => 'persistent-device-id',
        );
        final transport = _redirectTransport(
          '{"success":true,"code":"ALREADY_ACTIVATED"}',
        );
        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            activationServiceProvider.overrideWithValue(
              ActivationService(transport: transport),
            ),
          ],
        );
        addTearDown(container.dispose);

        final activation = container
            .read(activationProvider.notifier)
            .activate('qauser');
        expect(storage.loadActivation(), isNull);
        expect(await activation, isTrue);
        expect(storage.loadActivation()?.deviceId, 'persistent-device-id');
        expect(transport.methods, ['POST', 'GET']);
      },
    );
  });

  group('startup routing', () {
    testWidgets('activation absent shows activation screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activationProvider.overrideWith(_NotActivated.new),
            calorieTargetsProvider.overrideWith(_NoTargets.new),
          ],
          child: const CalorieTrackerApp(),
        ),
      );

      expect(find.byType(ActivationScreen), findsOneWidget);
      expect(find.text('فعال‌سازی Calora'), findsOneWidget);
    });

    testWidgets('activated without targets shows onboarding', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activationProvider.overrideWith(_Activated.new),
            calorieTargetsProvider.overrideWith(_NoTargets.new),
          ],
          child: const CalorieTrackerApp(),
        ),
      );

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    test('activated with targets selects the main Today destination', () {
      expect(
        appStartDestination(
          isActivated: true,
          targets: const CalorieTargets(
            trainingDayCalories: 2400,
            restDayCalories: 1900,
          ),
        ),
        AppStartDestination.main,
      );
    });
  });
}

_SequenceTransport _redirectTransport(String finalBody) => _SequenceTransport([
  const ActivationHttpResponse(
    statusCode: 302,
    body: '',
    location: 'https://script.googleusercontent.com/macros/echo?token=private',
  ),
  ActivationHttpResponse(statusCode: 200, body: finalBody),
]);

class _SequenceTransport implements ActivationHttpTransport {
  _SequenceTransport(List<ActivationHttpResponse> responses)
    : _responses = List.of(responses);

  final List<ActivationHttpResponse> _responses;
  final methods = <String>[];
  final uris = <Uri>[];
  final bodies = <String?>[];

  @override
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  }) async {
    methods.add(method);
    uris.add(uri);
    bodies.add(body);
    if (_responses.isEmpty) {
      throw StateError('Unexpected activation request');
    }
    return _responses.removeAt(0);
  }
}

class _ResponseTransport implements ActivationHttpTransport {
  const _ResponseTransport(this.response);
  final ActivationHttpResponse response;

  @override
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  }) async => response;
}

class _NetworkFailureTransport implements ActivationHttpTransport {
  const _NetworkFailureTransport();

  @override
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  }) => throw const SocketException('private transport detail');
}

class _TimeoutTransport implements ActivationHttpTransport {
  const _TimeoutTransport();

  @override
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  }) => throw TimeoutException('private timeout detail');
}

class _ControlledTransport implements ActivationHttpTransport {
  final _pending = <Completer<ActivationHttpResponse>>[];
  final deviceIds = <String>[];
  final usernames = <String>[];
  int calls = 0;

  @override
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  }) {
    calls++;
    final request = jsonDecode(body!) as Map<String, dynamic>;
    usernames.add(request['username'] as String);
    deviceIds.add(request['deviceId'] as String);
    final completer = Completer<ActivationHttpResponse>();
    _pending.add(completer);
    return completer.future;
  }

  void complete(ActivationHttpResponse response) =>
      _pending.removeAt(0).complete(response);
}

class _NotActivated extends ActivationNotifier {
  @override
  ActivationViewState build() => const ActivationViewState();
}

class _Activated extends ActivationNotifier {
  @override
  ActivationViewState build() => const ActivationViewState(
    activation: ActivationRecord(username: 'qauser', deviceId: 'device-id'),
  );
}

class _NoTargets extends CalorieTargetsNotifier {
  @override
  CalorieTargets? build() => null;
}
