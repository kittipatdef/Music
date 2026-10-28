/// โมเดลสำหรับเก็บข้อมูลแต่ละบรรทัดของเนื้อเพลงพร้อม Timecode
class LyricEntry implements Comparable<LyricEntry> {
  final Duration timestamp;
  final String text;

  LyricEntry({
    required this.timestamp,
    required this.text,
  });

  @override
  int compareTo(LyricEntry other) {
    return timestamp.compareTo(other.timestamp);
  }

  @override
  String toString() => '[${timestamp.inMinutes}:${(timestamp.inSeconds % 60).toString().padLeft(2, '0')}] $text';
}
