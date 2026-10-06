import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Error thrown for every failed API call. [message] is always safe to show
/// to the user (it comes from the backend's JSON error body when available).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code = 'error'});

  final String message;
  final int? statusCode;
  final String code; // e.g. department_paused, serving_in_progress, network

  @override
  String toString() => message;
}

/// Thin HTTP wrapper: base URL, JSON, bearer token and error mapping.
/// No widget talks to `http` directly - everything goes through here.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  String? authToken;

  /// Called when an authenticated request gets 401 (token expired/invalid).
  void Function()? onUnauthorized;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> _send(String method, String path, {Map<String, dynamic>? body}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final token = authToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 10));
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.', code: 'timeout');
    } catch (_) {
      throw const ApiException(
        'Cannot reach the server. Check your connection and that the backend is running.',
        code: 'network',
      );
    }

    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        data = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    if (response.statusCode == 401 && token != null) {
      onUnauthorized?.call();
    }
    final error = data is Map ? data['error'] : null;
    if (error is Map) {
      throw ApiException(
        error['message']?.toString() ?? 'Request failed',
        statusCode: response.statusCode,
        code: error['code']?.toString() ?? 'error',
      );
    }
    throw ApiException('Request failed (${response.statusCode})', statusCode: response.statusCode);
  }
}
