import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_item.dart';
import 'id3_parser.dart';
import 'lyrics_parser.dart';

/// Service บันทึกและกู้คืนรายชื่อเพลงถาวร (Persistent Storage)
class PlaylistStorageService {
  static const String _keyPlaylist = 'saved_playlist_v1';
  static const String _keyLastSongId = 'saved_last_song_id';

  /// บันทึกรายการเพลงทั้งหมดลงในเครื่อง
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

  /// โหลดรายการเพลงเดิมที่เคยบันทึกไว้กลับมา พร้อมโหลดเนื้อเพลงและภาพปก
  static Future<List<SongItem>> loadPlaylist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString(_keyPlaylist);
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
      print('Error loading playlist: $e');
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
}
