# Personal Offline Music Player with Synced LRC Lyrics

แอปพลิเคชันเล่นเพลงออฟไลน์สำหรับ Android พร้อมระบบแสดงเนื้อเพลงซิงค์ตามเวลา (.lrc) สไตล์ Minimal Dark Mode พัฒนาด้วย Flutter

---

## ฟีเจอร์หลัก (Features)
- 🎵 **100% Offline Playback**: เล่นไฟล์เสียง (.mp3, .wav, .m4a, .flac) จากในเครื่องโดยตรง ไม่ต้องใช้อินเทอร์เน็ต
- 📜 **Synced Lyrics (.lrc)**: ตัวแปลง (Parser) รองรับแท็ก `[mm:ss.xx]` และ `[mm:ss.xxx]` พร้อมไฮไลต์บรรทัดปัจจุบันและเลื่อนหน้าจออัตโนมัติ (Auto-scroll)
- 👆 **Tap to Seek via Lyrics**: กดที่บรรทัดเนื้อเพลงเพื่อกระโดดข้ามไปยังท่อนเพลงนั้นได้ทันที
- 🔋 **Background Playback & Lock Screen**: เล่นเพลงต่อเนื่องเมื่อสลับแอปหรือปิดหน้าจอ ผ่าน Android Foreground Service พร้อมแถบควบคุมบนแถบแจ้งเตือน (Notification) และหน้าจอ Lock Screen
- 📂 **Auto-matching LRC**: ตรวจจับไฟล์ `.lrc` ที่ชื่อเดียวกันในโฟลเดอร์เดียวกับเพลงให้อัตโนมัติ หรือเลือกไฟล์แยกได้ตามต้องการ
- 💾 **Persistent Library**: จดจำรายชื่อเพลงและเนื้อเพลงที่เคยนำเข้าไว้ เปิดแอปครั้งต่อไปเพลงเดิมยังอยู่ทันทีไม่ต้องเลือกใหม่
- 🔀 **Shuffle & Repeat**: สุ่มเพลงในคิว และระบบวนซ้ำ 3 โหมด (Repeat All, Repeat One, Repeat Off)
- 🖼️ **ID3 Album Art Extractor**: ดึงภาพปกอัลบั้มที่ฝังในไฟล์ MP3 มาแสดงผลอัตโนมัติด้วย Pure Dart
- ⏰ **Sleep Timer**: โหมดตั้งเวลาปิดเพลงอัตโนมัติ (15, 30, 45, 60 นาที) พร้อมเวลานับถอยหลังบนหน้าจอ
- 🗑️ **Swipe to Delete**: ปัดเพื่อลบเพลงออกจากคิวในหน้ารายการเพลง

---

## โครงสร้างโปรเจกต์ (Project Structure)
```
lib/
├── main.dart                       # จุดเริ่มต้นแอปและตั้งค่า AudioService
├── models/
│   ├── lyric_entry.dart            # โมเดลข้อมูลเนื้อเพลงแต่ละบรรทัด (Timecode + ข้อความ)
│   └── song_item.dart              # โมเดลเพลง, ปกอัลบั้ม, JSON serialization
├── services/
│   ├── audio_handler.dart          # BaseAudioHandler (Shuffle, Repeat, Sleep Timer, Queue)
│   ├── lyrics_parser.dart          # ตัวแปลงไฟล์ .lrc และอัลกอริทึม Binary Search ค้นหาบรรทัดปัจจุบัน
│   ├── file_picker_service.dart    # ขอสิทธิ์ Android และเลือกไฟล์เสียง/เนื้อเพลง
│   ├── id3_parser.dart             # Pure Dart ดึงรูปปกอัลบั้ม (APIC frame)
│   └── playlist_storage_service.dart # ระบบเซฟ/โหลดเพลย์ลิสต์ถาวร (SharedPreferences)
└── screens/
    └── player_screen.dart          # หน้าจอเครื่องเล่นเพลงสไตล์ Minimal Dark Mode
```

---

## ข้อกำหนดของระบบ Android (Android Configuration)
ในไฟล์ `android/app/build.gradle.kts`:
- `minSdk`: 21 ขึ้นไป
- `compileSdk`: 36
- `targetSdk`: 34
