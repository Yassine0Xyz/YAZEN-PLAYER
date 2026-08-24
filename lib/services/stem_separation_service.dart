import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/stem_models.dart';

class StemSeparationService {
  StemSeparationService({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<StemSeparationResult> separateFile(
    String filePath, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/separate'),
    );
    request.files.add(await http.MultipartFile.fromPath('audio', filePath));
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(response));
    }
    onProgress?.call(1);
    return StemSeparationResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['detail']?.toString() ?? 'Stem separation failed.';
    } catch (_) {
      return 'Stem separation failed with status ${response.statusCode}.';
    }
  }

  void dispose() => _client.close();
}
