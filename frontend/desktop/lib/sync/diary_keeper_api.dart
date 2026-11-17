import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Something the Diary Keeper said no to, with its own explanation.
class DiaryKeeperException implements Exception {
  DiaryKeeperException(this.status, this.detail);

  final int status;
  final String detail;

  bool get unauthorized => status == 401;

  @override
  String toString() => status == 0 ? detail : 'The Diary Keeper said $status: $detail';
}

/// The Diary Keeper's API (backend/SPEC.md): sign-in, nights, epochs, events and recording files.
///
/// Access tokens live 15 minutes; when one expires, the refresh token gets a new pair once and the
/// request is repeated. New tokens are passed to [onTokens], so they can be kept for next time.
class DiaryKeeperApi {
  DiaryKeeperApi(String baseUrl, {http.Client? client, this.refreshToken, this.onTokens})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? accessToken;
  String? refreshToken;

  /// Called with (access, refresh) whenever the server hands out new tokens.
  void Function(String access, String refresh)? onTokens;

  static const _timeout = Duration(seconds: 30);

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> version() async => await _send('GET', '/version', auth: false) as Map<String, dynamic>;

  /// Signs in; returns the user.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final body = await _send('POST', '/auth/login', body: {'email': email, 'password': password}, auth: false);
    return _takeTokens(body as Map<String, dynamic>);
  }

  /// Creates an account (the first account on a Diary Keeper becomes its admin); returns the user.
  Future<Map<String, dynamic>> register(String email, String password, {required String consentVersion, String? displayName}) async {
    final body = await _send('POST', '/auth/register', auth: false, body: {
      'email': email,
      'password': password,
      if (displayName != null && displayName.isNotEmpty) 'display_name': displayName,
      'accept_consent': true,
      'consent_version': consentVersion,
    });
    return _takeTokens(body as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final token = refreshToken;
    if (token == null) return;
    try {
      await _send('POST', '/auth/logout', body: {'refresh_token': token}, auth: false);
    } finally {
      accessToken = null;
      refreshToken = null;
    }
  }

  Map<String, dynamic> _takeTokens(Map<String, dynamic> body) {
    accessToken = body['access_token'] as String;
    refreshToken = body['refresh_token'] as String;
    onTokens?.call(accessToken!, refreshToken!);
    return (body['user'] as Map<String, dynamic>?) ?? {};
  }

  Future<bool> _refresh() async {
    final token = refreshToken;
    if (token == null) return false;
    try {
      _takeTokens(await _send('POST', '/auth/refresh', body: {'refresh_token': token}, auth: false) as Map<String, dynamic>);
      return true;
    } on DiaryKeeperException catch (e) {
      if (e.unauthorized) {
        accessToken = null;
        refreshToken = null;
      }
      return false;
    }
  }

  // ---- Nights ----

  /// Creates the night, or returns the existing one with the same client id (safe to repeat).
  Future<Map<String, dynamic>> createNight(Map<String, dynamic> night) async =>
      await _send('POST', '/nights', body: night) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateNight(String id, Map<String, dynamic> changes) async =>
      await _send('PATCH', '/nights/$id', body: changes) as Map<String, dynamic>;

  /// Upserts epochs by index (safe to repeat), in batches the server accepts.
  Future<void> putEpochs(String nightId, List<Map<String, dynamic>> epochs) async {
    for (var i = 0; i < epochs.length; i += 1000) {
      await _send('PUT', '/nights/$nightId/epochs', body: {'epochs': epochs.sublist(i, (i + 1000).clamp(0, epochs.length))});
    }
  }

  /// Adds events; ones whose client id the server already has are skipped (safe to repeat).
  Future<void> postEvents(String nightId, List<Map<String, dynamic>> events) async {
    for (var i = 0; i < events.length; i += 500) {
      await _send('POST', '/nights/$nightId/events', body: {'events': events.sublist(i, (i + 500).clamp(0, events.length))});
    }
  }

  Future<List<Map<String, dynamic>>> recordings(String nightId) async {
    final body = await _send('GET', '/nights/$nightId/recordings', query: {'limit': '200'}) as Map<String, dynamic>;
    return [for (final item in body['items'] as List) item as Map<String, dynamic>];
  }

  /// Uploads one file of the night, streamed from disk.
  Future<void> uploadRecording(String nightId, File file, {required String kind, String? filename}) async {
    Future<http.StreamedResponse> send() async {
      final request = http.MultipartRequest('POST', _uri('/nights/$nightId/recordings'))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..fields['kind'] = kind
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: filename));
      return _client.send(request).timeout(const Duration(minutes: 30));
    }

    var response = await send();
    if (response.statusCode == 401 && await _refresh()) response = await send();
    final text = await response.stream.bytesToString();
    if (response.statusCode >= 300) throw DiaryKeeperException(response.statusCode, _detail(text));
  }

  // ---- Plumbing ----

  Future<Object?> _send(String method, String path, {Object? body, Map<String, String>? query, bool auth = true}) async {
    Future<http.Response> once() async {
      final request = http.Request(method, _uri(path, query))..headers['Accept'] = 'application/json';
      if (auth && accessToken != null) request.headers['Authorization'] = 'Bearer $accessToken';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      try {
        return await http.Response.fromStream(await _client.send(request).timeout(_timeout));
      } on SocketException {
        throw DiaryKeeperException(0, 'No answer from $baseUrl. Is the Diary Keeper running?');
      } on http.ClientException catch (e) {
        throw DiaryKeeperException(0, 'Could not reach $baseUrl: ${e.message}');
      }
    }

    if (auth && accessToken == null && !await _refresh()) throw DiaryKeeperException(401, 'Not signed in.');
    var response = await once();
    if (auth && response.statusCode == 401 && await _refresh()) response = await once();
    if (response.statusCode >= 300) throw DiaryKeeperException(response.statusCode, _detail(response.body));
    return response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
  }

  static String _detail(String body) {
    try {
      final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first as Map<String, dynamic>;
        return '${(first['loc'] as List?)?.join('.') ?? ''}: ${first['msg']}';
      }
      return '$detail';
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }

  void close() => _client.close();
}
