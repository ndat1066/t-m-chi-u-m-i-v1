// lib/services/weaving_api_service.dart
// =============================================================================
// Dịch vụ HTTP duy nhất của Flutter kết nối đến FastAPI backend.
// Mọi API call trong app đều đi qua class này.
//
// CÁC ENDPOINT TƯƠNG ỨNG:
//   renderFromBytes()       → POST /api/patterns/render
//   searchPatternByPrompt() → POST /api/search-pattern
//   getAllPatterns()         → GET  /api/patterns
//   renderPatternById()     → POST /api/render-pattern/{key}
//   editClusterColor()      → POST /api/edit-cluster-color
//   sendRowToEsp32()        → POST /api/esp32/send-row
//   checkServerHealth()     → GET  /api/health
//   checkEsp32Connection()  → GET  /api/esp32/ping
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// ── Models trả về từ backend ──────────────────────────────────────────────────

/// Thông tin một cụm màu (6 clusters tương ứng 6 màu trong COLOR_PALETTE)
class ClusterInfo {
  final int id;           // 0–5
  final String color;     // Hex, ví dụ "#b42832"
  final int pixelCount;
  final double percentage;

  const ClusterInfo({
    required this.id,
    required this.color,
    required this.pixelCount,
    required this.percentage,
  });

  factory ClusterInfo.fromJson(Map<String, dynamic> j) => ClusterInfo(
        id: j['id'] as int,
        color: j['color'] as String,
        pixelCount: j['pixel_count'] as int,
        percentage: (j['percentage'] as num).toDouble(),
      );
}

/// Kết quả render — format chuẩn backend trả về cho mọi endpoint render
class RenderResult {
  final String imageUrl;            // URL đầy đủ ảnh Jacquard 3D
  final List<List<int>> matrix;     // Ma trận 0/1 điều khiển 31 lever
  final List<ClusterInfo> clusters; // 6 cluster màu
  final String? patternName;        // Tên/key mẫu
  final int width;                  // Số cột (luôn = 31)
  final int height;                 // Số hàng

  const RenderResult({
    required this.imageUrl,
    required this.matrix,
    required this.clusters,
    this.patternName,
    this.width = 31,
    this.height = 0,
  });

  factory RenderResult.fromJson(Map<String, dynamic> j) => RenderResult(
        imageUrl: j['image_url'] as String,
        matrix: (j['matrix'] as List)
            .map((row) => List<int>.from(row as List))
            .toList(),
        clusters: (j['clusters'] as List)
            .map((c) => ClusterInfo.fromJson(c as Map<String, dynamic>))
            .toList(),
        patternName: j['pattern_name'] as String?,
        width: (j['width'] as int?) ?? 31,
        height: (j['height'] as int?) ?? 0,
      );
}

/// Một mẫu trong thư viện (kết quả tìm kiếm bằng prompt)
class PatternSuggestion {
  final String id;          // Key trong pattern_library.json
  final String name;
  final String description;
  final String imagePath;
  final List<String> tags;
  final double similarity;  // 0.0–1.0, điểm cosine similarity

  const PatternSuggestion({
    required this.id,
    required this.name,
    required this.description,
    required this.imagePath,
    required this.tags,
    required this.similarity,
  });

  factory PatternSuggestion.fromJson(Map<String, dynamic> j) =>
      PatternSuggestion(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['description'] as String?) ?? '',
        imagePath: (j['image_path'] as String?) ?? '',
        tags: List<String>.from(j['tags'] ?? []),
        similarity: ((j['similarity'] as num?) ?? 0.0).toDouble(),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// SERVICE CLASS
// ══════════════════════════════════════════════════════════════════════════════

class WeavingApiService {
  // Singleton — toàn app dùng chung 1 instance
  static final WeavingApiService _instance = WeavingApiService._internal();
  factory WeavingApiService() => _instance;
  WeavingApiService._internal();

  // URL gốc của FastAPI server — thay đổi IP nếu cần
  String _baseUrl = 'http://192.168.1.8:8000';

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // Headers cho JSON request
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Timeout ngắn cho các request nhẹ (ping, danh sách)
  static const Duration _shortTimeout = Duration(seconds: 8);
  // Timeout dài cho upload + render Jacquard 3D (tốn CPU)
  static const Duration _renderTimeout = Duration(seconds: 60);

  // ════════════════════════════════════════════════════════════════════════
  // 1. RENDER TỪ ẢNH UPLOAD
  // ════════════════════════════════════════════════════════════════════════

  /// Upload ảnh bytes lên backend → nhận về ảnh Jacquard 3D + matrix + clusters
  /// [bytes]: Bytes của file ảnh (PNG/JPG)
  /// [fileName]: Tên file để xác định định dạng
  Future<RenderResult?> renderFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/patterns/render');

      // Xác định media type từ đuôi file
      final ext = fileName.split('.').last.toLowerCase();
      final mediaType = ext == 'png'
          ? MediaType('image', 'png')
          : MediaType('image', 'jpeg');

      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'file',       // Tên field khớp với FastAPI: file: UploadFile = File(...)
          bytes,
          filename: fileName,
          contentType: mediaType,
        ));

      final streamed = await request.send().timeout(_renderTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return RenderResult.fromJson(data);
      } else {
        debugPrint('renderFromBytes lỗi ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('renderFromBytes exception: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 2. TÌM KIẾM MẪU BẰNG PROMPT
  // ════════════════════════════════════════════════════════════════════════

  /// Tìm mẫu phù hợp nhất với prompt — dùng embedding similarity hoặc keyword
  /// [prompt]: Mô tả tiếng Việt/Anh, ví dụ "mẫu sọc xanh đỏ truyền thống"
  /// [topK]: Số mẫu gợi ý (1–5)
  Future<List<PatternSuggestion>> searchPatternByPrompt(
    String prompt, {
    int topK = 3,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/search-pattern'),
            headers: _jsonHeaders,
            body: jsonEncode({'prompt': prompt, 'top_k': topK}),
          )
          .timeout(_shortTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List? ?? [];
        return results
            .map((r) => PatternSuggestion.fromJson(r as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('searchPatternByPrompt exception: $e');
    }
    return [];
  }

  // ════════════════════════════════════════════════════════════════════════
  // 3. LẤY TOÀN BỘ THƯ VIỆN MẪU
  // ════════════════════════════════════════════════════════════════════════

  Future<List<PatternSuggestion>> getAllPatterns() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/patterns'))
          .timeout(_shortTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final patterns = data['patterns'] as List? ?? [];
        return patterns
            .map((p) => PatternSuggestion.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('getAllPatterns exception: $e');
    }
    return [];
  }

  // ════════════════════════════════════════════════════════════════════════
  // 4. RENDER MẪU THEO KEY/ID
  // ════════════════════════════════════════════════════════════════════════

  /// Render một mẫu cụ thể từ thư viện (gọi sau khi user chọn từ gợi ý)
  Future<RenderResult?> renderPatternById(String patternId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/render-pattern/$patternId'),
            headers: _jsonHeaders,
          )
          .timeout(_renderTimeout);

      if (response.statusCode == 200) {
        return RenderResult.fromJson(jsonDecode(response.body));
      }
      debugPrint('renderPatternById lỗi ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('renderPatternById exception: $e');
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 5. ĐỔI MÀU CLUSTER
  // ════════════════════════════════════════════════════════════════════════

  /// Đổi màu cluster_id → new_color_id rồi render lại toàn bộ Jacquard 3D
  /// [patternKey]: Key mẫu đang hiển thị (từ RenderResult.patternName)
  /// [clusterId]: ID cluster cần đổi (0–5)
  /// [newColorId]: ID màu mới trong palette (0–5)
  Future<RenderResult?> editClusterColor({
    required String patternKey,
    required int clusterId,
    required int newColorId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/edit-cluster-color'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'pattern_key': patternKey,
              'cluster_id': clusterId,
              'new_color_id': newColorId,
            }),
          )
          .timeout(_renderTimeout);

      if (response.statusCode == 200) {
        return RenderResult.fromJson(jsonDecode(response.body));
      }
      debugPrint('editClusterColor lỗi ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('editClusterColor exception: $e');
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 6. GỬI MỘT HÀNG ĐẾN ESP32
  // ════════════════════════════════════════════════════════════════════════

  /// Gửi 31 giá trị 0/1 của hàng [rowIndex] đến ESP32 (qua proxy backend)
  Future<bool> sendRowToEsp32(int rowIndex, List<int> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/esp32/send-row'),
            headers: _jsonHeaders,
            body: jsonEncode({'row_index': rowIndex, 'data': data}),
          )
          .timeout(_shortTimeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('sendRowToEsp32 exception: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 7. UTILITY — Health check, ping ESP32, resolve URL
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkEsp32Connection() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/esp32/ping'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['connected'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Tạo URL đầy đủ từ URL trả về từ backend
  /// Backend trả về URL đầy đủ (http://...) nên hàm này chỉ để phòng trường hợp
  /// backend trả path tương đối như "/renders/abc.png"
  String resolveImageUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;  // Đã là URL đầy đủ
    }
    // Ghép với base URL nếu là path tương đối
    final path = url.startsWith('/') ? url : '/$url';
    return '$_baseUrl$path';
  }
}
