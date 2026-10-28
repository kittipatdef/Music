import 'dart:typed_data';
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
  final Uint8List? coverArt;

  SongItem({
    required this.id,
    required this.title,
    this.artist = 'Unknown Artist',
    required this.audioPath,
    this.lrcPath,
    this.duration,
    this.lyrics = const [],
    this.coverArt,
  });

  /// คัดลอกและอัปเดตข้อมูลบางส่วน
  SongItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? audioPath,
    String? lrcPath,
    Duration? duration,
    List<LyricEntry>? lyrics,
    Uint8List? coverArt,
  }) {
    return SongItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      audioPath: audioPath ?? this.audioPath,
      lrcPath: lrcPath ?? this.lrcPath,
      duration: duration ?? this.duration,
      lyrics: lyrics ?? this.lyrics,
      coverArt: coverArt ?? this.coverArt,
    );
  }

  /// แปลงเป็น MediaItem สำหรับใช้กับ AudioService (แสดงผลบน Lock Screen & Notification)
  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      album: 'Offline Music',
      title: title,
      artist: artist,
      duration: duration,
      extras: {
        'audioPath': audioPath,
        'lrcPath': lrcPath,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'audioPath': audioPath,
      'lrcPath': lrcPath,
    };
  }

  factory SongItem.fromJson(Map<String, dynamic> json) {
    return SongItem(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: (json['artist'] as String?) ?? 'Unknown Artist',
      audioPath: json['audioPath'] as String,
      lrcPath: json['lrcPath'] as String?,
    );
  }
}
