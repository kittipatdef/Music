import 'dart:io';
import 'dart:typed_data';

/// เครื่องมือดึงภาพปก (Album Art) จากไฟล์ MP3 ด้วยภาษา Dart แท้ (Pure Dart)
/// โดยไม่ต้องพึ่งพา Library ภายนอกหรือ NDK ใดๆ
class Id3Parser {
  /// อ่านภาพปก (APIC Frame) จากไฟล์ MP3
  static Future<Uint8List?> extractCoverArt(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      // อ่านเฉพาะ 2MB แรกของไฟล์ (ID3v2 Header มักอยู่ที่ต้นไฟล์)
      final length = await file.length();
      final readLength = length > (2 * 1024 * 1024) ? (2 * 1024 * 1024) : length;

      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(readLength);
      await raf.close();

      return _findApicFrame(bytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _findApicFrame(Uint8List bytes) {
    if (bytes.length < 10) return null;

    // ตรวจสอบ Header: "ID3"
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return null;
    }

    final majorVersion = bytes[3];
    if (majorVersion != 3 && majorVersion != 4) {
      // รองรับ ID3v2.3 และ ID3v2.4
      return null;
    }

    // ขนาดรวมของ ID3 Header (Syncsafe integer: 4 ไบต์)
    final tagSize = ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);

    int offset = 10;
    final maxOffset = (tagSize + 10).clamp(10, bytes.length);

    while (offset + 10 < maxOffset) {
      // ตรวจสอบ Frame ID (4 ตัวอักษร เช่น 'APIC')
      final frameId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (frameId.codeUnits.any((c) => c < 32 || c > 126)) {
        break; // ข้อมูล padding สิ้นสุด
      }

      int frameSize = 0;
      if (majorVersion == 4) {
        // ID3v2.4 ใช้ Syncsafe integer
        frameSize = ((bytes[offset + 4] & 0x7F) << 21) |
            ((bytes[offset + 5] & 0x7F) << 14) |
            ((bytes[offset + 6] & 0x7F) << 7) |
            (bytes[offset + 7] & 0x7F);
      } else {
        // ID3v2.3 ใช้ standard 32-bit big endian
        frameSize = (bytes[offset + 4] << 24) |
            (bytes[offset + 5] << 16) |
            (bytes[offset + 6] << 8) |
            bytes[offset + 7];
      }

      final frameDataStart = offset + 10;
      final frameDataEnd = frameDataStart + frameSize;

      if (frameDataEnd > bytes.length) break;

      if (frameId == 'APIC') {
        final frameBytes = bytes.sublist(frameDataStart, frameDataEnd);
        return _extractPictureDataFromApic(frameBytes);
      }

      offset = frameDataEnd;
    }

    return null;
  }

  static Uint8List? _extractPictureDataFromApic(Uint8List apicBytes) {
    if (apicBytes.length < 5) return null;

    // Byte 0: Text encoding
    int cursor = 1;

    // MIME type (ASCII null-terminated)
    while (cursor < apicBytes.length && apicBytes[cursor] != 0) {
      cursor++;
    }
    cursor++; // ข้าม null terminator ของ MIME

    if (cursor >= apicBytes.length) return null;

    // Picture type (1 byte: e.g. 0x03 for Cover Front)
    cursor++;

    // Description (null-terminated string)
    while (cursor < apicBytes.length && apicBytes[cursor] != 0) {
      cursor++;
    }
    cursor++; // ข้าม null terminator ของ description

    // ค้นหาตำแหน่งเริ่มต้นของข้อมูลภาพจริง (JPEG header 0xFF, 0xD8 หรือ PNG header 0x89, 0x50)
    for (int i = cursor; i < apicBytes.length - 1; i++) {
      if ((apicBytes[i] == 0xFF && apicBytes[i + 1] == 0xD8) ||
          (apicBytes[i] == 0x89 && apicBytes[i + 1] == 0x50)) {
        return apicBytes.sublist(i);
      }
    }

    if (cursor < apicBytes.length) {
      return apicBytes.sublist(cursor);
    }

    return null;
  }
}
