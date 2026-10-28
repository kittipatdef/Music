import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song_item.dart';

/// Service จัดการเครื่องเล่นเสียงเบื้องหลัง (Background Audio Handler)
/// เชื่อมต่อกับ Android Foreground Service และ Lock Screen Controls
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  // จัดเก็บรายการเพลงในคิว
  final BehaviorSubject<List<SongItem>> _playlistSubject =
      BehaviorSubject<List<SongItem>>.seeded([]);
  Stream<List<SongItem>> get playlistStream => _playlistSubject.stream;
  List<SongItem> get playlist => _playlistSubject.value;

  // จัดเก็บเพลงปัจจุบัน
  final BehaviorSubject<SongItem?> _currentSongSubject =
      BehaviorSubject<SongItem?>.seeded(null);
  Stream<SongItem?> get currentSongStream => _currentSongSubject.stream;
  SongItem? get currentSong => _currentSongSubject.value;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  MyAudioHandler() {
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    // 1. ส่งสถานะจาก just_audio ไปยัง audio_service (สำหรับ Notification & Lock Screen)
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 3], // Previous, Play/Pause, Next
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: _currentIndex,
        ),
      );
    });

    // 2. จัดการเมื่อเพลงเล่นจบ (Auto-play เพลงถัดไป)
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });

    // 3. ติดตาม Duration ที่แท้จริงจากไฟล์เสียง
    _player.durationStream.listen((newDuration) {
      if (newDuration != null && currentSong != null) {
        final updated = currentSong!.copyWith(duration: newDuration);
        _currentSongSubject.add(updated);
        mediaItem.add(updated.toMediaItem());
      }
    });
  }

  // --- Queue & Playlist Management ---

  /// กำหนดรายการเพลงใหม่ลงในคิว
  void setPlaylist(List<SongItem> songs, {int initialIndex = 0}) {
    _playlistSubject.add(songs);
    queue.add(songs.map((e) => e.toMediaItem()).toList());

    if (songs.isNotEmpty && initialIndex >= 0 && initialIndex < songs.length) {
      playSongAtIndex(initialIndex);
    }
  }

  /// เพิ่มเพลงใหม่เข้าไปในคิว
  void addSong(SongItem song) {
    final currentList = List<SongItem>.from(playlist);
    currentList.add(song);
    _playlistSubject.add(currentList);
    queue.add(currentList.map((e) => e.toMediaItem()).toList());

    if (currentList.length == 1) {
      playSongAtIndex(0);
    }
  }

  /// อัปเดตข้อมูลเนื้อเพลงให้กับเพลงในคิว
  void updateSongLyrics(String songId, SongItem updatedSong) {
    final list = List<SongItem>.from(playlist);
    final idx = list.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      list[idx] = updatedSong;
      _playlistSubject.add(list);
      if (_currentIndex == idx) {
        _currentSongSubject.add(updatedSong);
      }
    }
  }

  /// เล่นเพลงตาม Index ที่ระบุ
  Future<void> playSongAtIndex(int index) async {
    if (index < 0 || index >= playlist.length) return;

    _currentIndex = index;
    final song = playlist[index];
    _currentSongSubject.add(song);
    mediaItem.add(song.toMediaItem());

    try {
      // โหลดไฟล์เสียงออฟไลน์จาก Local Path
      await _player.setFilePath(song.audioPath);
      _player.play();
    } catch (e) {
      // ignore: avoid_print
      print('Error playing audio file: $e');
    }
  }

  // --- Media Controls Callbacks (คำสั่งจากหน้าจอ/Notification/หูฟัง) ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (playlist.isEmpty) return;
    int nextIndex = _currentIndex + 1;
    if (nextIndex >= playlist.length) {
      nextIndex = 0; // วนกลับไปเพลงแรก
    }
    await playSongAtIndex(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (playlist.isEmpty) return;

    // ถ้าเล่นเพลงไปเกิน 3 วินาที ให้กรอกลับไปต้นเพลงก่อน
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    int prevIndex = _currentIndex - 1;
    if (prevIndex < 0) {
      prevIndex = playlist.length - 1; // วนไปเพลงสุดท้าย
    }
    await playSongAtIndex(prevIndex);
  }

  // Stream สำหรับ UI ติดตามตำแหน่งเวลาปัจจุบัน
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
}
