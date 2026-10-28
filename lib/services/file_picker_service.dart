import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/lyric_entry.dart';
import '../models/song_item.dart';
import 'lyrics_parser.dart';

/// Service สำหรับขอสิทธิ์ และเลือกไฟล์เสียง/ไฟล์เนื้อเพลงจากเครื่อง
class FilePickerService {
  /// ขอสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูลและแจ้งเตือนสำหรับ Android
  static Future<bool> requestPermissions() async {
    // ขอสิทธิ์แสดงแถบแจ้งเตือน Notification (สำหรับ Android 13+)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // ขอสิทธิ์อ่านไฟล์เสียง/ไฟล์ในเครื่อง
    if (Platform.isAndroid) {
      // ตรวจสอบ Android 13+ (Audio) หรือเวอร์ชันเก่า (Storage)
      if (await Permission.audio.status.isGranted ||
          await Permission.storage.status.isGranted) {
        return true;
      }

      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;

      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }

  /// เลือกไฟล์เพลง (.mp3, .wav, .m4a, .flac) และค้นหาไฟล์ .lrc คู่กันอัตโนมัติ
  static Future<List<SongItem>> pickAudioFiles() async {
    await requestPermissions();

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'flac'],
    );

    if (files.isEmpty) return [];

    final List<SongItem> songs = [];

    for (var file in files) {
      if (file.path == null) continue;

      final audioPath = file.path!;
      final filename = file.name;
      // ลบนามสกุลไฟล์ออกเพื่อใช้เป็นชื่อเพลงเริ่มต้น
      final title = filename.contains('.')
          ? filename.substring(0, filename.lastIndexOf('.'))
          : filename;

      // ตรวจสอบว่าในโฟลเดอร์เดียวกัน มีไฟล์ .lrc ที่ชื่อเดียวกันหรือไม่ (Auto-pairing)
      final autoLrcPath = _findMatchingLrcPath(audioPath);
      var lyrics = <LyricEntry>[];
      String? matchedLrcPath;

      if (autoLrcPath != null && await File(autoLrcPath).exists()) {
        matchedLrcPath = autoLrcPath;
        lyrics = await LyricsParser.parseFile(autoLrcPath);
      }

      songs.add(
        SongItem(
          id: audioPath,
          title: title,
          artist: 'Offline Audio',
          audioPath: audioPath,
          lrcPath: matchedLrcPath,
          lyrics: lyrics,
        ),
      );
    }

    return songs;
  }

  /// เลือกไฟล์ .lrc เฉพาะเจาะจงเพื่อนำมาจับคู่กับเพลงที่เลือก
  static Future<String?> pickLrcFile() async {
    await requestPermissions();

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );

    if (files.isEmpty) return null;
    return files.first.path;
  }

  /// ค้นหาไฟล์ .lrc ชื่อเดียวกับไฟล์เสียงในโฟลเดอร์เดียวกัน
  static String? _findMatchingLrcPath(String audioPath) {
    final dotIndex = audioPath.lastIndexOf('.');
    if (dotIndex != -1) {
      return '${audioPath.substring(0, dotIndex)}.lrc';
    }
    return null;
  }
}
