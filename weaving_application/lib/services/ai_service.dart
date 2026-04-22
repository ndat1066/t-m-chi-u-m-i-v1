// lib/services/ai_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/app_theme.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  String _baseUrl = _defaultBaseUrl();

  static String _defaultBaseUrl() {
    const envBaseUrl = String.fromEnvironment('AI_API_URL');
    if (envBaseUrl.isNotEmpty) {
      return envBaseUrl;
    }
    
    return AppConstants.aiApiUrl; 
  }

  void setBaseUrl(String url) {
    _baseUrl = _normalizeBaseUrl(url);
  }

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return _defaultBaseUrl();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  String _resolveApiUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  /// Test ket noi API
  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('AI API connection failed: $e');
      return false;
    }
  }

  Future<AIPatternResult?> generateFromPrompt({
    required String prompt,
    bool autoMode = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'prompt': prompt,
              'auto_mode': autoMode,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AIPatternResult.fromJson(data);
      } else {
        debugPrint('AI API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Generate error: $e');
      return null;
    }
  }

  Future<List<String>> getAllPatterns() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/patterns'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final patterns = (decoded['patterns'] as List?) ?? [];
        return patterns
            .whereType<Map>()
            .map((item) => item['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('Get patterns error: $e');
    }
    return [];
  }

  /// Lay lever cho mot row cu the
  Future<List<int>?> getRowLevers({
    required String patternName,
    required int rowIndex,
    bool autoMode = false,
  }) async {
    try {
      final aiUri = Uri.parse('$_baseUrl/api/ai/get-row-levers')
          .replace(queryParameters: {
        'pattern_name': patternName,
        'row_index': rowIndex.toString(),
        'auto_mode': autoMode.toString(),
      });

      final response =
          await http.post(aiUri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<int>.from(data['levers']);
      }
    } catch (e) {
      debugPrint('Get row levers error: $e');
    }
    return null;
  }

  Future<UploadedPatternResult?> processPatternImage({
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/patterns/render');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: fileName));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return UploadedPatternResult.fromJson(jsonDecode(response.body));
      } else {
        debugPrint('Upload failed: ${response.statusCode} - ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('Lỗi Render: $e');
      return null;
    }
  }

  Future<String?> renderPatternImage({required String patternName}) async {
    try {
      final encoded = Uri.encodeComponent(patternName);
      final response = await http
          .post(Uri.parse('$_baseUrl/api/patterns/$encoded/render'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final imageUrl = data['image_url']?.toString();
        if (imageUrl == null || imageUrl.isEmpty) return null;
        
        // Gọi hàm phân giải URL để đảm bảo đường dẫn ảnh hợp lệ
        return _resolveApiUrl(imageUrl);
      }

      debugPrint('Render pattern error: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Render pattern exception: $e');
      return null;
    }
  }
}

/// Model cho ket qua tu AI
class AIPatternResult {
  final String patternName;
  final List<List<int>> matrix;
  final List<int> levers;
  final Map<String, dynamic> colorMap;
  final String message;

  AIPatternResult({
    required this.patternName,
    required this.matrix,
    required this.levers,
    required this.colorMap,
    required this.message,
  });

  factory AIPatternResult.fromJson(Map<String, dynamic> json) {
    return AIPatternResult(
      patternName: json['pattern_name'] ?? '',
      matrix: (json['matrix'] as List?)
              ?.map((row) => List<int>.from(row))
              .toList() ??
          [],
      levers: List<int>.from(json['levers'] ?? []),
      colorMap: json['color_map'] ?? {},
      message: json['message'] ?? '',
    );
  }

  int get totalRows => matrix.length;
}

class UploadedPatternResult {
  final String patternName;
  final String imageUrl;
  final List<List<int>> matrix;

  UploadedPatternResult({
    required this.patternName,
    required this.imageUrl,
    required this.matrix,
  });

  factory UploadedPatternResult.fromJson(Map<String, dynamic> json) {
    final pattern = json['pattern'] ?? {};
    return UploadedPatternResult(
      patternName: pattern['name'] ?? 'pattern_new',
      imageUrl: json['image_url'] ?? '',
      matrix: (pattern['matrix'] as List?)
              ?.map((row) => List<int>.from(row))
              .toList() ?? [],
    );
  }
}