import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/activation_models.dart';

const activationEndpoint =
    'https://script.google.com/macros/s/AKfycby8Cx6tI5n1NHndXjboGESL2wg-DpF1WMMMEJl4EnxUEjYO3m9a-2KWUZUFcnvWLVt7nw/exec';

class ActivationHttpResponse {
  const ActivationHttpResponse({
    required this.statusCode,
    required this.body,
    this.location,
  });

  final int statusCode;
  final String body;
  final String? location;
}

abstract interface class ActivationHttpTransport {
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  });
}

class IoActivationHttpTransport implements ActivationHttpTransport {
  const IoActivationHttpTransport();

  @override
  Future<ActivationHttpResponse> send({
    required String method,
    required Uri uri,
    String? body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = false;
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close().timeout(timeout);
      return ActivationHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join().timeout(timeout),
        location: response.headers.value(HttpHeaders.locationHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class ActivationService {
  const ActivationService({
    this.transport = const IoActivationHttpTransport(),
    this.timeout = const Duration(seconds: 20),
    this.maxRedirects = 3,
  });

  final ActivationHttpTransport transport;
  final Duration timeout;
  final int maxRedirects;

  Future<ActivationResult> activate({
    required String username,
    required String deviceId,
  }) async {
    try {
      final response = await _sendFollowingRedirects(
        body: jsonEncode({'username': username, 'deviceId': deviceId}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const ActivationResult(ActivationCode.serverError);
      }
      final value = jsonDecode(response.body);
      if (value is! Map) {
        return const ActivationResult(ActivationCode.serverError);
      }
      final result = ActivationResult(_parseCode(value['code']));
      if (value['success'] is! bool || value['success'] != result.isSuccess) {
        return const ActivationResult(ActivationCode.serverError);
      }
      return result;
    } on TimeoutException {
      throw const ActivationRequestException(ActivationFailureType.timeout);
    } on SocketException {
      throw const ActivationRequestException(ActivationFailureType.network);
    } on FormatException {
      return const ActivationResult(ActivationCode.serverError);
    } on ActivationRequestException {
      rethrow;
    } catch (_) {
      throw const ActivationRequestException(ActivationFailureType.network);
    }
  }

  Future<ActivationHttpResponse> _sendFollowingRedirects({
    required String body,
  }) async {
    var currentUri = Uri.parse(activationEndpoint);
    var response = await transport.send(
      method: 'POST',
      uri: currentUri,
      body: body,
      timeout: timeout,
    );
    var redirectCount = 0;
    final visited = <Uri>{currentUri};

    while (_isRedirect(response.statusCode)) {
      if (redirectCount >= maxRedirects) {
        return const ActivationHttpResponse(statusCode: 508, body: '');
      }
      final location = response.location;
      if (location == null || location.trim().isEmpty) {
        return const ActivationHttpResponse(statusCode: 502, body: '');
      }
      final parsedLocation = Uri.tryParse(location);
      if (parsedLocation == null) {
        return const ActivationHttpResponse(statusCode: 502, body: '');
      }
      final redirectUri = currentUri.resolveUri(parsedLocation);
      if (redirectUri.scheme != 'https' || redirectUri.host.isEmpty) {
        return const ActivationHttpResponse(statusCode: 502, body: '');
      }
      if (!visited.add(redirectUri)) {
        return const ActivationHttpResponse(statusCode: 508, body: '');
      }
      redirectCount++;
      currentUri = redirectUri;
      response = await transport.send(
        method: 'GET',
        uri: currentUri,
        timeout: timeout,
      );
    }
    return response;
  }
}

bool _isRedirect(int statusCode) =>
    statusCode == HttpStatus.movedPermanently ||
    statusCode == HttpStatus.found ||
    statusCode == HttpStatus.seeOther ||
    statusCode == HttpStatus.temporaryRedirect ||
    statusCode == HttpStatus.permanentRedirect;

ActivationCode _parseCode(Object? value) => switch (value) {
  'ACTIVATED' => ActivationCode.activated,
  'ALREADY_ACTIVATED' => ActivationCode.alreadyActivated,
  'USERNAME_ALREADY_USED' => ActivationCode.usernameAlreadyUsed,
  'INVALID_USERNAME' => ActivationCode.invalidUsername,
  'INVALID_REQUEST' => ActivationCode.invalidRequest,
  'SERVER_ERROR' => ActivationCode.serverError,
  _ => ActivationCode.serverError,
};
