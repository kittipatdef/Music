# Personal Offline Music Player with Synced LRC Lyrics

แอปพลิเคชันเล่นเพลงออฟไลน์สำหรับ Android พร้อมระบบแสดงเนื้อเพลงซิงค์ตามเวลา (.lrc) พัฒนาด้วย Flutter

---

## ฟีเจอร์หลัก (Features)
- 🎵 **100% Offline Playback**: เล่นไฟล์เสียง (.mp3, .wav, .m4a, .flac) จากในเครื่องโดยตรง ไม่ต้องใช้อินเทอร์เน็ต
- 📜 **Synced Lyrics (.lrc)**: ตัวแปลง (Parser) รองรับแท็ก `[mm:ss.xx]` และ `[mm:ss.xxx]` พร้อมไฮไลต์บรรทัดปัจจุบันและเลื่อนหน้าจออัตโนมัติ (Auto-scroll)
- 👆 **Tap to Seek via Lyrics**: กดที่บรรทัดเนื้อเพลงเพื่อกระโดดข้ามไปยังท่อนเพลงนั้นได้ทันที
- 🔋 **Background Playback & Lock Screen**: เล่นเพลงต่อเนื่องเมื่อสลับแอปหรือปิดหน้าจอ ผ่าน Android Foreground Service พร้อมแถบควบคุมบนแถบแจ้งเตือน (Notification) และหน้าจอ Lock Screen
- 📂 **Auto-matching LRC**: ตรวจจับไฟล์ `.lrc` ที่ชื่อเดียวกันในโฟลเดอร์เดียวกับเพลงให้อัตโนมัติ หรือเลือกไฟล์แยกได้ตามต้องการ

---

## โครงสร้างโปรเจกต์ (Project Structure)
```
lib/
├── main.dart                       # จุดเริ่มต้นแอปและตั้งค่า AudioService
├── models/
│   ├── lyric_entry.dart            # โมเดลข้อมูลเนื้อเพลงแต่ละบรรทัด (Timecode + ข้อความ)
│   └── song_item.dart              # โมเดลเพลงและเมธอดแปลงเป็น MediaItem
├── services/
│   ├── audio_handler.dart          # BaseAudioHandler จัดการคิวเพลงและเครื่องเล่นเสียงเบื้องหลัง
│   ├── lyrics_parser.dart          # ตัวแปลงไฟล์ .lrc และอัลกอริทึม Binary Search ค้นหาบรรทัดปัจจุบัน
│   └── file_picker_service.dart    # ขอสิทธิ์ Android และเลือกไฟล์เสียง/เนื้อเพลง
└── screens/
    └── player_screen.dart          # หน้าจอเครื่องเล่นเพลงสไตล์ Minimal Dark Mode
```

---

## ข้อกำหนดของระบบ Android (Android Configuration)
ในไฟล์ `android/app/build.gradle`:
- `minSdkVersion`: 21 ขึ้นไป
- `compileSdkVersion`: 34 ขึ้นไป
- `targetSdkVersion`: 34 ขึ้นไป
