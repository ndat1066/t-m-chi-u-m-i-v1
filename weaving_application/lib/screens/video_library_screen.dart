import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../models/models.dart';
import '../services/video_service.dart';
import '../services/profile_service.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class VideoLibraryScreen extends StatefulWidget {
  const VideoLibraryScreen({super.key});

  @override
  State<VideoLibraryScreen> createState() => _VideoLibraryScreenState();
}

class _VideoLibraryScreenState extends State<VideoLibraryScreen> {
  List<VideoItem> _videos = [];
  bool _isLoading = true;
  String _selectedCategory = 'Tất cả';
  final VideoService _videoService = VideoService();

  final List<String> _categories = [
    'Tất cả',
    'Cơ bản',
    'Nâng cao',
    'Kỹ thuật',
    'AI & Tự động',
    'Văn hóa',
  ];

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    final videos = await _videoService.fetchVideos();
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
  }

  List<VideoItem> get _filteredVideos {
    if (_selectedCategory == 'Tất cả') return _videos;
    return _videos.where((v) => v.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildCategoryFilter(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryPurple))
                  : _filteredVideos.isEmpty
                      ? _buildEmptyState()
                      : _buildVideoList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thư viện Video',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Học kỹ thuật dệt từ chuyên gia',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadVideos,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg,
                borderRadius: AppTheme.radiusMD,
                border: Border.all(
                    color: AppTheme.lightPurple.withOpacity(0.2)),
              ),
              child: const Icon(Icons.refresh,
                  color: AppTheme.lightPurple, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final isSelected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: AppTheme.radiusMD,
                gradient: isSelected ? AppTheme.primaryGradient : null,
                color: isSelected ? null : AppTheme.surfaceBg,
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : AppTheme.textMuted.withOpacity(0.2),
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _filteredVideos.length,
      itemBuilder: (_, i) => _VideoCard(
        video: _filteredVideos[i],
        videoService: _videoService,
        onStateChanged: () => setState(() {}),
        onPlay: () => _openVideoPlayer(_filteredVideos[i]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('📹', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text(
            'Không có video trong danh mục này',
            style:
                TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _openVideoPlayer(VideoItem video) async {
    final profile = await ProfileService().loadProfile();
    await ProfileService().addWatchedVideo(profile, video.id);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VideoPlayerPage(video: video),
      ),
    );
  }

}

// ── Video Card ─────────────────────────────────────────────────────────────
class _VideoCard extends StatefulWidget {
  final VideoItem video;
  final VideoService videoService;
  final VoidCallback onStateChanged;
  final VoidCallback onPlay;

  const _VideoCard({
    required this.video,
    required this.videoService,
    required this.onStateChanged,
    required this.onPlay,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _isDownloading = false;

  void _showQuickSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    
    // Xóa thông báo cũ ngay lập tức
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); 
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        duration: const Duration(seconds: 2), // Giảm xuống 2 giây cho nhanh
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMD),
      ),
    );
  }

  Widget _buildThumbnailImage(String url) {
    if (url.isEmpty) {
      return const Text('🎬', style: TextStyle(fontSize: 28));
    }

    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => 
            const Text('🎬', style: TextStyle(fontSize: 28)),
      );
    } else {
      // Nếu là link ảnh từ Mock API (Internet)
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => 
            const Text('🎬', style: TextStyle(fontSize: 28)),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)));
        },
      );
    }
  }

  Future<void> _startDownload() async {
    if (_isDownloading) {
      _showQuickSnackBar("Video đang được tải...");
      return;
    }

    setState(() => _isDownloading = true);
    _showQuickSnackBar("Bắt đầu tải: ${widget.video.title}");
    widget.video.downloadProgress = 0;

    await widget.videoService.downloadVideo(
      widget.video,
      onProgress: (p) {
        if (mounted) {
          setState(() => widget.video.downloadProgress = p);
        }
      },
      onComplete: (path) {
        if (mounted) {
          setState(() => _isDownloading = false);
          widget.onStateChanged();
          _showQuickSnackBar('✅ "${widget.video.title}" đã tải xong!');
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() => _isDownloading = false);
          _showQuickSnackBar(err, isError: true);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
              width: 90,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: AppTheme.radiusSM,
                color: const Color(0xFF1E1535),
              ),
              child: ClipRRect(
                borderRadius: AppTheme.radiusSM,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildThumbnailImage(video.thumbnailUrl),
                    if (_isDownloading)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.6),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                value: video.downloadProgress > 0 ? video.downloadProgress : null,
                                color: AppTheme.accentYellow,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ChipBadge(
                        label: video.category,
                        color: AppTheme.accentBlue),
                    const SizedBox(width: 6),
                    Text(
                      video.durationFormatted,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                if (_isDownloading && video.downloadProgress > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(
                      value: video.downloadProgress,
                      backgroundColor: AppTheme.surfaceBg,
                      valueColor: const AlwaysStoppedAnimation(
                          AppTheme.accentYellow),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action button
          _buildActionButton(video),
        ],
      ),
    );
  }

  Widget _buildActionButton(VideoItem video) {
    if (video.isDownloaded) {
      return GestureDetector(
        onTap: widget.onPlay,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: AppTheme.radiusSM,
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 20),
        ),
      );
    }

    if (_isDownloading) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceBg,
          borderRadius: AppTheme.radiusSM,
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: AppTheme.accentYellow, strokeWidth: 2),
        ),
      );
    }

    return GestureDetector(
      onTap: _startDownload,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          gradient: AppTheme.warmGradient,
          borderRadius: AppTheme.radiusSM,
        ),
        child: const Icon(Icons.download_rounded,
            color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Video Player Page ──────────────────────────────────────────────────────
class _VideoPlayerPage extends StatefulWidget {
  final VideoItem video;
  const _VideoPlayerPage({required this.video});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      if (widget.video.serverUrl.startsWith('assets/')) {
        _controller = VideoPlayerController.asset(widget.video.serverUrl);
      } 
      else if (widget.video.isDownloaded && widget.video.localPath != null && File(widget.video.localPath!).existsSync()) {
        _controller = VideoPlayerController.file(File(widget.video.localPath!));
      } 
      else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.video.serverUrl));
      }

      await _controller!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: true,
        looping: false,
        aspectRatio: _controller!.value.aspectRatio,
        placeholder: Container(color: AppTheme.darkBg),
      );

      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint("Lỗi khởi tạo player: $e");
      if (mounted) setState(() { _error = 'Không thể phát video'; _isInitializing = false; });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.video.title),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isInitializing
            ? const CircularProgressIndicator(
                color: AppTheme.primaryPurple)
            : _error != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: AppTheme.error, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(color: Colors.white)),
                    ],
                  )
                : Chewie(controller: _chewieController!),
      ),
    );
  }
}
