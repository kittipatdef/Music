import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/lyric_entry.dart';
import '../models/song_item.dart';
import 'lyrics_parser.dart';

/// ข้อมูลเบื้องต้นของเพลงที่แกะได้จากลิงก์ YouTube
class TrackMeta {
  final String title;
  final String artist;
  final String? coverUrl;
  final String youtubeVideoId;

  TrackMeta({
    required this.title,
    required this.artist,
    this.coverUrl,
    required this.youtubeVideoId,
  });
}

/// Service สำหรับดาวน์โหลดเพลงจาก YouTube พร้อมดึงเนื้อเพลงซิงค์ .lrc ด้วยความเร็วสูงพิเศษ
class OnlineDownloaderService {
  static final YoutubeExplode _yt = YoutubeExplode();

  /// รายชื่อ Invidious API instances สำหรับสำรองข้อมูล Metadata เมื่อ YouTube ติด rate limit
  static const List<String> _invidiousInstances = [
    'https://yt.chocolatemoo53.com',
    'https://inv.nadeko.net',
    'https://invidious.private.coffee',
  ];

  /// ตรวจสอบว่าลิงก์เป็น YouTube หรือไม่
  static bool isSupportedUrl(String input) {
    final lower = input.trim().toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  /// ดึง Video ID 11 ตัวอักษรจากลิงก์ YouTube
  static String? extractVideoId(String url) {
    final clean = url.trim();
    final match = RegExp(r'(?:v=|\/|youtu\.be\/|shorts\/)([0-9A-Za-z_-]{11})').firstMatch(clean);
    return match?.group(1);
  }

  /// ดึงข้อมูล Metadata จากลิงก์ YouTube อย่างรวดเร็ว
  static Future<TrackMeta> extractMetadata(String url) async {
    var cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    final videoId = extractVideoId(cleanUrl);
    if (videoId == null) {
      throw Exception('ลิงก์ YouTube ไม่ถูกต้อง ไม่พบรหัสวิดีโอ');
    }

    // 1. ดึงข้อมูลจาก YouTube Explode โดยตรงก่อน (เร็วที่สุดและสดใหม่)
    try {
      final video = await _yt.videos.get(videoId).timeout(const Duration(seconds: 5));
      final cleanedTitle = cleanSongTitle(video.title);
      var artist = video.author.replaceAll(' - Topic', '').replaceAll('VEVO', '').trim();
      var title = cleanedTitle;

      // ถ้าชื่อคลิปบน YouTube มีรูปแบบ "Artist - Title" หรือ "Artist – Title" ให้แยกเพลงและศิลปินออกจากกัน
      if (cleanedTitle.contains(' - ') || cleanedTitle.contains(' – ')) {
        final parts = cleanedTitle.contains(' - ') ? cleanedTitle.split(' - ') : cleanedTitle.split(' – ');
        if (parts.length >= 2) {
          final possibleArtist = parts[0].trim();
          final possibleTitle = parts.sublist(1).join(' - ').trim();
          if (possibleArtist.isNotEmpty && possibleTitle.isNotEmpty) {
            artist = possibleArtist;
            title = possibleTitle;
          }
        }
      }

      final coverUrl = video.thumbnails.highResUrl;

      return TrackMeta(
        title: title,
        artist: artist.isNotEmpty ? artist : 'Unknown Artist',
        coverUrl: coverUrl,
        youtubeVideoId: video.id.value,
      );
    } catch (e) {
      final str = e.toString().toLowerCase();
      if (str.contains('socket') || str.contains('failed host lookup')) {
        throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ');
      }
      if (str.contains('unavailable') || str.contains('not found')) {
        throw Exception('วิดีโอนี้ไม่พร้อมใช้งาน (อาจถูกลบหรือเป็นวิดีโอส่วนตัว)');
      }
    }

    // 2. หาก YouTube ติด Rate Limit ให้ดึงข้อมูลผ่าน Invidious API สำรอง
    for (final base in _invidiousInstances) {
      try {
        final res = await http.get(Uri.parse('$base/api/v1/videos/$videoId')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final rawTitle = data['title'] as String? ?? 'YouTube Audio';
          final author = data['author'] as String? ?? 'Artist';
          final thumbnails = data['videoThumbnails'] as List?;
          String? coverUrl;
          if (thumbnails != null && thumbnails.isNotEmpty) {
            coverUrl = thumbnails.last['url'] as String?;
          }

          final cleanedTitle = cleanSongTitle(rawTitle);
          var artist = author.replaceAll(' - Topic', '').replaceAll('VEVO', '').trim();
          var title = cleanedTitle;

          if (cleanedTitle.contains(' - ') || cleanedTitle.contains(' – ')) {
            final parts = cleanedTitle.contains(' - ') ? cleanedTitle.split(' - ') : cleanedTitle.split(' – ');
            if (parts.length >= 2) {
              final possibleArtist = parts[0].trim();
              final possibleTitle = parts.sublist(1).join(' - ').trim();
              if (possibleArtist.isNotEmpty && possibleTitle.isNotEmpty) {
                artist = possibleArtist;
                title = possibleTitle;
              }
            }
          }

          return TrackMeta(
            title: title,
            artist: artist.isNotEmpty ? artist : 'Unknown Artist',
            coverUrl: coverUrl,
            youtubeVideoId: videoId,
          );
        }
      } catch (_) {}
    }

    throw Exception('ไม่สามารถดึงข้อมูลเพลงได้ กรุณาตรวจสอบลิงก์แล้วลองใหม่อีกครั้ง');
  }

  /// ดาวน์โหลดเพลงและเนื้อเพลงซิงค์ (.lrc) ด้วยความเร็วสูงพิเศษ
  static Future<SongItem> downloadTrack(
    TrackMeta meta, {
    required Function(String status, double progress) onProgress,
  }) async {
    onProgress('กำลังเตรียมดาวน์โหลดไฟล์เสียง...', 0.05);

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${docsDir.path}/DownloadedMusic');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final safeFilename = sanitizeFilename('${meta.title} - ${meta.artist}');
      final audioFilePath = '${downloadDir.path}/$safeFilename.m4a';
      final audioFile = File(audioFilePath);

      // 1. สตรีมดาวน์โหลดไฟล์เสียงความเร็วสูงแบบ Multi-threaded
      final downloadOk = await _downloadBestAudioStream(
        meta: meta,
        destinationFile: audioFile,
        onProgress: onProgress,
      );

      if (!downloadOk) {
        throw Exception('ไม่สามารถดาวน์โหลดไฟล์เสียงได้ กรุณาลองใหม่อีกครั้ง');
      }

      // 2. ดึงเนื้อเพลงซิงค์ .lrc จาก LRCLIB
      onProgress('กำลังค้นหาเนื้อเพลงซิงค์ (.lrc)...', 0.85);
      List<LyricEntry> lyrics = [];
      String? lrcFilePath;

      final lrcContent = await _fetchSyncedLyricsFromLrclib(meta.title, meta.artist);
      if (lrcContent != null && lrcContent.isNotEmpty) {
        lrcFilePath = '${downloadDir.path}/$safeFilename.lrc';
        await File(lrcFilePath).writeAsString(lrcContent);
        lyrics = LyricsParser.parse(lrcContent);
        onProgress('พบเนื้อเพลงซิงค์สำเร็จ (${lyrics.length} บรรทัด)', 0.92);
      } else {
        onProgress('ไม่พบเนื้อเพลงซิงค์สำหรับเพลงนี้', 0.92);
      }

      // 3. ดาวน์โหลดภาพปกอัลบั้ม
      Uint8List? coverBytes;
      if (meta.coverUrl != null && meta.coverUrl!.isNotEmpty) {
        onProgress('กำลังโหลดภาพปกอัลบั้ม...', 0.96);
        try {
          final imgRes = await http.get(Uri.parse(meta.coverUrl!)).timeout(
                const Duration(seconds: 6),
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

  /// ค้นหาและดาวน์โหลดสตรีมเสียงที่ดีที่สุด (Tag 18 MP4 AAC หรือ Audio-only พร้อมระบบ Fallback อัตโนมัติ)
  static Future<bool> _downloadBestAudioStream({
    required TrackMeta meta,
    required File destinationFile,
    required Function(String status, double progress) onProgress,
  }) async {
    // 1. ลองดาวน์โหลดจาก Video ID หลักก่อน
    final ok = await _tryDownloadVideoId(
      videoId: meta.youtubeVideoId,
      destinationFile: destinationFile,
      onProgress: onProgress,
    );
    if (ok) return true;

    // 2. ถ้าคลิปหลักมีข้อจำกัดด้านลิขสิทธิ์ (เช่น VEVO หรือบล็อก Range) ให้ใช้ Smart Fallback
    onProgress('กำลังค้นหาเวอร์ชันเสียงสำรองคุณภาพสูง...', 0.15);
    try {
      final query = '${meta.title} ${meta.artist} audio';
      final searchResults = await _yt.search.search(query).timeout(const Duration(seconds: 5));
      for (final result in searchResults.take(4)) {
        if (result.id.value == meta.youtubeVideoId) continue;
        final fallbackOk = await _tryDownloadVideoId(
          videoId: result.id.value,
          destinationFile: destinationFile,
          onProgress: onProgress,
        );
        if (fallbackOk) return true;
      }
    } catch (_) {}

    return false;
  }

  /// พยายามดึง Manifest และสตรีมดาวน์โหลดจาก Video ID ที่ระบุ
  static Future<bool> _tryDownloadVideoId({
    required String videoId,
    required File destinationFile,
    required Function(String status, double progress) onProgress,
  }) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 6));

      // ลำดับสตรีมที่ต้องการ:
      // Priority 1: Tag 18 (MP4 360p พร้อมเสียง AAC) - YouTube ไม่บีบความเร็ว และไม่บล็อก Range requests!
      // Priority 2: Audio-only bitrate สูงสุด
      final candidateStreams = <StreamInfo>[];
      final tag18 = manifest.muxed.where((s) => s.tag == 18).firstOrNull;
      if (tag18 != null) candidateStreams.add(tag18);

      final audioOnly = manifest.audioOnly.withHighestBitrate();
      candidateStreams.add(audioOnly);

      for (final stream in candidateStreams) {
        final streamUrl = stream.url.toString();
        final totalBytes = stream.size.totalBytes;

        // 1. ลองดาวน์โหลดแบบ Multi-threaded Range Requests (4 เธรดคู่ขนาน โหลดเสร็จใน 1-2 วินาที)
        final multiOk = await _downloadConcurrentChunks(
          audioUrl: streamUrl,
          totalBytes: totalBytes,
          destinationFile: destinationFile,
          onProgress: onProgress,
        );
        if (multiOk) return true;

        // 2. ถ้า Range ถูกบล็อก ให้ลองสตรีมแบบ Single Stream ปกติ
        final singleOk = await _downloadSingleStream(
          audioUrl: streamUrl,
          totalBytes: totalBytes,
          destinationFile: destinationFile,
          onProgress: onProgress,
        );
        if (singleOk) return true;
      }
    } catch (_) {}

    return false;
  }

  /// ดาวน์โหลดความเร็วสูงแบบ 4 เธรดคู่ขนาน (Multi-threaded Range Requests)
  static Future<bool> _downloadConcurrentChunks({
    required String audioUrl,
    required int totalBytes,
    required File destinationFile,
    required Function(String status, double progress) onProgress,
    int workerCount = 4,
  }) async {
    if (totalBytes <= 0) return false;

    try {
      final chunkSize = (totalBytes / workerCount).ceil();
      final chunks = List<Uint8List?>.filled(workerCount, null);
      final receivedByWorker = List<int>.filled(workerCount, 0);

      final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      onProgress('กำลังดาวน์โหลด: 0% (0.0 / $totalMb MB)', 0.1);

      void updateOverallProgress() {
        final totalReceived = receivedByWorker.fold<int>(0, (sum, val) => sum + val);
        final pct = (totalReceived / totalBytes * 100).toInt().clamp(0, 100);
        final currentMb = (totalReceived / (1024 * 1024)).toStringAsFixed(1);
        final prog = 0.1 + (totalReceived / totalBytes) * 0.70;
        onProgress('กำลังดาวน์โหลด: $pct% ($currentMb / $totalMb MB)', prog);
      }

      final futures = <Future<void>>[];
      for (int i = 0; i < workerCount; i++) {
        final workerIndex = i;
        final start = i * chunkSize;
        final end = (i == workerCount - 1) ? totalBytes - 1 : (i + 1) * chunkSize - 1;

        futures.add(() async {
          final client = http.Client();
          try {
            final req = http.Request('GET', Uri.parse(audioUrl));
            req.headers['User-Agent'] = 'Mozilla/5.0';
            req.headers['Range'] = 'bytes=$start-$end';

            final res = await client.send(req).timeout(const Duration(seconds: 12));
            if (res.statusCode == 200 || res.statusCode == 206) {
              final builder = BytesBuilder(copy: false);
              await for (final chunk in res.stream) {
                builder.add(chunk);
                receivedByWorker[workerIndex] += chunk.length;
                updateOverallProgress();
              }
              chunks[workerIndex] = builder.takeBytes();
            }
          } finally {
            client.close();
          }
        }());
      }

      await Future.wait(futures);

      for (final chunk in chunks) {
        if (chunk == null || chunk.isEmpty) {
          return false;
        }
      }

      final sink = destinationFile.openWrite();
      for (final chunk in chunks) {
        sink.add(chunk!);
      }
      await sink.flush();
      await sink.close();

      return true;
    } catch (_) {
      return false;
    }
  }

  /// สตรีมดาวน์โหลดปกติ (Fallback ในกรณีที่เซิร์ฟเวอร์บล็อก Range requests)
  static Future<bool> _downloadSingleStream({
    required String audioUrl,
    required int totalBytes,
    required File destinationFile,
    required Function(String status, double progress) onProgress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(audioUrl));
      req.headers['User-Agent'] = 'Mozilla/5.0';

      final res = await client.send(req).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 206) {
        final output = destinationFile.openWrite();
        int receivedBytes = 0;
        final totalMbStr = totalBytes > 0 ? (totalBytes / (1024 * 1024)).toStringAsFixed(1) : '';

        await for (final chunk in res.stream) {
          output.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final progress = 0.1 + (receivedBytes / totalBytes) * 0.70;
            final currentMbStr = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            onProgress('กำลังดาวน์โหลด: ${(receivedBytes / totalBytes * 100).toInt()}% ($currentMbStr / $totalMbStr MB)', progress);
          }
        }

        await output.flush();
        await output.close();
        return receivedBytes > 10000;
      }
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
    return false;
  }

  static const Map<String, String> _lrclibHeaders = {
    'User-Agent': 'OfflineMusicPlayer/1.0 (https://github.com/kittipatdef/Music)',
  };

  /// ค้นหาและดึงเนื้อเพลง .lrc จาก LRCLIB API ด้วย User-Agent ที่ถูกต้องและระบบค้นหาแบบละเอียด
  static Future<String?> _fetchSyncedLyricsFromLrclib(
      String title, String artist) async {
    // กำจัดคำขยะ เช่น (feat. ...), ft. ..., etc.
    final cleanTitle = title
        .replaceAll(RegExp(r'\s*\(?(feat\.|ft\.|with)\s+.*?\)?', caseSensitive: false), '')
        .trim();
    final cleanArtist = artist
        .replaceAll(RegExp(r'\s*\(?(feat\.|ft\.|with)\s+.*?\)?', caseSensitive: false), '')
        .trim();

    // 1. ลองแบบ Exact Match ด้วยชื่อคลีน
    try {
      final directUri = Uri.parse(
        'https://lrclib.net/api/get?track_name=${Uri.encodeComponent(cleanTitle)}&artist_name=${Uri.encodeComponent(cleanArtist)}',
      );
      final response = await http.get(directUri, headers: _lrclibHeaders).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final synced = data['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) {
          return synced;
        }
      }
    } catch (_) {}

    // 2. ลองแบบ Search ด้วย $cleanTitle $cleanArtist
    try {
      final searchUri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent('$cleanTitle $cleanArtist')}',
      );
      final response = await http.get(searchUri, headers: _lrclibHeaders).timeout(const Duration(seconds: 6));
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

    // 3. ลองแบบ Search ด้วย $cleanTitle อย่างเดียว
    try {
      final searchUri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent(cleanTitle)}',
      );
      final response = await http.get(searchUri, headers: _lrclibHeaders).timeout(const Duration(seconds: 6));
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
