import 'dart:async';
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

  /// รายชื่อ Invidious API instances สำหรับสำรองเมื่อ YouTube Explode ติด Rate Limit หรือ PO Token
  static const List<String> _invidiousInstances = [
    'https://yt.chocolatemoo53.com',
    'https://inv.nadeko.net',
    'https://invidious.private.coffee',
    'https://iv.ggtyler.dev',
  ];

  /// ตรวจสอบว่าลิงก์เป็น YouTube หรือ Spotify หรือไม่
  static bool isSupportedUrl(String input) {
    final lower = input.trim().toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('spotify.com');
  }

  /// ดึง Video ID 11 ตัวอักษรจากลิงก์ YouTube
  static String? extractVideoId(String url) {
    final clean = url.trim();
    final match = RegExp(r'(?:v=|\/|youtu\.be\/|shorts\/)([0-9A-Za-z_-]{11})').firstMatch(clean);
    return match?.group(1);
  }

  /// ดึงข้อมูล Metadata จากลิงก์ (YouTube หรือ Spotify)
  static Future<TrackMeta> extractMetadata(String url) async {
    var cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    if (cleanUrl.contains('spotify.com')) {
      return await _extractSpotifyMeta(cleanUrl);
    } else {
      return await _extractYouTubeMeta(cleanUrl);
    }
  }

  /// แกะข้อมูลจากลิงก์ Spotify ผ่าน Public oEmbed & OpenGraph
  static Future<TrackMeta> _extractSpotifyMeta(String spotifyUrl) async {
    try {
      // ตัด query parameters เช่น ?si=... ออกเพื่อความสะอาด
      String targetUrl = spotifyUrl;
      try {
        final uri = Uri.parse(spotifyUrl);
        if (uri.hasQuery) {
          targetUrl = '${uri.scheme}://${uri.host}${uri.path}';
        }
      } catch (_) {}

      final oembedUrl =
          'https://open.spotify.com/oembed?url=${Uri.encodeComponent(targetUrl)}';
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

        if (bestVideo == null) {
          throw Exception('พบเพลงบน Spotify แต่ไม่พบคลิปเสียงที่ตรงกันบน YouTube');
        }

        return TrackMeta(
          title: title,
          artist: artist,
          coverUrl: coverUrl,
          youtubeVideoId: bestVideo.id.value,
        );
      } else if (response.statusCode == 404) {
        throw Exception('ไม่พบเพลงนี้บน Spotify (ลิงก์อาจไม่ถูกต้อง)');
      } else {
        throw Exception('ไม่สามารถดึงข้อมูลจาก Spotify ได้ (รหัส: ${response.statusCode})');
      }
    } on SocketException {
      throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ');
    } catch (e) {
      final str = e.toString().toLowerCase();
      if (str.contains('socket') || str.contains('failed host lookup')) {
        throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ');
      }
      if (e is Exception) {
        rethrow;
      }
      throw Exception('ไม่สามารถดึงข้อมูลจากลิงก์ Spotify นี้ได้: $e');
    }
  }

  /// ดึงข้อมูล Metadata จาก Invidious API (ช่องทางสำรอง)
  static Future<TrackMeta?> _extractMetaFromInvidious(String videoId) async {
    for (final base in _invidiousInstances) {
      try {
        final res = await http.get(Uri.parse('$base/api/v1/videos/$videoId')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final rawTitle = data['title'] as String? ?? 'Unknown Title';
          final author = data['author'] as String? ?? 'YouTube Artist';
          final thumbnails = data['videoThumbnails'] as List?;
          String? coverUrl;
          if (thumbnails != null && thumbnails.isNotEmpty) {
            coverUrl = thumbnails.last['url'] as String?;
          }
          return TrackMeta(
            title: cleanSongTitle(rawTitle),
            artist: author.replaceAll(' - Topic', '').trim(),
            coverUrl: coverUrl,
            youtubeVideoId: videoId,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  /// แกะข้อมูลจากลิงก์ YouTube
  static Future<TrackMeta> _extractYouTubeMeta(String youtubeUrl) async {
    final videoId = extractVideoId(youtubeUrl);

    try {
      final video = await _yt.videos.get(youtubeUrl).timeout(const Duration(seconds: 8));
      final title = cleanSongTitle(video.title);
      final artist = video.author.replaceAll(' - Topic', '').trim();
      final coverUrl = video.thumbnails.highResUrl;

      return TrackMeta(
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        youtubeVideoId: video.id.value,
      );
    } catch (e) {
      // หากโดน Rate limit หรือล้มเหลว ให้ใช้ช่องทางสำรอง Invidious
      if (videoId != null) {
        final fallbackMeta = await _extractMetaFromInvidious(videoId);
        if (fallbackMeta != null) {
          return fallbackMeta;
        }
      }

      final str = e.toString().toLowerCase();
      if (str.contains('socket') || str.contains('failed host lookup')) {
        throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ');
      }
      if (str.contains('rate limit') || str.contains('requestlimitexceeded')) {
        throw Exception('YouTube จำกัดการเชื่อมต่อชั่วคราว กรุณารอสักครู่แล้วลองใหม่');
      }
      if (str.contains('unavailable') || str.contains('not found')) {
        throw Exception('วิดีโอนี้ไม่พร้อมใช้งาน (อาจถูกลบหรือเป็นวิดีโอส่วนตัว)');
      }
      if (e is Exception) {
        rethrow;
      }
      throw Exception('ไม่สามารถดึงข้อมูล YouTube ได้: $e');
    }
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

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${docsDir.path}/DownloadedMusic');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final safeFilename = sanitizeFilename('${meta.title} - ${meta.artist}');
      final audioFilePath = '${downloadDir.path}/$safeFilename.mp3';
      final audioFile = File(audioFilePath);

      bool downloadSuccess = false;
      Exception? lastDownloadError;

      // วิธีที่ 1: ลองดาวน์โหลดผ่าน YouTube Explode โดยตั้ง Timeout ป้องกันค้าง
      try {
        onProgress('กำลังเชื่อมต่อสตรีม YouTube...', 0.15);
        final manifest = await _yt.videos.streamsClient
            .getManifest(meta.youtubeVideoId!)
            .timeout(const Duration(seconds: 8));

        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        final totalBytes = audioStreamInfo.size.totalBytes;
        final totalMbStr = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

        onProgress('กำลังดาวน์โหลดเพลง ($totalMbStr MB)...', 0.2);

        final audioStream = _yt.videos.streamsClient.get(audioStreamInfo);
        final output = audioFile.openWrite();
        int receivedBytes = 0;

        // หาก 8 วินาทีแรกไม่มี chunk เข้ามา ให้ส่ง Error เพื่อสลับไปช่องทางสำรองทันที
        final timedStream = audioStream.timeout(
          const Duration(seconds: 8),
          onTimeout: (sink) => sink.addError(TimeoutException('YouTube stream timed out')),
        );

        await for (final chunk in timedStream) {
          output.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final progress = 0.2 + (receivedBytes / totalBytes) * 0.5;
            final currentMbStr = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            onProgress('กำลังดาวน์โหลด: ${(receivedBytes / totalBytes * 100).toInt()}% ($currentMbStr / $totalMbStr MB)', progress);
          }
        }

        await output.flush();
        await output.close();

        if (receivedBytes > 10000) {
          downloadSuccess = true;
        }
      } catch (e) {
        lastDownloadError = Exception(e.toString());
      }

      // วิธีที่ 2: หากวิธีแรกติดบล็อก/Rate Limit/Timeout ให้สลับไปช่องทางสำรอง Invidious ทันที
      if (!downloadSuccess) {
        onProgress('สลับไปใช้ช่องทางดาวน์โหลดสำรองความเร็วสูง...', 0.22);
        downloadSuccess = await _downloadViaFallbackInstances(
          meta.youtubeVideoId!,
          audioFile,
          onProgress,
        );
      }

      if (!downloadSuccess) {
        throw lastDownloadError ?? Exception('ไม่สามารถดาวน์โหลดไฟล์เสียงจากคลิปนี้ได้ กรุณาลองใหม่อีกครั้ง');
      }

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
    } on SocketException {
      throw Exception('ขาดการเชื่อมต่ออินเทอร์เน็ตระหว่างดาวน์โหลด');
    } catch (e) {
      final str = e.toString().toLowerCase();
      if (str.contains('socket') || str.contains('failed host lookup') || str.contains('connection closed')) {
        throw Exception('ขาดการเชื่อมต่ออินเทอร์เน็ตระหว่างดาวน์โหลด');
      }
      if (e is Exception) {
        rethrow;
      }
      throw Exception('เกิดข้อผิดพลาดระหว่างดาวน์โหลด: $e');
    }
  }

  /// ดาวน์โหลดสตรีมเสียงผ่าน Invidious Instances (สำรอง)
  static Future<bool> _downloadViaFallbackInstances(
    String videoId,
    File destinationFile,
    Function(String status, double progress) onProgress,
  ) async {
    for (final base in _invidiousInstances) {
      try {
        final res = await http.get(Uri.parse('$base/api/v1/videos/$videoId')).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final formats = (data['adaptiveFormats'] as List?)
              ?.where((f) => (f['type'] as String? ?? '').startsWith('audio/'))
              .toList();

          if (formats != null && formats.isNotEmpty) {
            // เรียงลำดับเอา Bitrate ที่เหมาะสมที่สุด
            formats.sort((a, b) {
              final bitA = int.tryParse(a['bitrate']?.toString() ?? '0') ?? 0;
              final bitB = int.tryParse(b['bitrate']?.toString() ?? '0') ?? 0;
              return bitB.compareTo(bitA);
            });

            final bestAudio = formats.first;
            final audioUrl = bestAudio['url'] as String?;
            if (audioUrl == null || audioUrl.isEmpty) continue;

            final totalSize = int.tryParse(bestAudio['clen']?.toString() ?? '');

            final client = http.Client();
            final req = http.Request('GET', Uri.parse(audioUrl));
            req.headers['User-Agent'] = 'Mozilla/5.0';

            final streamedRes = await client.send(req).timeout(const Duration(seconds: 10));
            if (streamedRes.statusCode == 200 || streamedRes.statusCode == 206) {
              final expectedBytes = streamedRes.contentLength ?? totalSize ?? 0;
              final totalMbStr = expectedBytes > 0
                  ? (expectedBytes / (1024 * 1024)).toStringAsFixed(1)
                  : '';

              final output = destinationFile.openWrite();
              int receivedBytes = 0;

              await for (final chunk in streamedRes.stream) {
                output.add(chunk);
                receivedBytes += chunk.length;
                if (expectedBytes > 0) {
                  final progress = 0.2 + (receivedBytes / expectedBytes) * 0.5;
                  final currentMbStr = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
                  onProgress('กำลังดาวน์โหลด: ${(receivedBytes / expectedBytes * 100).toInt()}% ($currentMbStr / $totalMbStr MB)', progress);
                } else {
                  onProgress('กำลังดาวน์โหลด: ${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB', 0.45);
                }
              }

              await output.flush();
              await output.close();
              client.close();

              if (receivedBytes > 10000) {
                return true;
              }
            }
          }
        }
      } catch (_) {}
    }
    return false;
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
