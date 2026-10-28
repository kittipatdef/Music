import 'package:audio_service/audio_service.dart';
import 'lyric_entry.dart';

/// โมเดลข้อมูลเพลงภายในเครื่อง
class SongItem {
  final String id;
  final String title;
  final String artist;
  final String audioPath;
  final String? lrcPath;
  final Duration? duration;
  final List<LyricEntry> lyrics;

  SongItem({
    required this.id,
    required this.title,
    this.artist = 'Unknown Artist',
    required this.audioPath,
    this.lrcPath,
    this.duration,
    this.lyrics = const [],
  });

  /// คัดลอกและอัปเดตข้อมูลบางส่วน (เช่น เพิ่ม lyrics ทีหลัง)
  SongItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? audioPath,
    String? lrcPath,
    Duration? duration,
    List<LyricEntry>? lyrics,
  }) {
    return SongItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      audioPath: audioPath ?? this.audioPath,
      lrcPath: lrcPath ?? this.lrcPath,
      duration: duration ?? this.duration,
      lyrics: lyrics ?? this.lyrics,
    );
  }

  /// แปลงเป็น MediaItem สำหรับใช้กับ AudioService (แสดงผลบน Lock Screen & Notification)
  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      album: 'Local Storage',
      title: title,
      artist: artist,
      duration: duration,
      extras: {
        'audioPath': audioPath,
        'lrcPath': lrcPath,
      },
    );
  }
}
