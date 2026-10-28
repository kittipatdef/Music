import 'dart:io';
import '../models/lyric_entry.dart';

/// ตัวแปลงไฟล์เนื้อเพลง .lrc (LRC Parser)
class LyricsParser {
  // Regex ตรวจจับ Tag Timecode เช่น [01:23.45] หรือ [01:23.456] หรือ [01:23]
  static final RegExp _timeTagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?\]');

  /// แปลงเนื้อหา String ของไฟล์ .lrc ออกมาเป็น List<LyricEntry> เรียงตามเวลา
  static List<LyricEntry> parse(String lrcContent) {
    if (lrcContent.trim().isEmpty) return [];

    final List<LyricEntry> entries = [];
    final lines = lrcContent.split(RegExp(r'\r?\n'));

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // ข้าม Metadata ทั่วไป เช่น [ti:...], [ar:...], [by:...]
      if (line.startsWith('[ti:') ||
          line.startsWith('[ar:') ||
          line.startsWith('[al:') ||
          line.startsWith('[by:') ||
          line.startsWith('[offset:')) {
        continue;
      }

      // ดึง timestamp tags ทั้งหมดในบรรทัด (รองรับกรณีบรรทัดเดียวมีหลาย timestamp ซ้ำ)
      // ตัวอย่าง: [00:12.30][01:45.20]ร้องท่อนซ้ำ
      final matches = _timeTagRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // ข้อความเนื้อเพลงคือส่วนที่เหลือหลังจากตัด tags ออก
      final text = line.replaceAll(_timeTagRegex, '').trim();

      for (var match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        
        int milliseconds = 0;
        final msStr = match.group(3);
        if (msStr != null) {
          if (msStr.length == 2) {
            // ค่า xx คือร้อยละวินาที (centiseconds) -> คูณ 10 เพื่อแปลงเป็น ms
            milliseconds = int.parse(msStr) * 10;
          } else if (msStr.length == 3) {
            milliseconds = int.parse(msStr);
          }
        }

        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        entries.add(LyricEntry(
          timestamp: duration,
          text: text,
        ));
      }
    }

    // เรียงลำดับตาม Timestamp จากต้นเพลงไปท้ายเพลง
    entries.sort();
    return entries;
  }

  /// โหลดไฟล์ .lrc จาก path ในเครื่องแล้วทำการแปลง
  static Future<List<LyricEntry>> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      return parse(content);
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing LRC file: $e');
      return [];
    }
  }

  /// ค้นหา Index บรรทัดเนื้อเพลงที่กำลังเล่นอยู่ ณ เวลา position
  /// คืนค่า -1 หากยังไม่ถึงเวลาเริ่มบรรทัดแรก (ช่วง Intro)
  static int findActiveIndex(List<LyricEntry> lyrics, Duration position) {
    if (lyrics.isEmpty || position < lyrics.first.timestamp) {
      return -1;
    }

    // Binary Search เพื่อประสิทธิภาพสูงสุด
    int low = 0;
    int high = lyrics.length - 1;
    int activeIndex = 0;

    while (low <= high) {
      int mid = (low + high) ~/ 2;
      if (lyrics[mid].timestamp <= position) {
        activeIndex = mid;
        low = mid + 1; // ลองหาบรรทัดที่ตรงหรือใกล้เคียงที่สุดถัดไป
      } else {
        high = mid - 1;
      }
    }

    return activeIndex;
  }
}
