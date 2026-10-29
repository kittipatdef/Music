import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
import '../services/audio_handler.dart';
import '../services/file_picker_service.dart';
import '../services/lyrics_parser.dart';
import '../widgets/download_dialog.dart';
import '../widgets/playlist_bottom_sheet.dart';

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

  static const double _lyricItemHeight = 56.0;

  @override
  void initState() {
    super.initState();

    // ขอสิทธิ์แจ้งเตือน Notification และสิทธิ์การเข้าถึงไฟล์ตั้งแต่เริ่มเปิดแอป
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FilePickerService.requestPermissions();
    });

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

  void _scrollToActiveLyric(int index) {
    if (_isUserScrollingLyrics || !_lyricScrollController.hasClients || index < 0) {
      return;
    }

    final viewportHeight = _lyricScrollController.position.viewportDimension;
    final targetOffset =
        (index * _lyricItemHeight) - (viewportHeight / 2) + (_lyricItemHeight / 2);

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

  Future<void> _handleImportSongs() async {
    final songs = await FilePickerService.pickAudioFiles();
    if (songs.isNotEmpty) {
      if (widget.audioHandler.playlist.isEmpty) {
        widget.audioHandler.setPlaylist(songs);
      } else {
        widget.audioHandler.addSongs(songs);
      }
    }
  }

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

  void _showSleepTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF181822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.timer_outlined, color: Color(0xFF818CF8)),
              SizedBox(width: 10),
              Text('ตั้งเวลาปิดเพลง (Sleep Timer)', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTimerOption(ctx, '15 นาที', 15),
              _buildTimerOption(ctx, '30 นาที', 30),
              _buildTimerOption(ctx, '45 นาที', 45),
              _buildTimerOption(ctx, '60 นาที (1 ชั่วโมง)', 60),
              const Divider(color: Color(0xFF2E2E3A)),
              ListTile(
                leading: const Icon(Icons.timer_off_outlined, color: Colors.redAccent),
                title: const Text('ปิดการตั้งเวลา', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  widget.audioHandler.cancelSleepTimer();
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimerOption(BuildContext context, String title, int minutes) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF64748B)),
      onTap: () {
        widget.audioHandler.setSleepTimer(minutes);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ตั้งเวลาปิดเพลงใน $title'),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D11),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: StreamBuilder<int?>(
          stream: widget.audioHandler.sleepTimerStream,
          builder: (context, timerSnap) {
            final remaining = timerSnap.data;
            final isActive = remaining != null;
            return IconButton(
              icon: Icon(
                isActive ? Icons.timer_rounded : Icons.timer_outlined,
                color: isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                size: 22,
              ),
              tooltip: isActive
                  ? 'เหลือเวลา ${_formatSeconds(remaining)}'
                  : 'ตั้งเวลาปิดเพลง',
              onPressed: () => _showSleepTimerDialog(context),
            );
          },
        ),
        title: const Text(
          'OFFLINE PLAYER',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: Color(0xFF94A3B8),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download_rounded, color: Color(0xFF818CF8)),
            tooltip: 'ดาวน์โหลดจากลิงก์ YouTube / Spotify',
            onPressed: () => DownloadDialog.show(context, widget.audioHandler),
          ),
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
              const SizedBox(height: 8),
              _buildSongInfo(song),
              const SizedBox(height: 12),
              Expanded(
                child: _buildLyricsView(song),
              ),
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => DownloadDialog.show(context, widget.audioHandler),
            icon: const Icon(Icons.link_rounded, size: 20),
            label: const Text('ดาวน์โหลดจากลิงก์ YouTube / Spotify'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF818CF8),
              side: const BorderSide(color: Color(0xFF4338CA)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      child: Row(
        children: [
          // รูปปกอัลบั้ม (ID3 Album Art หรือ Default Icon)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF1E1E28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              image: song.coverArt != null
                  ? DecorationImage(
                      image: MemoryImage(song.coverArt!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: song.coverArt == null
                ? const Icon(Icons.music_note_rounded, color: Color(0xFF6366F1), size: 28)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
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
                    fontSize: 13,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Slider แสดงเวลาเพลง
            StreamBuilder<Duration>(
              stream: widget.audioHandler.positionStream,
              builder: (context, posSnapshot) {
                final position = posSnapshot.data ?? Duration.zero;
                final duration = song.duration ?? Duration.zero;
                final maxSeconds = duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0;
                final currentSeconds =
                    position.inMilliseconds.toDouble().clamp(0.0, maxSeconds);

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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 6),

            // แผงปุ่มควบคุม: Shuffle, Previous, Play/Pause, Next, Repeat
            StreamBuilder<PlayerState>(
              stream: widget.audioHandler.playerStateStream,
              builder: (context, stateSnapshot) {
                final playerState = stateSnapshot.data;
                final isPlaying = playerState?.playing ?? false;
                final isProcessing =
                    playerState?.processingState == ProcessingState.loading ||
                    playerState?.processingState == ProcessingState.buffering;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // ปุ่มสุ่มเพลง (Shuffle)
                    StreamBuilder<bool>(
                      stream: widget.audioHandler.isShuffleStream,
                      builder: (context, snap) {
                        final isShuffle = snap.data ?? false;
                        return IconButton(
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: isShuffle ? const Color(0xFF818CF8) : const Color(0xFF475569),
                            size: 22,
                          ),
                          tooltip: isShuffle ? 'สุ่มเพลง: เปิด' : 'สุ่มเพลง: ปิด',
                          onPressed: () => widget.audioHandler.toggleShuffle(),
                        );
                      },
                    ),

                    // ปุ่มเพลงก่อนหน้า (Previous)
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                      onPressed: () => widget.audioHandler.skipToPrevious(),
                    ),

                    // ปุ่ม Play/Pause กลางเด่น
                    GestureDetector(
                      onTap: () {
                        if (isPlaying) {
                          widget.audioHandler.pause();
                        } else {
                          widget.audioHandler.play();
                        }
                      },
                      child: Container(
                        width: 60,
                        height: 60,
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
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 34,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),

                    // ปุ่มเพลงถัดไป (Next)
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                      onPressed: () => widget.audioHandler.skipToNext(),
                    ),

                    // ปุ่มวนซ้ำ (Repeat Mode)
                    StreamBuilder<LoopModeType>(
                      stream: widget.audioHandler.loopModeStream,
                      builder: (context, snap) {
                        final mode = snap.data ?? LoopModeType.all;
                        IconData icon;
                        Color color;
                        String tip;
                        switch (mode) {
                          case LoopModeType.all:
                            icon = Icons.repeat_rounded;
                            color = const Color(0xFF818CF8);
                            tip = 'วนซ้ำทั้งคิว';
                            break;
                          case LoopModeType.one:
                            icon = Icons.repeat_one_rounded;
                            color = const Color(0xFF818CF8);
                            tip = 'วนซ้ำเพลงเดิม';
                            break;
                          case LoopModeType.off:
                            icon = Icons.repeat_rounded;
                            color = const Color(0xFF475569);
                            tip = 'ไม่วนซ้ำ';
                            break;
                        }
                        return IconButton(
                          icon: Icon(icon, color: color, size: 22),
                          tooltip: tip,
                          onPressed: () => widget.audioHandler.toggleRepeatMode(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _showPlaylistModal(BuildContext context) {
    PlaylistBottomSheet.show(
      context,
      audioHandler: widget.audioHandler,
      onImportSongs: _handleImportSongs,
      onImportLrc: _handleImportLrc,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatSeconds(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
