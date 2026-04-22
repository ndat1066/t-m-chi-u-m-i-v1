// lib/services/pattern_service.dart

import 'dart:convert';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';

class PatternService {
  static Map<String, dynamic>? _cache;

  /// Load toàn bộ file JSON (chỉ load 1 lần)
  static Future<void> _loadJson() async {
    if (_cache != null) return;

    try {
      final data = await rootBundle.loadString('assets/pattern_library.json');
      _cache = jsonDecode(data);
      print("✅ JSON loaded");
      print("📌 Keys: ${_cache!.keys}");
    } catch (e) {
      throw Exception("Lỗi load JSON: $e");
    }
  }

  /// Reload JSON
  static Future<void> reload() async {
    print("🔄 Reload JSON...");
    _cache = null;
    await _loadJson();
  }

  /// Lấy danh sách key
  static Future<List<String>> getAllPatternKeys() async {
    await _loadJson();
    return _cache!.keys.toList();
  }

  /// Load matrix của 1 pattern
  static Future<List<List<int>>> loadPattern(String key) async {
    await _loadJson();

    if (!_cache!.containsKey(key)) {
      throw Exception("❌ Không tìm thấy pattern: $key");
    }

    final rawMatrix = _cache![key]["matrix"];
    List<List<int>> matrix = List<List<int>>.from(
      rawMatrix.map((row) => List<int>.from(row)),
    );

    print("✅ Loaded pattern: $key");
    return matrix;
  }

  /// Lấy color map
  static Future<Map<String, dynamic>> getColorMap(String key) async {
    await _loadJson();

    if (!_cache!.containsKey(key)) {
      throw Exception("Không tìm thấy pattern: $key");
    }

    return Map<String, dynamic>.from(_cache![key]["color_map"] ?? {});
  }

  static List<int> getThanhCanGat(List<int> row, {bool autoMode = false}) {
    List<int> result = [];
    for (int i = 0; i < row.length && i < AppConstants.leverCount; i++) {
      if (row[i] == 1) {
        if (autoMode) {
          // Sử dụng hằng số đã định nghĩa
          if (i >= AppConstants.autoModeStart && i <= AppConstants.autoModeEnd) {
            result.add(i);
          }
        } else {
          result.add(i);
        }
      }
    }
    return result;
  }

  /// Convert row → LED state (31 thanh)
  static List<bool> convertToLEDState(List<int> thanhCanGat) {
    List<bool> ledState = List.generate(31, (index) => false);

    for (var index in thanhCanGat) {
      if (index >= 0 && index < 31) {
        ledState[index] = true;
      }
    }

    return ledState;
  }

  /// Check hoàn thành
  static bool isRowCompleted(List<bool> ledState) {
    return ledState.every((e) => e == false);
  }
}
