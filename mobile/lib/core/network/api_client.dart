import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class FlowPayApiClient {
  final String baseUrl;
  final http.Client _client;

  FlowPayApiClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = client ?? http.Client();

  Future<dynamic> get(String path, {Map<String, String>? queryParams}) async {
    final uri =
        Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
    final res = await _client.get(uri, headers: {'Accept': 'application/json'});
    return _handleResponse(res);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(res);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _client.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(res);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _client.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(res);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data.containsKey('data')) {
        return data['data'];
      }
      return data;
    }

    String errorMsg = 'HTTP ${response.statusCode}';
    try {
      final errObj = jsonDecode(response.body);
      if (errObj['message'] != null) {
        errorMsg = errObj['message'].toString();
      }
    } catch (_) {}
    throw Exception(errorMsg);
  }
}
