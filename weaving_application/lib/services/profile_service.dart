import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  static const String _profileKey = 'user_profile';

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_profileKey);
    if (json == null) return UserProfile.defaultProfile;
    try {
      return UserProfile.fromJson(jsonDecode(json));
    } catch (_) {
      return UserProfile.defaultProfile;
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<void> addPatternToHistory(UserProfile profile, String patternName) async {
    if (!profile.patternHistory.contains(patternName)) {
      profile.patternHistory.insert(0, patternName);
      if (profile.patternHistory.length > 20) {
        profile.patternHistory.removeLast();
      }
    }
    await saveProfile(profile);
  }

  Future<void> addWatchedVideo(UserProfile profile, String videoId) async {
    if (!profile.watchedVideoIds.contains(videoId)) {
      profile.watchedVideoIds.insert(0, videoId);
    }
    await saveProfile(profile);
  }

  Future<void> addUsageTime(UserProfile profile, int minutes) async {
    profile.totalMinutes += minutes;
    // Level up every 50 minutes
    profile.level = (profile.totalMinutes ~/ 50) + 1;
    await saveProfile(profile);
  }
}
