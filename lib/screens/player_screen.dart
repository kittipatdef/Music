import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
import '../services/audio_handler.dart';
import '../services/file_picker_service.dart';
import '../services/lyrics_parser.dart';

class PlayerScreen extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const PlayerScreen({super.key, required this.audioHandler});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ScrollController _lyricScrollController = ScrollController();
  int _currentLyricIndex = -1;
  bool _isUserScrollingLyrics = false;
  Timer? _resumeAutoScrollTimer;

  // ค่าความสูงโดยประมาณของแต่ละบรรทัดเนื้อเพลง (ใช้สำหรับคำนวณ Auto-scroll ให้นุ่มนวล)
  static const double _lyricItemHeight = 56.0;

  @override
  void initState() {
    super.initState();

    // ติดตามตำแหน่งเวลาปัจจุบันเพื่อไฮไลต์และเลื่อนเนื้อเพลง
    widget.audioHandler.positionStream.listen((position) {
      final currentSong = widget.audioHandler.currentSong;
      if (currentSong == null || currentSong.lyrics.isEmpty) return;

      final newIndex = LyricsParser.findActiveIndex(currentSong.lyrics, position);
      if (newIndex != _currentLyricIndex) {
        if (mounted) {
          setState(() {
            _currentLyricIndex = newIndex;
          });
          _scrollToActiveLyric(newIndex);
        }
      }
    });
  }

  @override
  void dispose() {
    _lyricScrollController.dispose();
    _resumeAutoScrollTimer?.cancel();
    super.dispose();
  }

  /// คำนวณและเลื่อนหน้าจอไปยังตำแหน่งบรรทัดเนื้อเพลงปัจจุบันให้อยู่กึ่งกลาง
  void _scrollToActiveLyric(int index) {
    if (_isUserScrollingLyrics || !_lyricScrollController.hasClients || index < 0) {
      return;
    }

    final viewportHeight = _lyricScrollController.position.viewportDimension;
    // คำนวณให้อยู่กึ่งกลางหน้าจอ (Center Alignment)
    final targetOffset = (index * _lyricItemHeight) - (viewportHeight / 2) + (_lyricItemHeight / 2);

    final clampedOffset = targetOffset.clamp(
      0.0,
      _lyricScrollController.position.maxScrollExtent,
    );

    _lyricScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  /// ปิดการ auto-scroll ชั่วคราวเมื่อผู้ใช้กำลังปัดอ่านเนื้อเพลงด้วยตัวเอง
  void _onUserStartScroll() {
    _isUserScrollingLyrics = true;
    _resumeAutoScrollTimer?.cancel();
    _resumeAutoScrollTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isUserScrollingLyrics = false;
        });
        _scrollToActiveLyric(_currentLyricIndex);
      }
    });
  }

  /// เลือกไฟล์เพลงจาก Local Storage
  Future<void> _handleImportSongs() async {
    final songs = await FilePickerService.pickAudioFiles();
    if (songs.isNotEmpty) {
      widget.audioHandler.setPlaylist(songs);
    }
  }

  /// เลือกไฟล์ .lrc เพื่อนำมาผูกกับเพลงที่กำลังเล่นอยู่
  Future<void> _handleImportLrc(SongItem song) async {
    final path = await FilePickerService.pickLrcFile();
    if (path != null) {
      final lyrics = await LyricsParser.parseFile(path);
      final updated = song.copyWith(lrcPath: path, lyrics: lyrics);
      widget.audioHandler.updateSongLyrics(song.id, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('โหลดเนื้อเพลงสำเร็จ (${lyrics.length} บรรทัด)'),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D11),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'OFFLINE PLAYER',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.0,
            color: Color(0xFF94A3B8),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 28),
            tooltip: 'รายการคิวเพลง',
            onPressed: () => _showPlaylistModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
            tooltip: 'เพิ่มเพลงจากเครื่อง',
            onPressed: _handleImportSongs,
          ),
        ],
      ),
      body: StreamBuilder<SongItem?>(
        stream: widget.audioHandler.currentSongStream,
        builder: (context, songSnapshot) {
          final song = songSnapshot.data;

          if (song == null) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              const SizedBox(height: 12),
              // ข้อมูลเพลง
              _buildSongInfo(song),
              const SizedBox(height: 16),
              // พื้นที่แสดงเนื้อเพลง Synced Lyrics
              Expanded(
                child: _buildLyricsView(song),
              ),
              // แผงควบคุมเวลาและปุ่มเล่นเพลง
              _buildPlayerControls(song),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E1E26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.music_note_rounded,
              size: 56,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'ยังไม่มีเพลงในรายการ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'เลือกไฟล์ .mp3 จากในเครื่องของคุณเพื่อเริ่มต้น',
            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _handleImportSongs,
            icon: const Icon(Icons.file_open_rounded),
            label: const Text('เลือกไฟล์เพลงจากเครื่อง'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongInfo(SongItem song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsView(SongItem song) {
    if (song.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lyrics_outlined, size: 48, color: Color(0xFF334155)),
            const SizedBox(height: 12),
            const Text(
              'ไม่พบไฟล์เนื้อเพลง (.lrc)',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _handleImportLrc(song),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('เลือกไฟล์ .lrc สำหรับเพลงนี้'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF818CF8),
                side: const BorderSide(color: Color(0xFF3730A3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _onUserStartScroll();
        }
        return false;
      },
      child: ShaderMask(
        // Effect ขอบเบลอ Fade Out ด้านบนและด้านล่าง เพิ่มความรู้สึกแบบ Minimalistic Modern
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.15, 0.85, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _lyricScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 120),
          itemCount: song.lyrics.length,
          itemBuilder: (context, index) {
            final entry = song.lyrics[index];
            final isActive = index == _currentLyricIndex;

            return InkWell(
              onTap: () {
                // กดที่บรรทัดเนื้อเพลงเพื่อกรอ (Seek) ไปยังท่อนนั้นได้ทันที!
                widget.audioHandler.seek(entry.timestamp);
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                alignment: Alignment.center,
                height: _lyricItemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  entry.text.isEmpty ? '♪' : entry.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isActive ? 21 : 16,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive ? Colors.white : const Color(0xFF475569),
                    letterSpacing: isActive ? 0.3 : 0,
                    shadows: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerControls(SongItem song) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Slider แสดงเวลาเพลง
            StreamBuilder<Duration>(
              stream: widget.audioHandler.positionStream,
              builder: (context, posSnapshot) {
                final position = posSnapshot.data ?? Duration.zero;
                final duration = song.duration ?? Duration.zero;
                final maxSeconds = duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0;
                final currentSeconds = position.inMilliseconds.toDouble().clamp(0.0, maxSeconds);

                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: const Color(0xFF2E2E3A),
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: currentSeconds,
                        max: maxSeconds,
                        onChanged: (val) {
                          widget.audioHandler.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 8),

            // ปุ่มควบคุม Previous, Play/Pause, Next
            StreamBuilder<PlayerState>(
              stream: widget.audioHandler.playerStateStream,
              builder: (context, stateSnapshot) {
                final playerState = stateSnapshot.data;
                final isPlaying = playerState?.playing ?? false;
                final isProcessing =
                    playerState?.processingState == ProcessingState.loading ||
                    playerState?.processingState == ProcessingState.buffering;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Previous
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                      onPressed: () => widget.audioHandler.skipToPrevious(),
                    ),
                    const SizedBox(width: 24),
                    // Play/Pause Main Button
                    GestureDetector(
                      onTap: () {
                        if (isPlaying) {
                          widget.audioHandler.pause();
                        } else {
                          widget.audioHandler.play();
                        }
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: isProcessing
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 38,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Next
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                      onPressed: () => widget.audioHandler.skipToNext(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showPlaylistModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StreamBuilder<List<SongItem>>(
          stream: widget.audioHandler.playlistStream,
          builder: (context, snapshot) {
            final playlist = snapshot.data ?? [];

            return Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'รายการเพลง (${playlist.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleImportSongs();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('เพิ่มเพลง'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF818CF8)),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF1E293B), height: 1),
                Expanded(
                  child: playlist.isEmpty
                      ? const Center(
                          child: Text('ไม่มีเพลงในรายการ', style: TextStyle(color: Color(0xFF64748B))),
                        )
                      : ListView.builder(
                          itemCount: playlist.length,
                          itemBuilder: (context, idx) {
                            final item = playlist[idx];
                            final isPlayingThis = widget.audioHandler.currentIndex == idx;

                            return ListTile(
                              leading: Icon(
                                isPlayingThis ? Icons.volume_up_rounded : Icons.music_note_rounded,
                                color: isPlayingThis ? const Color(0xFF6366F1) : const Color(0xFF475569),
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                                  color: isPlayingThis ? const Color(0xFF818CF8) : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                item.lyrics.isNotEmpty ? '✓ มีเนื้อเพลง' : 'ไม่มีเนื้อเพลง',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: item.lyrics.isNotEmpty ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                                onPressed: () => _handleImportLrc(item),
                                tooltip: 'เพิ่มไฟล์ .lrc ให้เพลงนี้',
                              ),
                              onTap: () {
                                widget.audioHandler.playSongAtIndex(idx);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
