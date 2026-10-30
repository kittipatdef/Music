import 'package:flutter_test/flutter_test.dart';
import 'package:personal_offline_music_player/services/online_downloader_service.dart';

void main() {
  group('OnlineDownloaderService Tests', () {
    test('isSupportedUrl identifies valid YouTube URLs', () {
      expect(OnlineDownloaderService.isSupportedUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(OnlineDownloaderService.isSupportedUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(OnlineDownloaderService.isSupportedUrl('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
    });

    test('isSupportedUrl rejects Spotify, other platforms, and invalid URLs', () {
      expect(OnlineDownloaderService.isSupportedUrl('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT'), isFalse);
      expect(OnlineDownloaderService.isSupportedUrl('https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3'), isFalse);
      expect(OnlineDownloaderService.isSupportedUrl('https://google.com'), isFalse);
      expect(OnlineDownloaderService.isSupportedUrl('https://facebook.com/video'), isFalse);
      expect(OnlineDownloaderService.isSupportedUrl('just a random song title'), isFalse);
      expect(OnlineDownloaderService.isSupportedUrl(''), isFalse);
    });

    test('cleanSongTitle removes redundant tags from YouTube video titles', () {
      expect(
        OnlineDownloaderService.cleanSongTitle('Alan Walker - Faded (Official Music Video)'),
        'Alan Walker - Faded',
      );
      expect(
        OnlineDownloaderService.cleanSongTitle('Queen – Bohemian Rhapsody [Audio 4K]'),
        'Queen – Bohemian Rhapsody',
      );
      expect(
        OnlineDownloaderService.cleanSongTitle('Ed Sheeran - Shape of You (Official Lyric Video)'),
        'Ed Sheeran - Shape of You',
      );
    });

    test('sanitizeFilename removes illegal characters from filenames', () {
      expect(
        OnlineDownloaderService.sanitizeFilename('Song: Title/Name? <Special>*"|'),
        'Song_ Title_Name_ _Special____',
      );
      expect(
        OnlineDownloaderService.sanitizeFilename('Normal File Name'),
        'Normal File Name',
      );
    });
  });
}
