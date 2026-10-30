import 'package:flutter_test/flutter_test.dart';
import 'package:personal_offline_music_player/models/playlist_model.dart';
import 'package:personal_offline_music_player/models/lyric_entry.dart';
import 'package:personal_offline_music_player/models/song_item.dart';

void main() {
  group('Models Serialization and Logic Tests', () {
    test('LyricEntry Comparable ordering', () {
      final entry1 = LyricEntry(timestamp: const Duration(seconds: 10), text: 'Later');
      final entry2 = LyricEntry(timestamp: const Duration(seconds: 2), text: 'Earlier');

      final list = [entry1, entry2]..sort();
      expect(list.first.text, 'Earlier');
      expect(list.last.text, 'Later');
    });

    test('SongItem JSON serialization and deserialization', () {
      final original = SongItem(
        id: 'song_123',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        audioPath: '/data/user/0/music/bohemian.mp3',
        lrcPath: '/data/user/0/music/bohemian.lrc',
      );

      final json = original.toJson();
      final restored = SongItem.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.artist, original.artist);
      expect(restored.audioPath, original.audioPath);
      expect(restored.lrcPath, original.lrcPath);
    });

    test('SongItem toMediaItem conversion', () {
      final song = SongItem(
        id: 'path/to/song.mp3',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        audioPath: 'path/to/song.mp3',
        duration: const Duration(minutes: 3, seconds: 53),
      );

      final mediaItem = song.toMediaItem();
      expect(mediaItem.id, 'path/to/song.mp3');
      expect(mediaItem.title, 'Shape of You');
      expect(mediaItem.artist, 'Ed Sheeran');
      expect(mediaItem.duration, const Duration(minutes: 3, seconds: 53));
      expect(mediaItem.extras?['audioPath'], 'path/to/song.mp3');
    });

    test('CustomPlaylist JSON serialization and copyWith', () {
      final now = DateTime.now();
      final pl = CustomPlaylist(
        id: 'pl_001',
        name: 'Chill Vibes',
        createdAt: now,
        songIds: ['song1', 'song2'],
      );

      final json = pl.toJson();
      final restored = CustomPlaylist.fromJson(json);

      expect(restored.id, 'pl_001');
      expect(restored.name, 'Chill Vibes');
      expect(restored.songIds, ['song1', 'song2']);

      final updated = pl.copyWith(name: 'Workout Mix', songIds: ['song1', 'song2', 'song3']);
      expect(updated.name, 'Workout Mix');
      expect(updated.songIds.length, 3);
      expect(updated.id, pl.id);
    });
  });
}
