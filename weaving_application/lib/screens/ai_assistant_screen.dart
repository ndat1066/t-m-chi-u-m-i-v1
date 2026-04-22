// lib/screens/ai_assistant_screen.dart
// =============================================================================
// Màn hình chính "Trợ lý Dệt Chiếu" — điểm kết nối giữa người dùng và backend
//
// LUỒNG SỬ DỤNG CHÍNH:
//   A. Upload ảnh: Chọn ảnh → Nhấn "Xử lý" → Backend render Jacquard 3D
//      → Xem ảnh → Chỉnh màu cluster → Xác nhận → Gửi ESP32
//
//   B. AI Gợi ý: Nhập prompt → Backend tìm mẫu → Chọn mẫu → Render
//      → Xem ảnh → Chỉnh màu → Xác nhận → Gửi ESP32
//
// CÁC TÍNH NĂNG:
//   1. Chatbox nhập prompt → tìm mẫu tương tự (embedding similarity)
//   2. Upload ảnh hoa văn → render Jacquard 3D
//   3. Preview ảnh render (có thể zoom)
//   4. Bảng 6 màu + cluster editing
//   5. Grid 31 thanh gạt (lever) theo từng hàng
//   6. Gửi từng hàng xuống ESP32
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/profile_service.dart';
import '../services/pattern_service.dart';
import '../services/weaving_api_service.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen>
    with TickerProviderStateMixin {

  // ── Services & Controllers ──────────────────────────────────────────────
  final WeavingApiService _api = WeavingApiService();
  final TextEditingController _aiController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  // ── State ───────────────────────────────────────────────────────────────
  WeavingPattern _selectedPattern = WeavingPattern.defaults[0];
  bool _showMachineControl = false;  // Hiện phần điều khiển máy sau khi có render
  bool _isAutoMode = false;          // Chế độ tự động: chỉ lever 11–23
  bool _isSending = false;           // Đang gửi lệnh ESP32
  bool _isAIProcessing = false;      // Đang xử lý AI prompt
  bool _isUploadingImage = false;    // Đang upload và render ảnh
  bool _esp32Connected = false;
  bool _serverConnected = false;

  Uint8List? _selectedImageBytes;    // Bytes của ảnh người dùng chọn
  String? _selectedImageName;

  // Kết quả render từ backend — null khi chưa render
  RenderResult? _renderResult;
  int _currentRowIndex = 0;          // Hàng đang hiển thị trong LED panel

  // Trạng thái 31 lever
  late List<LeverState> _levers;

  // Animation cho indicator kết nối
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── 6 màu của palette hệ thống (khớp với COLOR_PALETTE trong backend) ──
  // Thứ tự: 0=nền(kem), 1=đỏ, 2=xanh lá, 3=xanh dương, 4=vàng, 5=nâu
  static const List<Color> _paletteColors = [
    Color(0xFFEBD7AA),   // 0 — Nền (kem/beige)
    Color(0xFFB42832),   // 1 — Đỏ
    Color(0xFF2D6E4B),   // 2 — Xanh lá
    Color(0xFF234B91),   // 3 — Xanh dương
    Color(0xFFD79B23),   // 4 — Vàng
    Color(0xFF7D5F41),   // 5 — Nâu
  ];
  static const List<String> _paletteNames = [
    'Nền', 'Đỏ', 'Xanh lá', 'Xanh dương', 'Vàng', 'Nâu',
  ];

  // Cluster đang được chọn để đổi màu (null = chưa chọn)
  int? _selectedClusterId;

  @override
  void initState() {
    super.initState();
    _initLevers();
    _checkConnections();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _aiController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _initLevers() {
    _levers = List.generate(
      AppConstants.leverCount,  // 31
      (i) => LeverState(index: i, isOn: false, isEnabled: true),
    );
  }

  Future<void> _checkConnections() async {
    final results = await Future.wait([
      _api.checkServerHealth(),
      _api.checkEsp32Connection(),
    ]);
    if (mounted) {
      setState(() {
        _serverConnected = results[0];
        _esp32Connected = results[1];
      });
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // XỬ LÝ CHẾ ĐỘ LEVER
  // ════════════════════════════════════════════════════════════════════════

  void _applyMode(bool autoMode) {
    setState(() {
      _isAutoMode = autoMode;
      for (int i = 0; i < _levers.length; i++) {
        if (autoMode) {
          // Chế độ tự động: chỉ lever 10–22 (index 0-based)
          final inRange = i >= AppConstants.autoModeStart &&
                          i <= AppConstants.autoModeEnd;
          _levers[i].isEnabled = inRange;
          if (!inRange) _levers[i].isOn = false;
        } else {
          _levers[i].isEnabled = true;
        }
      }
    });
    if (_renderResult != null) {
      _applyLeversFromRow(_currentRowIndex);
    }
  }

  /// Cập nhật 31 lever theo hàng [rowIndex] của matrix render
  void _applyLeversFromRow(int rowIndex) {
    if (_renderResult == null || _renderResult!.matrix.isEmpty) return;
    final matrix = _renderResult!.matrix;
    if (rowIndex >= matrix.length) return;

    final row = matrix[rowIndex];  // List<int> 31 giá trị 0/1
    setState(() {
      _currentRowIndex = rowIndex;
      for (int i = 0; i < _levers.length; i++) {
        if (_levers[i].isEnabled) {
          _levers[i].isOn = (i < row.length && row[i] == 1);
        } else {
          _levers[i].isOn = false;
        }
      }
    });
  }

  void _nextRow() {
    if (_renderResult == null) return;
    final next = _currentRowIndex + 1;
    if (next < _renderResult!.height) {
      _applyLeversFromRow(next);
      HapticFeedback.selectionClick();
    } else {
      _showSnack('Đã hoàn thành tất cả ${_renderResult!.height} hàng!');
    }
  }

  void _previousRow() {
    if (_currentRowIndex > 0) {
      _applyLeversFromRow(_currentRowIndex - 1);
      HapticFeedback.selectionClick();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // AI PROMPT → TÌM MẪU
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _processAIPrompt() async {
    final prompt = _aiController.text.trim();
    if (prompt.isEmpty) {
      _showSnack('Vui lòng nhập mô tả hoa văn', isError: true);
      return;
    }
    setState(() => _isAIProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      // Bước 1: Tìm mẫu phù hợp nhất (top 1)
      final suggestions = await _api.searchPatternByPrompt(prompt, topK: 1);

      if (suggestions.isEmpty) {
        _showSnack('Không tìm thấy mẫu phù hợp, thử mô tả khác', isError: true);
        return;
      }

      final pattern = suggestions.first;

      // Bước 2: Render mẫu đó → Jacquard 3D
      final result = await _api.renderPatternById(pattern.id);

      if (result != null && mounted) {
        setState(() {
          _renderResult = result;
          _currentRowIndex = 0;
          _selectedClusterId = null;
          _showMachineControl = true;
        });
        _applyLeversFromRow(0);
        _showSnack('Đã render mẫu: ${pattern.name}');

        // Lưu vào lịch sử profile
        final profile = await ProfileService().loadProfile();
        await ProfileService().addPatternToHistory(profile, pattern.name);
      } else {
        _showSnack('Lỗi render mẫu từ server', isError: true);
      }
    } catch (e) {
      _showSnack('Lỗi kết nối AI: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isAIProcessing = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // UPLOAD ẢNH → RENDER
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _pickPatternImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048, maxHeight: 2048, imageQuality: 95,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = picked.name.isNotEmpty ? picked.name : 'upload.jpg';
        _renderResult = null;       // Reset kết quả cũ
        _selectedClusterId = null;
        _showMachineControl = false;
      });
    } catch (e) {
      _showSnack('Không thể chọn ảnh: $e', isError: true);
    }
  }

  Future<void> _uploadImageAndRender() async {
    if (_selectedImageBytes == null) {
      _showSnack('Vui lòng chọn ảnh trước', isError: true);
      return;
    }
    setState(() => _isUploadingImage = true);

    try {
      final result = await _api.renderFromBytes(
        _selectedImageBytes!,
        _selectedImageName ?? 'upload.jpg',
      );

      if (result != null && mounted) {
        setState(() {
          _renderResult = result;
          _currentRowIndex = 0;
          _selectedClusterId = null;
          _showMachineControl = true;
        });
        _applyLeversFromRow(0);
        _showSnack('Render thành công! ${result.height} hàng × 31 cột');
      } else {
        _showSnack('Lỗi render ảnh. Thử lại hoặc đổi ảnh khác.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // CLUSTER COLOR EDITING
  // ════════════════════════════════════════════════════════════════════════

  /// Đổi màu của [clusterId] thành màu [newColorId] rồi render lại
  Future<void> _editClusterColor(int clusterId, int newColorId) async {
    if (_renderResult?.patternName == null) return;

    setState(() {
      _isUploadingImage = true;  // Tái sử dụng loading state
      _selectedClusterId = null;
    });

    final result = await _api.editClusterColor(
      patternKey: _renderResult!.patternName!,
      clusterId: clusterId,
      newColorId: newColorId,
    );

    if (result != null && mounted) {
      setState(() {
        _renderResult = result;
        _currentRowIndex = 0;
      });
      _applyLeversFromRow(0);
      _showSnack('Đã đổi màu: ${_paletteNames[clusterId]} → ${_paletteNames[newColorId]}');
    } else {
      _showSnack('Lỗi đổi màu cluster', isError: true);
    }

    if (mounted) setState(() => _isUploadingImage = false);
  }

  // ════════════════════════════════════════════════════════════════════════
  // GỬI ĐẾN ESP32
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _confirmPattern() async {
    setState(() => _showMachineControl = true);
    final profile = await ProfileService().loadProfile();
    final name = _renderResult?.patternName ?? _selectedPattern.name;
    await ProfileService().addPatternToHistory(profile, name);
    HapticFeedback.lightImpact();
    _showSnack('Đã xác nhận mẫu dệt!');
  }

  Future<void> _sendToMachine() async {
    if (_renderResult == null || _isSending) return;
    setState(() => _isSending = true);
    HapticFeedback.mediumImpact();

    bool allSuccess = true;
    final matrix = _renderResult!.matrix;

    for (int i = 0; i < matrix.length; i++) {
      final success = await _api.sendRowToEsp32(i, matrix[i]);
      if (mounted) {
        _applyLeversFromRow(i);  // UI lever chạy theo hàng đang gửi
      }
      if (!success) {
        allSuccess = false;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (mounted) {
      setState(() => _isSending = false);
      _showSnack(
        allSuccess ? '✅ Đã gửi ${matrix.length} hàng đến máy dệt'
                   : '❌ Lỗi kết nối ở hàng ${_currentRowIndex + 1}',
        isError: !allSuccess,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ════════════════════════════════════════════════════════════════════════

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  void _showZoomableImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true, minScale: 0.5, maxScale: 5.0,
              child: ClipRRect(
                borderRadius: AppTheme.radiusMD,
                child: Image.network(
                  imageUrl, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text(
                    'Lỗi hiển thị ảnh',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10, right: 10,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildPatternPreview()),
            SliverToBoxAdapter(child: _buildPatternSelector()),
            SliverToBoxAdapter(child: _buildAIInput()),
            SliverToBoxAdapter(child: _buildUploadRenderSection()),
            SliverToBoxAdapter(child: _buildActionButtons()),
            if (_showMachineControl && _renderResult != null) ...[
              SliverToBoxAdapter(child: _buildColorClusterPanel()),
              SliverToBoxAdapter(child: _buildRowNavigator()),
              SliverToBoxAdapter(child: _buildModeSelector()),
              SliverToBoxAdapter(child: _buildLeverGrid()),
              SliverToBoxAdapter(child: _buildSendButton()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _serverConnected
                    ? const Color(0xFF21D363)
                    : AppTheme.accentOrange,
                boxShadow: [
                  BoxShadow(
                    color: (_serverConnected
                            ? AppTheme.success
                            : AppTheme.accentOrange)
                        .withOpacity(_pulseAnim.value * 0.8),
                    blurRadius: 10 * _pulseAnim.value,
                    spreadRadius: 2 * _pulseAnim.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trợ lý Dệt Chiếu',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF689FFF)),
                ),
                Text(
                  _serverConnected
                      ? 'AI API Connected'
                      : 'Local Mode (API Offline)',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF8395AF)),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _checkConnections,
            child: ChipBadge(
              label: _esp32Connected ? 'ESP32' : 'Offline',
              color: _esp32Connected ? AppTheme.success : AppTheme.accentOrange,
            ),
          ),
        ],
      ),
    );
  }

  // ── Pattern Preview ─────────────────────────────────────────────────────
  Widget _buildPatternPreview() {
    final displayName =
        _renderResult?.patternName ?? _selectedPattern.name;
    final displayDesc = _renderResult != null
        ? 'Ma trận ${_renderResult!.height} hàng × 31 cột'
        : _selectedPattern.description;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: GlassCard(
        padding: EdgeInsets.zero,
        gradient: AppTheme.primaryGradient,
        boxShadow: AppTheme.glowShadow(const Color(0xFFD2B5FF), blur: 30),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: AppTheme.radiusLG,
              child: SizedBox(
                height: 250,
                width: double.infinity,
                child: Image.asset(
                  _selectedPattern.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPatternFallback(),
                ),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900)),
                        Text(displayDesc,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (_renderResult != null)
                    const ChipBadge(label: 'AI', color: Color(0xFF9B59B6))
                  else
                    const ChipBadge(
                        label: 'Đang chọn', color: Color(0xFFFFC815)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatternFallback() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.texture, color: Colors.white, size: 48),
            const SizedBox(height: 8),
            Text(_selectedPattern.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ── Pattern Selector ────────────────────────────────────────────────────
  Widget _buildPatternSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 20, bottom: 12),
            child: SectionHeader(
              title: 'Chọn mẫu dệt truyền thống',
              subtitle: 'Vuốt ngang để xem thêm mẫu',
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: WeavingPattern.defaults.length,
              itemBuilder: (_, i) {
                final p = WeavingPattern.defaults[i];
                final isSelected = p.id == _selectedPattern.id;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedPattern = p;
                    _renderResult = null;
                    _selectedClusterId = null;
                    _showMachineControl = false;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 12),
                    width: 90,
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.radiusMD,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFF9D803)
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? AppTheme.glowShadow(const Color(0xFFE8B200),
                              blur: 40)
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: AppTheme.radiusMD,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(p.imagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                    decoration: BoxDecoration(
                                        gradient: i == 0
                                            ? AppTheme.primaryGradient
                                            : AppTheme.coolGradient),
                                    child: const Center(
                                        child: Icon(Icons.texture,
                                            color: Colors.white, size: 28)),
                                  )),
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.75)
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: Text(p.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 6, right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: AppTheme.accentYellow,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.check,
                                    color: Colors.black, size: 10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── AI Prompt Input ─────────────────────────────────────────────────────
  Widget _buildAIInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Mô tả yêu cầu hoa văn',
            subtitle: 'AI sẽ tìm mẫu phù hợp trong thư viện',
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppTheme.radiusLG,
              border: Border.all(
                  color: AppTheme.lightPurple.withOpacity(0.25)),
              boxShadow: AppTheme.softShadow,
              gradient: LinearGradient(
                colors: [
                  AppTheme.surfaceBg.withOpacity(0.9),
                  const Color.fromARGB(255, 255, 251, 251).withOpacity(0.95)
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _aiController,
                    maxLines: 3, minLines: 2,
                    style: const TextStyle(
                        color: Color(0xFF649DFF), fontSize: 14),
                    decoration: const InputDecoration(
                      hintText:
                          'VD: Mẫu sọc truyền thống, hoa văn caro đỏ xanh...',
                      hintStyle:
                          TextStyle(color: AppTheme.textMuted, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: GestureDetector(
                    onTap: _isAIProcessing ? null : _processAIPrompt,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: _isAIProcessing
                            ? null
                            : AppTheme.primaryGradient,
                        color: _isAIProcessing ? AppTheme.textMuted : null,
                        borderRadius: AppTheme.radiusSM,
                      ),
                      child: _isAIProcessing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Upload & Render Section ─────────────────────────────────────────────
  Widget _buildUploadRenderSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Upload ảnh & Render Jacquard 3D',
            subtitle: 'Gửi ảnh hoa văn → nhận ảnh mô phỏng dệt thật',
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview ảnh đã chọn
                if (_selectedImageBytes != null)
                  ClipRRect(
                    borderRadius: AppTheme.radiusMD,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: SizedBox(
                        width: double.infinity,
                        child: Image.memory(_selectedImageBytes!,
                            fit: BoxFit.contain),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 150, width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.radiusMD,
                      color: AppTheme.surfaceBg,
                      border: Border.all(
                          color: AppTheme.lightPurple.withOpacity(0.35)),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined,
                              color: AppTheme.textMuted, size: 34),
                          SizedBox(height: 8),
                          Text('Chưa chọn ảnh',
                              style: TextStyle(color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        label: 'Chọn ảnh',
                        onTap: _pickPatternImage,
                        icon: Icons.photo_library_outlined,
                        gradient: AppTheme.coolGradient,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GradientButton(
                        label: 'Xử lý',
                        onTap: (_selectedImageBytes == null ||
                                _isUploadingImage)
                            ? null
                            : _uploadImageAndRender,
                        icon: Icons.cloud_upload_rounded,
                        gradient: AppTheme.warmGradient,
                        isLoading: _isUploadingImage,
                      ),
                    ),
                  ],
                ),
                if (_renderResult?.patternName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Mẫu đang dệt: ${_renderResult!.patternName}',
                    style: const TextStyle(
                        color: AppTheme.accentBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ],
            ),
          ),

          // ── Ảnh Jacquard 3D output ──────────────────────────────────
          if (_renderResult != null) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Preview ảnh Jacquard 3D',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700)),
                      Text('Chạm để phóng to',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontStyle: FontStyle.italic)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _showZoomableImage(
                        context,
                        _api.resolveImageUrl(_renderResult!.imageUrl)),
                    child: ClipRRect(
                      borderRadius: AppTheme.radiusMD,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              _api.resolveImageUrl(_renderResult!.imageUrl),
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, prog) {
                                if (prog == null) return child;
                                return Container(
                                  color: AppTheme.surfaceBg,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: prog.cumulativeBytesLoaded /
                                            (prog.expectedTotalBytes ?? 1),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text('Đang tải ảnh...',
                                          style: TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 12)),
                                    ],
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => Container(
                                color: AppTheme.surfaceBg,
                                alignment: Alignment.center,
                                child: const Text(
                                    'Không tải được ảnh output',
                                    style: TextStyle(
                                        color: AppTheme.textMuted)),
                              ),
                            ),
                            Positioned(
                              bottom: 8, right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.zoom_in,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Color Cluster Panel — ĐỔI MÀU 6 CLUSTER ────────────────────────────
  Widget _buildColorClusterPanel() {
    if (_renderResult == null) return const SizedBox.shrink();
    final clusters = _renderResult!.clusters
        .where((c) => c.pixelCount > 0)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.palette_outlined,
                    size: 18, color: AppTheme.accentBlue),
                const SizedBox(width: 6),
                const Text('Chỉnh màu hoa văn',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const Spacer(),
                if (_selectedClusterId != null)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _selectedClusterId = null),
                    child: const ChipBadge(
                        label: 'Hủy chọn', color: AppTheme.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Chọn vùng màu → chọn màu thay thế',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),

            // ── Danh sách cluster hiện tại ──────────────────────────
            ...clusters.map((c) {
              final isSelected = _selectedClusterId == c.id;
              // Parse hex → Color
              final hex = c.color.replaceAll('#', '');
              final clusterColor =
                  Color(int.parse('FF$hex', radix: 16));

              return GestureDetector(
                onTap: _isUploadingImage
                    ? null
                    : () => setState(() =>
                        _selectedClusterId =
                            isSelected ? null : c.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: AppTheme.radiusSM,
                    color: isSelected
                        ? AppTheme.accentBlue.withOpacity(0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.accentBlue
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Ô màu hiện tại
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: clusterColor,
                          borderRadius: AppTheme.radiusSM,
                          border: Border.all(
                              color: AppTheme.textMuted
                                  .withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: clusterColor.withOpacity(0.4),
                              blurRadius: 8,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_paletteNames[c.id]} (ID: ${c.id})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary),
                            ),
                            Text(
                              '${c.percentage.toStringAsFixed(1)}% diện tích',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected
                            ? Icons.edit
                            : Icons.chevron_right,
                        size: 16,
                        color: isSelected
                            ? AppTheme.accentBlue
                            : AppTheme.textMuted,
                      ),
                    ],
                  ),
                ),
              );
            }),

            // ── Color Picker (hiện khi đã chọn cluster) ─────────────
            if (_selectedClusterId != null) ...[
              const Divider(height: 20),
              Text(
                'Đổi màu cluster "${_paletteNames[_selectedClusterId!]}" thành:',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: List.generate(6, (i) {
                  // Không hiển thị màu hiện tại của cluster đang chọn
                  final isCurrent = i == _selectedClusterId;
                  return GestureDetector(
                    onTap: (_isUploadingImage || isCurrent)
                        ? null
                        : () {
                            final cid = _selectedClusterId!;
                            _editClusterColor(cid, i);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: _paletteColors[i],
                        borderRadius: AppTheme.radiusSM,
                        border: Border.all(
                          color: isCurrent
                              ? AppTheme.accentBlue
                              : _paletteColors[i] == Colors.white
                                  ? AppTheme.textMuted.withOpacity(0.3)
                                  : Colors.transparent,
                          width: isCurrent ? 2.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _paletteColors[i].withOpacity(0.4),
                            blurRadius: 8, spreadRadius: 1,
                          )
                        ],
                        // Mờ đi nếu là màu hiện tại
                      ),
                      child: isCurrent
                          ? const Center(
                              child: Icon(Icons.check,
                                  color: Colors.white, size: 20))
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              // Tên 6 màu
              Wrap(
                spacing: 10, runSpacing: 4,
                children: List.generate(6, (i) => SizedBox(
                  width: 48,
                  child: Text(
                    _paletteNames[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9, color: AppTheme.textMuted),
                  ),
                )),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Action Buttons ──────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: GradientButton(
              label: 'Xác nhận',
              onTap: _confirmPattern,
              icon: Icons.check_circle_outline,
              gradient: AppTheme.primaryGradient,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GradientButton(
              label: 'AI Gợi ý',
              onTap: _processAIPrompt,
              icon: Icons.auto_awesome,
              gradient: AppTheme.warmGradient,
              isLoading: _isAIProcessing,
            ),
          ),
        ],
      ),
    );
  }

  // ── Row Navigator ────────────────────────────────────────────────────────
  Widget _buildRowNavigator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GlassCard(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mẫu: ${_renderResult!.patternName ?? 'pattern_render'}',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700),
                ),
                ChipBadge(
                  label: 'Hàng ${_currentRowIndex + 1}/${_renderResult!.height}',
                  color: AppTheme.accentBlue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _currentRowIndex > 0 ? _previousRow : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Trước'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceBg,
                      foregroundColor: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentRowIndex <
                            _renderResult!.height - 1
                        ? _nextRow
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Tiếp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (_currentRowIndex + 1) / _renderResult!.height,
              backgroundColor: AppTheme.surfaceBg,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.accentYellow),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mode Selector ────────────────────────────────────────────────────────
  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
              title: 'Điều khiển máy dệt',
              subtitle: 'Chọn chế độ vận hành'),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _ModeButton(
                  label: 'Thủ công',
                  icon: Icons.tune,
                  isSelected: !_isAutoMode,
                  description: 'Cả 31 thanh gạt (1-31)',
                  onTap: () => _applyMode(false),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _ModeButton(
                  label: 'Tự động',
                  icon: Icons.auto_fix_high,
                  isSelected: _isAutoMode,
                  description: 'Chỉ thanh 11-23 hoạt động',
                  onTap: () => _applyMode(true),
                ),
              ),
            ],
          ),
          if (_isAutoMode)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withOpacity(0.1),
                  borderRadius: AppTheme.radiusSM,
                  border: Border.all(
                      color: AppTheme.accentBlue.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.accentBlue, size: 14),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Chế độ tự động: Chỉ thanh gạt 11-23 được kích hoạt.',
                        style: TextStyle(
                            color: AppTheme.accentBlue, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Lever Grid ───────────────────────────────────────────────────────────
  Widget _buildLeverGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('31 Thanh Gạt',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_levers.where((l) => l.isOn).length} đang bật',
                    style: const TextStyle(
                        color: AppTheme.accentYellow, fontSize: 15)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() {
                    for (final l in _levers) {
                      if (l.isEnabled) l.isOn = false;
                    }
                  }),
                  child: const ChipBadge(
                      label: 'Tắt tất cả', color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.68,
              ),
              itemCount: 31,
              itemBuilder: (_, i) => LeverToggle(
                index: i,
                isOn: _levers[i].isOn,
                isEnabled: _levers[i].isEnabled,
                onTap: () {
                  if (_levers[i].isEnabled) {
                    setState(() => _levers[i].isOn = !_levers[i].isOn);
                    HapticFeedback.selectionClick();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Send Button ─────────────────────────────────────────────────────────
  Widget _buildSendButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GradientButton(
        label: 'Gửi tín hiệu đến máy dệt',
        onTap: _sendToMachine,
        icon: Icons.send_rounded,
        gradient: AppTheme.warmGradient,
        isLoading: _isSending,
        width: double.infinity,
      ),
    );
  }
}

// ── Widget phụ trợ ─────────────────────────────────────────────────────────
class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final String description;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusLG,
          gradient: isSelected ? AppTheme.primaryGradient : null,
          color: isSelected ? null : AppTheme.surfaceBg,
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppTheme.textMuted.withOpacity(0.2),
          ),
          boxShadow: isSelected
              ? AppTheme.glowShadow(AppTheme.primaryPurple)
              : AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Text(description,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
