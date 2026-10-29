import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/lyric_entry.dart';
import '../models/song_item.dart';
import 'lyrics_parser.dart';

/// ข้อมูลเบื้องต้นของเพลงที่แกะได้จากลิงก์
class TrackMeta {
  final String title;
  final String artist;
  final String? coverUrl;
  final String? youtubeVideoId;

  TrackMeta({
    required this.title,
    required this.artist,
    this.coverUrl,
    this.youtubeVideoId,
  });
}

/// Service สำหรับดาวน์โหลดเพลงจาก YouTube และ Spotify พร้อมดึงเนื้อเพลง .lrc
class OnlineDownloaderService {
  static final YoutubeExplode _yt = YoutubeExplode();

  /// ตรวจสอบว่าลิงก์เป็น YouTube หรือ Spotify หรือไม่
  static bool isSupportedUrl(String input) {
    final lower = input.trim().toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('spotify.com');
  }

  /// ดึงข้อมูล Metadata จากลิงก์ (YouTube หรือ Spotify)
  static Future<TrackMeta> extractMetadata(String url) async {
    final cleanUrl = url.trim();

    if (cleanUrl.contains('spotify.com')) {
      return await _extractSpotifyMeta(cleanUrl);
    } else {
      return await _extractYouTubeMeta(cleanUrl);
    }
  }

  /// แกะข้อมูลจากลิงก์ Spotify ผ่าน Public oEmbed & OpenGraph
  static Future<TrackMeta> _extractSpotifyMeta(String spotifyUrl) async {
    try {
      final oembedUrl =
          'https://open.spotify.com/oembed?url=${Uri.encodeComponent(spotifyUrl)}';
      final response = await http.get(Uri.parse(oembedUrl)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawTitle = data['title'] as String? ?? 'Unknown Title';
        final coverUrl = data['thumbnail_url'] as String?;

        // Spotify oEmbed มักคืนค่า format: "Song Name" หรือ "Song Name by Artist Name"
        String title = rawTitle;
        String artist = 'Spotify Artist';

        if (rawTitle.contains(' by ')) {
          final parts = rawTitle.split(' by ');
          title = parts[0].trim();
          artist = parts.sublist(1).join(' by ').trim();
        }

        // ค้นหา YouTube Video ID ที่ตรงกับเพลงนี้
        final searchQuery = '$title $artist audio';
        final searchResults = await _yt.search.search(searchQuery);
        final bestVideo = searchResults.firstOrNull;

        return TrackMeta(
          title: title,
          artist: artist,
          coverUrl: coverUrl,
          youtubeVideoId: bestVideo?.id.value,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('Spotify metadata extraction error: $e');
    }

    throw Exception('ไม่สามารถดึงข้อมูลจากลิงก์ Spotify นี้ได้');
  }

  /// แกะข้อมูลจากลิงก์ YouTube
  static Future<TrackMeta> _extractYouTubeMeta(String youtubeUrl) async {
    final video = await _yt.videos.get(youtubeUrl);
    final title = cleanSongTitle(video.title);
    final artist = video.author.replaceAll(' - Topic', '').trim();
    final coverUrl = video.thumbnails.highResUrl;

    return TrackMeta(
      title: title,
      artist: artist,
      coverUrl: coverUrl,
      youtubeVideoId: video.id.value,
    );
  }

  /// ดาวน์โหลดเพลงและเนื้อเพลงซิงค์ (.lrc)
  static Future<SongItem> downloadTrack(
    TrackMeta meta, {
    required Function(String status, double progress) onProgress,
  }) async {
    if (meta.youtubeVideoId == null) {
      throw Exception('ไม่พบแหล่งไฟล์เสียงสำหรับเพลงนี้');
    }

    onProgress('กำลังเตรียมดาวน์โหลดไฟล์เสียง...', 0.1);

    // 1. ดึง Audio Stream Manifest จาก YouTube
    final manifest =
        await _yt.videos.streamsClient.getManifest(meta.youtubeVideoId!);
    final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

    final docsDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${docsDir.path}/DownloadedMusic');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final safeFilename = sanitizeFilename('${meta.title} - ${meta.artist}');
    final audioFilePath = '${downloadDir.path}/$safeFilename.mp3';
    final audioFile = File(audioFilePath);

    // 2. ดาวน์โหลดสตรีมเสียงพร้อมรายงานความคืบหน้า
    final audioStream = _yt.videos.streamsClient.get(audioStreamInfo);
    final output = audioFile.openWrite();

    int totalBytes = audioStreamInfo.size.totalBytes;
    int receivedBytes = 0;

    onProgress('กำลังดาวน์โหลดเพลง (${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB)...', 0.2);

    await for (final chunk in audioStream) {
      output.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        final progress = 0.2 + (receivedBytes / totalBytes) * 0.5; // 0.2 ถึง 0.7
        onProgress('กำลังดาวน์โหลด: ${(receivedBytes / totalBytes * 100).toInt()}%', progress);
      }
    }
    await output.flush();
    await output.close();

    // 3. ดึงเนื้อเพลงซิงค์ .lrc จาก LRCLIB
    onProgress('กำลังค้นหาเนื้อเพลงซิงค์ (.lrc)...', 0.75);
    List<LyricEntry> lyrics = [];
    String? lrcFilePath;

    final lrcContent = await _fetchSyncedLyricsFromLrclib(meta.title, meta.artist);
    if (lrcContent != null && lrcContent.isNotEmpty) {
      lrcFilePath = '${downloadDir.path}/$safeFilename.lrc';
      await File(lrcFilePath).writeAsString(lrcContent);
      lyrics = LyricsParser.parse(lrcContent);
      onProgress('พบเนื้อเพลงซิงค์สำเร็จ (${lyrics.length} บรรทัด)', 0.85);
    } else {
      onProgress('ไม่พบเนื้อเพลงซิงค์สำหรับเพลงนี้', 0.85);
    }

    // 4. ดาวน์โหลดภาพปกอัลบั้ม
    Uint8List? coverBytes;
    if (meta.coverUrl != null && meta.coverUrl!.isNotEmpty) {
      onProgress('กำลังโหลดภาพปกอัลบั้ม...', 0.9);
      try {
        final imgRes = await http.get(Uri.parse(meta.coverUrl!)).timeout(
              const Duration(seconds: 10),
            );
        if (imgRes.statusCode == 200) {
          coverBytes = imgRes.bodyBytes;
        }
      } catch (_) {}
    }

    onProgress('เสร็จสมบูรณ์!', 1.0);

    return SongItem(
      id: audioFilePath,
      title: meta.title,
      artist: meta.artist,
      audioPath: audioFilePath,
      lrcPath: lrcFilePath,
      lyrics: lyrics,
      coverArt: coverBytes,
    );
  }

  /// ค้นหาและดึงเนื้อเพลง .lrc จาก LRCLIB API
  static Future<String?> _fetchSyncedLyricsFromLrclib(
      String title, String artist) async {
    try {
      // ลองค้นหาแบบ Direct match ก่อน
      final directUri = Uri.parse(
        'https://lrclib.net/api/get?track_name=${Uri.encodeComponent(title)}&artist_name=${Uri.encodeComponent(artist)}',
      );
      var response = await http.get(directUri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final synced = data['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) {
          return synced;
        }
      }

      // ถ้าไม่พบ ลองค้นหาผ่าน Search API
      final searchUri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent('$title $artist')}',
      );
      response = await http.get(searchUri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        for (var item in list) {
          final synced = item['syncedLyrics'] as String?;
          if (synced != null && synced.trim().isNotEmpty) {
            return synced;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// ลบคำฟุ่มเฟือยออกจากชื่อคลิป YouTube เช่น (Official Music Video), [Audio], 4K
  static String cleanSongTitle(String title) {
    var cleaned = title;
    cleaned = cleaned.replaceAll(RegExp(r'\[.*?\]'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'\((Official\s*.*|Audio|Video|Lyric\s*Video|MV|HD|4K)\)',
          caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'(Official\s*Music\s*Video|Official\s*Audio|Official\s*Lyric\s*Video|Lyric\s*Video)',
          caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }

  /// กำจัดอักขระต้องห้ามสำหรับชื่อไฟล์บนระบบปฏิบัติการ
  static String sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
