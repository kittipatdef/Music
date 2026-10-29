import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist_model.dart';
import '../models/song_item.dart';
import 'id3_parser.dart';
import 'lyrics_parser.dart';

/// Service บันทึกและกู้คืนรายชื่อเพลงถาวร (Persistent Storage)
/// รองรับทั้ง Master Library, Now Playing Queue และ Multiple Custom Playlists
class PlaylistStorageService {
  static const String _keyPlaylist = 'saved_playlist_v1';
  static const String _keyMasterLibrary = 'saved_master_library_v1';
  static const String _keyCustomPlaylists = 'saved_custom_playlists_v1';
  static const String _keyLastSongId = 'saved_last_song_id';

  /// บันทึกรายการเพลงในคิวปัจจุบัน (Now Playing Queue)
  static Future<void> savePlaylist(List<SongItem> songs, {String? lastPlayedId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = songs.map((s) => s.toJson()).toList();
      await prefs.setString(_keyPlaylist, jsonEncode(jsonList));

      if (lastPlayedId != null) {
        await prefs.setString(_keyLastSongId, lastPlayedId);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error saving playlist: $e');
    }
  }

  /// โหลดรายการเพลงในคิวเดิม
  static Future<List<SongItem>> loadPlaylist() async {
    return _loadSongListByKey(_keyPlaylist);
  }

  /// บันทึกคลังเพลงหลักทั้งหมด (Master Library)
  static Future<void> saveMasterLibrary(List<SongItem> songs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = songs.map((s) => s.toJson()).toList();
      await prefs.setString(_keyMasterLibrary, jsonEncode(jsonList));
    } catch (e) {
      // ignore: avoid_print
      print('Error saving master library: $e');
    }
  }

  /// โหลดคลังเพลงหลักทั้งหมด (ถ้ายังไม่มี ให้ดึงจาก saved_playlist_v1 เดิมมาเริ่มต้น)
  static Future<List<SongItem>> loadMasterLibrary() async {
    final list = await _loadSongListByKey(_keyMasterLibrary);
    if (list.isNotEmpty) return list;

    // ถ้า master library ยังว่าง ให้เอาจาก playlist เดิมมาเป็นจุดเริ่มต้น
    final fallback = await loadPlaylist();
    if (fallback.isNotEmpty) {
      await saveMasterLibrary(fallback);
    }
    return fallback;
  }

  /// Helper โหลดและแปลง JSON เป็น List<SongItem> พร้อมคืนสภาพ Cover Art และ Lyrics
  static Future<List<SongItem>> _loadSongListByKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString(key);
      if (dataStr == null || dataStr.isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(dataStr);
      final List<SongItem> restored = [];

      for (var item in decoded) {
        if (item is Map<String, dynamic>) {
          var song = SongItem.fromJson(item);
          // ตรวจสอบว่าไฟล์เสียงยังคงมีอยู่ในเครื่องจริง
          if (!await File(song.audioPath).exists()) continue;

          // โหลดเนื้อเพลงกลับคืน
          if (song.lrcPath != null && await File(song.lrcPath!).exists()) {
            final lyrics = await LyricsParser.parseFile(song.lrcPath!);
            song = song.copyWith(lyrics: lyrics);
          }

          // โหลดภาพปก ID3 Album Art
          final cover = await Id3Parser.extractCoverArt(song.audioPath);
          if (cover != null) {
            song = song.copyWith(coverArt: cover);
          }

          restored.add(song);
        }
      }

      return restored;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading songs for $key: $e');
      return [];
    }
  }

  /// ดึง ID เพลงที่เคยเปิดฟังล่าสุด
  static Future<String?> getLastPlayedSongId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastSongId);
    } catch (_) {
      return null;
    }
  }

  // --- จัดการ Custom Playlists ---

  /// โหลดรายชื่อ Playlist ทั้งหมดที่ผู้ใช้สร้างไว้
  static Future<List<CustomPlaylist>> loadCustomPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString(_keyCustomPlaylists);
      if (dataStr == null || dataStr.isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(dataStr);
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => CustomPlaylist.fromJson(e))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('Error loading custom playlists: $e');
      return [];
    }
  }

  /// บันทึกรายชื่อ Playlist ทั้งหมด
  static Future<void> saveCustomPlaylists(List<CustomPlaylist> playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = playlists.map((p) => p.toJson()).toList();
      await prefs.setString(_keyCustomPlaylists, jsonEncode(jsonList));
    } catch (e) {
      // ignore: avoid_print
      print('Error saving custom playlists: $e');
    }
  }
}
