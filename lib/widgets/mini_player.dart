import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
import '../screens/player_screen.dart';
import '../services/audio_handler.dart';

/// Mini Player ลอยอยู่ด้านล่างหน้าจอ สไตล์ Spotify
/// แสดงเพลงที่กำลังเล่นหรือเพลงที่เล่นล่าสุด พร้อมปุ่ม Play/Pause และแถบเวลาจิ๋ว
class MiniPlayer extends StatelessWidget {
  final MyAudioHandler audioHandler;

  const MiniPlayer({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SongItem?>(
      stream: audioHandler.currentSongStream,
      builder: (context, songSnap) {
        final currentSong = songSnap.data;
        if (currentSong == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                // แตะที่ Mini Player เพื่อเปิดหน้าจอเครื่องเล่นเพลงเต็ม (Full Player พร้อมเนื้อเพลง)
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        PlayerScreen(audioHandler: audioHandler),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      const begin = Offset(0.0, 1.0);
                      const end = Offset.zero;
                      const curve = Curves.easeOutCubic;
                      var tween = Tween(begin: begin, end: end)
                          .chain(CurveTween(curve: curve));
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                  ),
                );
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFF2E2E42),
                    width: 0.8,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    children: [
                      // ส่วนข้อมูลเพลงและปุ่มควบคุม
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              // รูปปกเพลง (Album Art หรือ Default Icon)
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: const Color(0xFF262638),
                                  image: currentSong.coverArt != null
                                      ? DecorationImage(
                                          image: MemoryImage(currentSong.coverArt!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: currentSong.coverArt == null
                                    ? const Icon(
                                        Icons.music_note_rounded,
                                        color: Color(0xFF818CF8),
                                        size: 24,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),

                              // ชื่อเพลงและศิลปิน
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentSong.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentSong.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ปุ่ม Play / Pause
                              StreamBuilder<PlayerState>(
                                stream: audioHandler.playerStateStream,
                                builder: (context, stateSnap) {
                                  final isPlaying =
                                      stateSnap.data?.playing ?? false;
                                  return IconButton(
                                    icon: Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onPressed: () {
                                      if (isPlaying) {
                                        audioHandler.pause();
                                      } else {
                                        audioHandler.play();
                                      }
                                    },
                                  );
                                },
                              ),

                              // ปุ่มข้ามเพลงถัดไป (Next)
                              IconButton(
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 24,
                                ),
                                onPressed: () => audioHandler.skipToNext(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // แถบ Progress Bar เล็กๆ ด้านล่าง
                      StreamBuilder<Duration>(
                        stream: audioHandler.positionStream,
                        builder: (context, posSnap) {
                          final pos = posSnap.data ?? Duration.zero;
                          final dur = currentSong.duration ?? Duration.zero;
                          final progress = (dur.inMilliseconds > 0)
                              ? (pos.inMilliseconds / dur.inMilliseconds)
                                  .clamp(0.0, 1.0)
                              : 0.0;

                          return LinearProgressIndicator(
                            value: progress,
                            minHeight: 2.2,
                            backgroundColor: const Color(0xFF262638),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF6366F1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
