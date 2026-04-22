import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/models.dart';
import '../utils/app_theme.dart';

class VideoService {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  final Dio _dio = Dio();
  static const String _videoCacheKey = 'cached_videos';

  // ── Mock video data (replace with real API call) ──────────────────────────
  final List<VideoItem> _mockVideos = [
    VideoItem(
      id: '1',
      title: 'Linh hồn sợi chiếu Cẩm Nê',
      description: 'Khám phá ý nghĩa sợi dệt truyền thống Cẩm Nê',
      serverUrl: 'assets/videos/1_Linh_Hon_Chieu_Cam_Ne.mp4',
      thumbnailUrl: 'assets/images/thumbnails/1_lang_cam_ne.jpg',
      category: 'Văn hóa',
      durationSeconds: 297,
      isDownloaded: true,
    ),
    VideoItem(
      id: '2',
      title: 'Kỹ thuật bẻ bìa',
      description: 'Học cách định hình chiếu cứng cáp, bền chặt đồng thời tạo viền thẩm mỹ',
      serverUrl: 'assets/videos/2_Cach_be_bien.mp4',
      thumbnailUrl: 'assets/images/thumbnails/2_be_bien.jpg',
      category: 'Cơ bản',
      durationSeconds: 27,
      isDownloaded: true,
    ),
    VideoItem(
      id: '3',
      title: 'Bảo trì máy dệt thông minh',
      description: 'Hướng dẫn vệ sinh và bảo trì hệ thống điều khiển',
      serverUrl: '${AppConstants.videoServerUrl}/maintenance.mp4',
      thumbnailUrl: '${AppConstants.videoServerUrl}/thumbnails/maintenance.jpg',
      category: 'Kỹ thuật',
      durationSeconds: 418,
    ),
    VideoItem(
      id: '4',
      title: 'Lập trình mẫu dệt tự động',
      description: 'Cách cài đặt chế độ tự động trên ESP32',
      serverUrl: '${AppConstants.videoServerUrl}/auto_mode.mp4',
      thumbnailUrl: '${AppConstants.videoServerUrl}/thumbnails/auto.jpg',
      category: 'AI & Tự động',
      durationSeconds: 630,
    ),
    VideoItem(
      id: '5',
      title: 'Giới thiệu mẫu chiếu truyền thống',
      description: 'Khám phá các mẫu chiếu đặc trưng miền Trung Việt Nam',
      serverUrl: '${AppConstants.videoServerUrl}/traditional.mp4',
      thumbnailUrl: '${AppConstants.videoServerUrl}/thumbnails/traditional.jpg',
      category: 'Văn hóa',
      durationSeconds: 280,
    ),
  ];


  Future<List<VideoItem>> fetchVideos() async {
    // Load from cache first, merge with mock/server data
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_videoCacheKey);
    Map<String, Map<String, dynamic>> cachedData = {};

    if (cachedJson != null) {
      try {
        final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
        cachedData = decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      } catch (_) {}
    }

    // Try to fetch from server, fallback to mock
    List<VideoItem> videos = [];
    try {
      final response = await _dio
          .get(AppConstants.videoServerUrl)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = response.data as List;
        videos = data.map((e) => VideoItem.fromJson(e)).toList();
      }
    } catch (_) {
      videos = List.from(_mockVideos);
    }

    // Merge with cached download info
    for (final video in videos) {
      final cached = cachedData[video.id];
      if (cached != null) {
        final localPath = cached['localPath'] as String?;
        if (localPath != null && File(localPath).existsSync()) {
          video.localPath = localPath;
          video.isDownloaded = true;
        }
      }
    }

    return videos;
  }

  Future<void> downloadVideo(
    VideoItem video, {
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) async {
    // KIỂM TRA NẾU LÀ VIDEO NỘI BỘ (MOCK DATA)
    if (video.serverUrl.startsWith('assets/')) {
      print("Video nội bộ: Không cần tải qua network");
      onProgress(1.0); // Giả lập tiến trình hoàn tất
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Đánh dấu là đã "tải" để UI cho phép nhấn nút Play
      video.isDownloaded = true;
      onComplete(video.serverUrl);
      return;
    }

    // LOGIC TẢI VIDEO THỰC TẾ TỪ URL
    try {
      final dir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${dir.path}/videos');
      if (!videoDir.existsSync()) videoDir.createSync(recursive: true);

      final localPath = '${videoDir.path}/${video.id}.mp4';

      await _dio.download(
        video.serverUrl,
        localPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      video.localPath = localPath;
      video.isDownloaded = true;
      await _saveCacheEntry(video.id, localPath);

      onComplete(localPath);
    } on DioException catch (e) {
      onError('Không thể tải video: ${e.message}');
    } catch (e) {
      onError('Lỗi không xác định: $e');
    }
  }

  Future<void> _saveCacheEntry(String videoId, String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_videoCacheKey);
    Map<String, dynamic> cachedData = {};

    if (cachedJson != null) {
      try {
        cachedData = jsonDecode(cachedJson);
      } catch (_) {}
    }

    cachedData[videoId] = {'localPath': localPath};
    await prefs.setString(_videoCacheKey, jsonEncode(cachedData));
  }

  Future<void> deleteDownload(VideoItem video) async {
    if (video.localPath != null) {
      final f = File(video.localPath!);
      if (f.existsSync()) f.deleteSync();
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_videoCacheKey);
    if (cachedJson != null) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(cachedJson));
        data.remove(video.id);
        await prefs.setString(_videoCacheKey, jsonEncode(data));
      } catch (_) {}
    }

    video.localPath = null;
    video.isDownloaded = false;
  }
}
