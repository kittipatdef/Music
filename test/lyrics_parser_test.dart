import 'package:flutter_test/flutter_test.dart';
import 'package:personal_offline_music_player/models/lyric_entry.dart';
import 'package:personal_offline_music_player/services/lyrics_parser.dart';

void main() {
  group('LyricsParser Tests', () {
    test('Parse standard LRC with centiseconds', () {
      const lrc = '''
[ti:Test Title]
[ar:Test Artist]
[00:05.50]Hello world
[00:12.80]Second line of song
''';
      final lyrics = LyricsParser.parse(lrc);
      expect(lyrics.length, 2);
      expect(lyrics[0].text, 'Hello world');
      expect(lyrics[0].timestamp, const Duration(seconds: 5, milliseconds: 500));
      expect(lyrics[1].text, 'Second line of song');
      expect(lyrics[1].timestamp, const Duration(seconds: 12, milliseconds: 800));
    });

    test('Parse LRC with 3-digit milliseconds', () {
      const lrc = '[01:23.456]Precision timing';
      final lyrics = LyricsParser.parse(lrc);
      expect(lyrics.length, 1);
      expect(lyrics[0].text, 'Precision timing');
      expect(lyrics[0].timestamp, const Duration(minutes: 1, seconds: 23, milliseconds: 456));
    });

    test('Parse repeated chorus with multiple timestamps on single line', () {
      const lrc = '[00:10.00][00:30.00]Chorus line';
      final lyrics = LyricsParser.parse(lrc);
      expect(lyrics.length, 2);
      expect(lyrics[0].timestamp, const Duration(seconds: 10));
      expect(lyrics[0].text, 'Chorus line');
      expect(lyrics[1].timestamp, const Duration(seconds: 30));
      expect(lyrics[1].text, 'Chorus line');
    });

    test('Ignore LRC metadata tags', () {
      const lrc = '''
[ti:Title]
[ar:Artist]
[al:Album]
[by:Author]
[offset:100]
[00:01.00]First real lyric
''';
      final lyrics = LyricsParser.parse(lrc);
      expect(lyrics.length, 1);
      expect(lyrics[0].text, 'First real lyric');
    });

    test('findActiveIndex correctly resolves lyric timestamps', () {
      final lyrics = [
        LyricEntry(timestamp: const Duration(seconds: 5), text: 'Line 1'),
        LyricEntry(timestamp: const Duration(seconds: 10), text: 'Line 2'),
        LyricEntry(timestamp: const Duration(seconds: 20), text: 'Line 3'),
      ];

      // Before first line (intro)
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 2)), -1);

      // Exactly at first line
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 5)), 0);

      // Between line 1 and line 2
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 8)), 0);

      // At line 2
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 10)), 1);

      // Between line 2 and line 3
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 15)), 1);

      // At or after line 3
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 20)), 2);
      expect(LyricsParser.findActiveIndex(lyrics, const Duration(seconds: 50)), 2);

      // Empty list
      expect(LyricsParser.findActiveIndex([], const Duration(seconds: 5)), -1);
    });
  });
}
