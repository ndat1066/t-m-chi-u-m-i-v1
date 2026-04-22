import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/profile_service.dart';
import '../services/video_service.dart';
import '../utils/app_theme.dart';
import '../widgets/shared_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<VideoItem> _allVideos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile = await ProfileService().loadProfile();
      final videos = await VideoService().fetchVideos();
      if (mounted) {
        setState(() {
          _profile = profile;
          _allVideos = videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _profile = UserProfile.defaultProfile;
          _isLoading = false;
        });
      }
    }
  }

  List<VideoItem> get _watchedVideos {
    if (_profile == null) return [];
    
    return _allVideos
        .where((v) => _profile!.watchedVideoIds.contains(v.id)) 
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const GradientBackground(
        child: Center(
          child:
              CircularProgressIndicator(color: AppTheme.primaryPurple),
        ),
      );
    }

    final profile = _profile!;
    return GradientBackground(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildProfileHero(profile)),
            SliverToBoxAdapter(child: _buildStatsRow(profile)),
            SliverToBoxAdapter(child: _buildWatchedVideos()),
            SliverToBoxAdapter(child: _buildPatternHistory(profile)),
            SliverToBoxAdapter(
                child: _buildSettingsSection(profile)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHero(UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: GlassCard(
        gradient: AppTheme.primaryGradient,
        boxShadow: AppTheme.glowShadow(AppTheme.primaryPurple, blur: 30),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
                border: Border.all(
                    color: Colors.white.withOpacity(0.4), width: 2),
              ),
              child: Center(
                child: Text(
                  profile.avatarEmoji,
                  style: const TextStyle(fontSize: 36),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: AppTheme.radiusSM,
                        ),
                        child: Text(
                          '⭐ ${profile.levelTitle}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Cấp ${profile.level}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // XP Progress bar
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(6)),
                    child: LinearProgressIndicator(
                      value: (profile.totalMinutes % 50) / 50,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation(
                          AppTheme.accentYellow),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.totalMinutes % 60}/60 phút đến cấp tiếp theo',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
              child: _StatCard(
            icon: '⏱️',
            label: 'Thời gian dùng',
            value: profile.usageTimeFormatted,
            color: AppTheme.accentBlue,
          )),
          const SizedBox(width: 12),
          Expanded(
              child: _StatCard(
            icon: '🎬',
            label: 'Video đã xem',
            value: '${_watchedVideos.length}',
            color: AppTheme.accentOrange,
          )),
          const SizedBox(width: 12),
          Expanded(
              child: _StatCard(
            icon: '🧵',
            label: 'Mẫu đã dệt',
            value: '${profile.patternHistory.length}',
            color: AppTheme.success,
          )),
        ],
      ),
    );
  }

  Widget _buildWatchedVideos() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Video đã xem (offline)',
            subtitle: '${_watchedVideos.length} video',
            trailing: const ChipBadge(
                label: '📥 Đã tải', color: AppTheme.success),
          ),
          const SizedBox(height: 12),
          if (_watchedVideos.isEmpty)
            const GlassCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Text('📭', style: TextStyle(fontSize: 32)),
                      SizedBox(height: 8),
                      Text(
                        'Chưa có video nào được xem',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...(_watchedVideos
                .take(3)
                .map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Text('▶️',
                                style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    v.title,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    v.durationFormatted,
                                    style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            ChipBadge(
                                label: v.category,
                                color: AppTheme.accentBlue),
                          ],
                        ),
                      ),
                    ))
                .toList()),
        ],
      ),
    );
  }

  Widget _buildPatternHistory(UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Lịch sử mẫu dệt',
            subtitle: '${profile.patternHistory.length} mẫu',
          ),
          const SizedBox(height: 12),
          if (profile.patternHistory.isEmpty)
            const GlassCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Text('🧵', style: TextStyle(fontSize: 32)),
                      SizedBox(height: 8),
                      Text(
                        'Chưa dệt mẫu nào',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            GlassCard(
              child: Column(
                children: profile.patternHistory
                    .take(5)
                    .toList()
                    .asMap()
                    .entries
                    .map((e) => Padding(
                          padding: EdgeInsets.only(
                              bottom: e.key <
                                      (profile.patternHistory.length
                                              .clamp(0, 5) -
                                          1)
                                  ? 12
                                  : 0),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: e.key == 0
                                      ? AppTheme.warmGradient
                                      : AppTheme.primaryGradient,
                                  borderRadius: AppTheme.radiusSM,
                                ),
                                child: const Center(
                                  child: Text('🧵',
                                      style: TextStyle(fontSize: 14)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (e.key == 0)
                                const ChipBadge(
                                    label: 'Gần nhất',
                                    color: AppTheme.accentYellow),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Cài đặt'),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.wifi,
                  label: 'Địa chỉ ESP32',
                  subtitle: AppConstants.esp32BaseUrl,
                  onTap: () => _showEsp32Dialog(context),
                ),
                const Divider(color: AppTheme.cardBg, height: 1),
                _SettingsTile(
                  icon: Icons.delete_outline,
                  label: 'Xóa dữ liệu cache',
                  subtitle: 'Xóa video tải xuống',
                  iconColor: AppTheme.error,
                  onTap: () {},
                ),
                const Divider(color: AppTheme.cardBg, height: 1),
                _SettingsTile(
                  icon: Icons.info_outline,
                  label: 'Về ứng dụng',
                  subtitle: 'Tấm chiếu mới v1.0.0',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEsp32Dialog(BuildContext context) {
    final controller =
        TextEditingController(text: AppConstants.esp32BaseUrl);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusLG),
        title: const Text('Cài đặt kết nối ESP32',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'URL (vd: http://192.168.1.100)',
            labelStyle: TextStyle(color: AppTheme.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.lightPurple),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('✅ Đã lưu địa chỉ ESP32')),
              );
            },
            child: const Text('Lưu',
                style: TextStyle(color: AppTheme.primaryPurple)),
          ),
        ],
      ),
    );
  }
}

// ── Stat Card ──────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── Settings Tile ──────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor = const Color.fromARGB(255, 215, 94, 1),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: AppTheme.radiusSM,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
