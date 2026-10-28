import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song_item.dart';
import 'playlist_storage_service.dart';

enum LoopModeType { off, all, one }

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

  // โหมดสุ่มเพลง (Shuffle Mode)
  final BehaviorSubject<bool> _isShuffleSubject =
      BehaviorSubject<bool>.seeded(false);
  Stream<bool> get isShuffleStream => _isShuffleSubject.stream;
  bool get isShuffle => _isShuffleSubject.value;

  // โหมดเล่นซ้ำ (Repeat / Loop Mode: off, all, one)
  final BehaviorSubject<LoopModeType> _loopModeSubject =
      BehaviorSubject<LoopModeType>.seeded(LoopModeType.all);
  Stream<LoopModeType> get loopModeStream => _loopModeSubject.stream;
  LoopModeType get loopMode => _loopModeSubject.value;

  // Sleep Timer (เวลานับถอยหลังเป็นวินาที)
  final BehaviorSubject<int?> _sleepTimerRemainingSubject =
      BehaviorSubject<int?>.seeded(null);
  Stream<int?> get sleepTimerStream => _sleepTimerRemainingSubject.stream;
  Timer? _sleepCountdownTimer;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  MyAudioHandler() {
    _initAudioPlayer();
    _loadSavedPlaylistOnStartup();
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

    // 2. จัดการเมื่อเพลงเล่นจบ (Auto-play เพลงถัดไปตามโหมด Loop/Shuffle)
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompletion();
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

  /// โหลดเพลงที่เคยบันทึกไว้ในเครื่องขึ้นมาเมื่อเปิดแอป
  Future<void> _loadSavedPlaylistOnStartup() async {
    final saved = await PlaylistStorageService.loadPlaylist();
    if (saved.isNotEmpty) {
      _playlistSubject.add(saved);
      queue.add(saved.map((e) => e.toMediaItem()).toList());
      final lastId = await PlaylistStorageService.getLastPlayedSongId();
      int initialIndex = 0;
      if (lastId != null) {
        final idx = saved.indexWhere((s) => s.id == lastId);
        if (idx != -1) initialIndex = idx;
      }
      _currentIndex = initialIndex;
      final song = saved[initialIndex];
      _currentSongSubject.add(song);
      mediaItem.add(song.toMediaItem());
      try {
        await _player.setFilePath(song.audioPath);
      } catch (_) {}
    }
  }

  void _handleTrackCompletion() {
    if (playlist.isEmpty) return;

    if (loopMode == LoopModeType.one) {
      // วนเพลงเดิม
      seek(Duration.zero);
      play();
    } else if (loopMode == LoopModeType.all) {
      skipToNext();
    } else {
      // LoopModeType.off
      if (_currentIndex < playlist.length - 1) {
        skipToNext();
      } else {
        pause();
        seek(Duration.zero);
      }
    }
  }

  // --- Shuffle & Loop Mode Toggles ---

  void toggleShuffle() {
    _isShuffleSubject.add(!isShuffle);
  }

  void toggleRepeatMode() {
    switch (loopMode) {
      case LoopModeType.all:
        _loopModeSubject.add(LoopModeType.one);
        break;
      case LoopModeType.one:
        _loopModeSubject.add(LoopModeType.off);
        break;
      case LoopModeType.off:
        _loopModeSubject.add(LoopModeType.all);
        break;
    }
  }

  // --- Sleep Timer ---

  /// ตั้งเวลานับถอยหลังปิดเพลง (ระบุจำนวนนาที)
  void setSleepTimer(int minutes) {
    cancelSleepTimer();
    int secondsRemaining = minutes * 60;
    _sleepTimerRemainingSubject.add(secondsRemaining);

    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsRemaining--;
      if (secondsRemaining <= 0) {
        timer.cancel();
        _sleepTimerRemainingSubject.add(null);
        pause(); // หยุดเล่นเพลงเมื่อหมดเวลา
      } else {
        _sleepTimerRemainingSubject.add(secondsRemaining);
      }
    });
  }

  /// ยกเลิกการตั้งเวลาปิดเพลง
  void cancelSleepTimer() {
    _sleepCountdownTimer?.cancel();
    _sleepCountdownTimer = null;
    _sleepTimerRemainingSubject.add(null);
  }

  // --- Queue & Playlist Management ---

  /// กำหนดรายการเพลงใหม่ลงในคิว
  void setPlaylist(List<SongItem> songs, {int initialIndex = 0}) {
    _playlistSubject.add(songs);
    queue.add(songs.map((e) => e.toMediaItem()).toList());
    PlaylistStorageService.savePlaylist(songs);

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
    PlaylistStorageService.savePlaylist(currentList, lastPlayedId: currentSong?.id);

    if (currentList.length == 1) {
      playSongAtIndex(0);
    }
  }

  /// เพิ่มหลายเพลงเข้าคิว
  void addSongs(List<SongItem> songs) {
    final currentList = List<SongItem>.from(playlist);
    currentList.addAll(songs);
    _playlistSubject.add(currentList);
    queue.add(currentList.map((e) => e.toMediaItem()).toList());
    PlaylistStorageService.savePlaylist(currentList, lastPlayedId: currentSong?.id);

    if (_currentIndex == -1 && currentList.isNotEmpty) {
      playSongAtIndex(0);
    }
  }

  /// ลบเพลงออกจากคิว
  void removeSongAtIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    final currentList = List<SongItem>.from(playlist);
    currentList.removeAt(index);
    _playlistSubject.add(currentList);
    queue.add(currentList.map((e) => e.toMediaItem()).toList());
    PlaylistStorageService.savePlaylist(currentList, lastPlayedId: currentSong?.id);

    if (_currentIndex == index) {
      if (currentList.isNotEmpty) {
        playSongAtIndex(index.clamp(0, currentList.length - 1));
      } else {
        stop();
        _currentIndex = -1;
        _currentSongSubject.add(null);
      }
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
  }

  /// อัปเดตข้อมูลเนื้อเพลงให้กับเพลงในคิว
  void updateSongLyrics(String songId, SongItem updatedSong) {
    final list = List<SongItem>.from(playlist);
    final idx = list.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      list[idx] = updatedSong;
      _playlistSubject.add(list);
      PlaylistStorageService.savePlaylist(list, lastPlayedId: currentSong?.id);
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
    PlaylistStorageService.savePlaylist(playlist, lastPlayedId: song.id);

    try {
      await _player.setFilePath(song.audioPath);
      _player.play();
    } catch (e) {
      // ignore: avoid_print
      print('Error playing audio file: $e');
    }
  }

  // --- Media Controls Callbacks ---

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

    if (isShuffle && playlist.length > 1) {
      // สุ่มเพลงแบบไม่ซ้ำเพลงเดิม
      int nextIndex;
      do {
        nextIndex = Random().nextInt(playlist.length);
      } while (nextIndex == _currentIndex);
      await playSongAtIndex(nextIndex);
      return;
    }

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

  // Streams
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
}
