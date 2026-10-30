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
  final String? directStreamUrl;
  final int? streamBytes;

  TrackMeta({
    required this.title,
    required this.artist,
    this.coverUrl,
    required this.youtubeVideoId,
    this.directStreamUrl,
    this.streamBytes,
  });
}

/// Service สำหรับดาวน์โหลดเพลงจาก YouTube พร้อมดึงเนื้อเพลงซิงค์ .lrc ด้วยความเร็วสูง
class OnlineDownloaderService {
  static final YoutubeExplode _yt = YoutubeExplode();

  /// รายชื่อ Invidious API instances ความเร็วสูงที่มีระบบ PO Token สำเร็จรูป
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

  /// ดึงข้อมูล Metadata จากลิงก์ YouTube
  static Future<TrackMeta> extractMetadata(String url) async {
    var cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    final videoId = extractVideoId(cleanUrl);
    if (videoId == null) {
      throw Exception('ลิงก์ YouTube ไม่ถูกต้อง ไม่พบรหัสวิดีโอ');
    }

    // 1. ดึงข้อมูลและลิงก์สตรีมผ่าน Invidious API ก่อน
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

          final formats = (data['adaptiveFormats'] as List?)
              ?.where((f) => (f['type'] as String? ?? '').startsWith('audio/'))
              .toList();

          String? streamUrl;
          int? totalBytes;

          if (formats != null && formats.isNotEmpty) {
            formats.sort((a, b) {
              final bitA = int.tryParse(a['bitrate']?.toString() ?? '0') ?? 0;
              final bitB = int.tryParse(b['bitrate']?.toString() ?? '0') ?? 0;
              return bitB.compareTo(bitA);
            });
            streamUrl = formats.first['url'] as String?;
            totalBytes = int.tryParse(formats.first['clen']?.toString() ?? '');
          }

          return TrackMeta(
            title: cleanSongTitle(rawTitle),
            artist: author.replaceAll(' - Topic', '').trim(),
            coverUrl: coverUrl,
            youtubeVideoId: videoId,
            directStreamUrl: streamUrl,
            streamBytes: totalBytes,
          );
        }
      } catch (_) {}
    }

    // 2. หาก Invidious ไม่ตอบสนอง ให้ลองดึงผ่าน YouTube Explode (Fallback)
    try {
      final video = await _yt.videos.get(cleanUrl).timeout(const Duration(seconds: 6));
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
      throw Exception('ไม่สามารถดึงข้อมูล YouTube ได้: $e');
    }
  }

  /// ดาวน์โหลดเพลงและเนื้อเพลงซิงค์ (.lrc)
  static Future<SongItem> downloadTrack(
    TrackMeta meta, {
    required Function(String status, double progress) onProgress,
  }) async {
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

      // สตรีมดาวน์โหลดไฟล์เสียงโดยตรงด้วยระบบ Multi-threaded Speed Boost
      final success = await _streamDownloadAudio(
        meta,
        audioFile,
        onProgress,
      );

      if (!success) {
        throw Exception('ไม่สามารถดาวน์โหลดไฟล์เสียงจากคลิปนี้ได้ กรุณาลองใหม่อีกครั้ง');
      }

      // ดึงเนื้อเพลงซิงค์ .lrc จาก LRCLIB
      onProgress('กำลังค้นหาเนื้อเพลงซิงค์ (.lrc)...', 0.8);
      List<LyricEntry> lyrics = [];
      String? lrcFilePath;

      final lrcContent = await _fetchSyncedLyricsFromLrclib(meta.title, meta.artist);
      if (lrcContent != null && lrcContent.isNotEmpty) {
        lrcFilePath = '${downloadDir.path}/$safeFilename.lrc';
        await File(lrcFilePath).writeAsString(lrcContent);
        lyrics = LyricsParser.parse(lrcContent);
        onProgress('พบเนื้อเพลงซิงค์สำเร็จ (${lyrics.length} บรรทัด)', 0.9);
      } else {
        onProgress('ไม่พบเนื้อเพลงซิงค์สำหรับเพลงนี้', 0.9);
      }

      // ดาวน์โหลดภาพปกอัลบั้ม
      Uint8List? coverBytes;
      if (meta.coverUrl != null && meta.coverUrl!.isNotEmpty) {
        onProgress('กำลังโหลดภาพปกอัลบั้ม...', 0.95);
        try {
          final imgRes = await http.get(Uri.parse(meta.coverUrl!)).timeout(
                const Duration(seconds: 8),
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

  /// สตรีมดาวน์โหลดไฟล์เสียงด้วยระบบ Multi-threaded Range Requests เพื่อความเร็วสูงสุด (ไม่โดนจำกัดความเร็ว)
  static Future<bool> _streamDownloadAudio(
    TrackMeta meta,
    File destinationFile,
    Function(String status, double progress) onProgress,
  ) async {
    // 1. ถ้ามี Direct Stream URL และทราบขนาดไฟล์ ให้ใช้ดาวน์โหลดหลายเธรดคู่ขนานทันที (เร็วขึ้นเกือบ 100 เท่า)
    if (meta.directStreamUrl != null &&
        meta.directStreamUrl!.isNotEmpty &&
        meta.streamBytes != null &&
        meta.streamBytes! > 0) {
      final multiThreadOk = await _downloadConcurrentChunks(
        audioUrl: meta.directStreamUrl!,
        totalBytes: meta.streamBytes!,
        destinationFile: destinationFile,
        onProgress: onProgress,
      );
      if (multiThreadOk) {
        return true;
      }
    }

    // 2. รายการ URL ที่จะลองดาวน์โหลดตามลำดับ
    final candidateUrls = <String>[];
    if (meta.directStreamUrl != null && meta.directStreamUrl!.isNotEmpty) {
      candidateUrls.add(meta.directStreamUrl!);
    }
    for (final base in _invidiousInstances) {
      candidateUrls.add('$base/latest_version?id=${meta.youtubeVideoId}&itag=140');
      candidateUrls.add('$base/latest_version?id=${meta.youtubeVideoId}&itag=251');
    }

    for (final streamUrl in candidateUrls) {
      try {
        final client = http.Client();
        final req = http.Request('GET', Uri.parse(streamUrl));
        req.headers['User-Agent'] = 'Mozilla/5.0';

        final streamedRes = await client.send(req).timeout(const Duration(seconds: 7));
        if (streamedRes.statusCode == 200 || streamedRes.statusCode == 206) {
          final expectedBytes = streamedRes.contentLength ?? meta.streamBytes ?? 0;

          // ถ้าทราบขนาดไฟล์ ให้ลองทำ multi-thread ดาวน์โหลดทันที
          if (expectedBytes > 0 && streamUrl == meta.directStreamUrl) {
            client.close();
            final ok = await _downloadConcurrentChunks(
              audioUrl: streamUrl,
              totalBytes: expectedBytes,
              destinationFile: destinationFile,
              onProgress: onProgress,
            );
            if (ok) return true;
          }

          final totalMbStr = expectedBytes > 0
              ? (expectedBytes / (1024 * 1024)).toStringAsFixed(1)
              : '';

          onProgress('กำลังดาวน์โหลดเพลง ${totalMbStr.isNotEmpty ? "($totalMbStr MB)..." : "..."}', 0.2);

          final output = destinationFile.openWrite();
          int receivedBytes = 0;

          await for (final chunk in streamedRes.stream) {
            output.add(chunk);
            receivedBytes += chunk.length;
            if (expectedBytes > 0) {
              final progress = 0.2 + (receivedBytes / expectedBytes) * 0.55;
              final currentMbStr = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              onProgress('กำลังดาวน์โหลด: ${(receivedBytes / expectedBytes * 100).toInt()}% ($currentMbStr / $totalMbStr MB)', progress);
            } else {
              final currentMbStr = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              onProgress('กำลังดาวน์โหลด: $currentMbStr MB', 0.45);
            }
          }

          await output.flush();
          await output.close();
          client.close();

          if (receivedBytes > 10000) {
            return true;
          }
        } else {
          client.close();
        }
      } catch (_) {}
    }

    return false;
  }

  /// ดาวน์โหลดแบบหลายเธรดคู่ขนาน (Multi-threaded Range Download) เพื่อทะลุการบีบความเร็วของ YouTube
  static Future<bool> _downloadConcurrentChunks({
    required String audioUrl,
    required int totalBytes,
    required File destinationFile,
    required Function(String status, double progress) onProgress,
    int workerCount = 4,
  }) async {
    try {
      final chunkSize = (totalBytes / workerCount).ceil();
      final chunks = List<Uint8List?>.filled(workerCount, null);
      final receivedByWorker = List<int>.filled(workerCount, 0);

      final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      onProgress('กำลังดาวน์โหลดความเร็วสูง: 0% (0.0 / $totalMb MB)', 0.2);

      void updateOverallProgress() {
        final totalReceived = receivedByWorker.fold<int>(0, (sum, val) => sum + val);
        final pct = (totalReceived / totalBytes * 100).toInt().clamp(0, 100);
        final currentMb = (totalReceived / (1024 * 1024)).toStringAsFixed(1);
        final prog = 0.2 + (totalReceived / totalBytes) * 0.55;
        onProgress('กำลังดาวน์โหลดความเร็วสูง: $pct% ($currentMb / $totalMb MB)', prog);
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

            final res = await client.send(req).timeout(const Duration(seconds: 15));
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

  /// ค้นหาและดึงเนื้อเพลง .lrc จาก LRCLIB API
  static Future<String?> _fetchSyncedLyricsFromLrclib(
      String title, String artist) async {
    try {
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
