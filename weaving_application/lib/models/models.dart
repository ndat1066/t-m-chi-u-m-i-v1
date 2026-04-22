class WeavingPattern {
  final String id;
  final String name;
  final String imagePath;
  final String description;

  const WeavingPattern({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.description,
  });

  static const List<WeavingPattern> defaults = [
    WeavingPattern(
      id: 'pattern_a',
      name: 'Mẫu A',
      imagePath: 'assets/images/patterns/pattern_a.png',
      description: 'Họa tiết caro truyền thống, mang ý nghĩa may mắn và sung túc',
    ),
    WeavingPattern(
      id: 'pattern_b',
      name: 'Mẫu B',
      imagePath: 'assets/images/patterns/pattern_b.png',
      description: 'Họa tiết Sắc xanh tím thanh lịch, dệt sọc ngang hiện đại và tinh tế',
    ),
    WeavingPattern(
      id: 'pattern_c',
      name: 'Mẫu C',
      imagePath: 'assets/images/patterns/pattern_c.png',
      description: 'Sọc đứng phối màu tím vàng, phong cách truyền thống Nam Bộ',
    ),
  ];
}

// ─── Lever Model ──────────────────────────────────────────────────────────────
/*class LeverState {
  final int index;
  bool isOn;
  bool isEnabled;

  LeverState({
    required this.index,
    this.isOn = false,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'state': isOn ? 1 : 0,
      };
}
*/

class LeverState {
  final int index;
  bool isOn;
  bool isEnabled;

  LeverState({
    required this.index,
    this.isOn = false,
    this.isEnabled = true,
  });
}

// ─── Machine Command ──────────────────────────────────────────────────────────
class MachineCommand {
  final String mode;
  final List<int> levers;

  MachineCommand({required this.mode, required this.levers});

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'levers': levers,
      };
}

// ─── Video Model ──────────────────────────────────────────────────────────────
class VideoItem {
  final String id;
  final String title;
  final String description;
  final String serverUrl;
  final String thumbnailUrl;
  final String category;
  final int durationSeconds;
  String? localPath;
  bool isDownloaded;
  double downloadProgress;

  VideoItem({
    required this.id,
    required this.title,
    required this.description,
    required this.serverUrl,
    required this.thumbnailUrl,
    required this.category,
    required this.durationSeconds,
    this.localPath,
    this.isDownloaded = false,
    this.downloadProgress = 0.0,
  });

factory VideoItem.fromJson(Map<String, dynamic> json) {
  return VideoItem(
    id: json['id'].toString(), // Đảm bảo ID luôn là String
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    serverUrl: json['server_url'] ?? '', // Khớp với JSON
    thumbnailUrl: json['thumbnail_url'] ?? '', // Khớp với JSON
    category: json['category'] ?? 'Chung',
    durationSeconds: int.tryParse(json['duration_seconds'].toString()) ?? 0,
  );
}

//factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
//      id: json['id'],
//      title: json['title'],
//     description: json['description'],
//      serverUrl: json['server_url'],
//      thumbnailUrl: json['thumbnail_url'],
//      category: json['category'] ?? 'Chung',
//      durationSeconds: json['duration_seconds'] ?? 0,
//    );

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ─── User Profile ─────────────────────────────────────────────────────────────
class UserProfile {
  String name;
  String avatarEmoji;
  int totalMinutes;
  int level;
  List<String> watchedVideoIds;
  List<String> patternHistory;

  UserProfile({
    required this.name,
    this.avatarEmoji = '🧵',
    this.totalMinutes = 0,
    this.level = 1,
    List<String>? watchedVideoIds,
    List<String>? patternHistory,
  })  : watchedVideoIds = watchedVideoIds ?? [],
        patternHistory = patternHistory ?? [];

  String get levelTitle {
    if (level < 3) return 'Học Viên';
    if (level < 6) return 'Thợ Dệt';
    if (level < 10) return 'Nghệ Nhân';
    return 'Bậc Thầy';
  }

  String get usageTimeFormatted {
    if (totalMinutes < 60) return '$totalMinutes phút';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}g ${m}p';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatarEmoji': avatarEmoji,
        'totalMinutes': totalMinutes,
        'level': level,
        'watchedVideoIds': watchedVideoIds,
        'patternHistory': patternHistory,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] ?? 'Người Dùng',
        avatarEmoji: json['avatarEmoji'] ?? '🧵',
        totalMinutes: json['totalMinutes'] ?? 0,
        level: json['level'] ?? 1,
        watchedVideoIds: List<String>.from(json['watchedVideoIds'] ?? []),
        patternHistory: List<String>.from(json['patternHistory'] ?? []),
      );

  static UserProfile get defaultProfile => UserProfile(
        name: 'Nguyễn Văn A',
        avatarEmoji: '🧵',
        totalMinutes: 142,
        level: 3,
        patternHistory: ['Mẫu A', 'Mẫu C', 'Mẫu B'],
      );
}
