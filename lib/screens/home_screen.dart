import 'package:flutter/material.dart';
import '../models/playlist_model.dart';
import '../models/song_item.dart';
import '../services/audio_handler.dart';
import '../services/file_picker_service.dart';
import '../services/lyrics_parser.dart';
import '../widgets/download_dialog.dart';
import '../widgets/mini_player.dart';

/// หน้าหลักของแอปพลิเคชัน (Home Screen) สไตล์ Spotify
/// รวม Playlists แบบ 2-Column Grid โดยมี "ดาวน์โหลด" เป็นเพลย์ลิสต์แรก
/// และมี Mini Player แสดงเพลงที่เล่นล่าสุดลอยอยู่ด้านล่าง
class HomeScreen extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const HomeScreen({super.key, required this.audioHandler});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _activeCustomPlaylistId;
  bool _isViewingDownloaded = false;

  @override
  void initState() {
    super.initState();
    // ขอสิทธิ์แจ้งเตือน Notification และสิทธิ์เข้าถึงไฟล์ตั้งแต่เริ่มเปิดแอป
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FilePickerService.requestPermissions();
    });
  }

  // --- เลือกไฟล์เพลงจากเครื่อง ---
  Future<void> _handleImportSongs() async {
    final songs = await FilePickerService.pickAudioFiles();
    if (songs.isNotEmpty) {
      widget.audioHandler.addSongs(songs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เพิ่ม ${songs.length} เพลงเข้าคลังเรียบร้อยแล้ว'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  // --- เลือกไฟล์ .lrc ให้เพลง ---
  Future<void> _handleImportLrc(SongItem song) async {
    final path = await FilePickerService.pickLrcFile();
    if (path != null) {
      final lyrics = await LyricsParser.parseFile(path);
      final updated = song.copyWith(lrcPath: path, lyrics: lyrics);
      widget.audioHandler.updateSongLyrics(song.id, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เพิ่มเนื้อเพลงให้ "${song.title}" สำเร็จ (${lyrics.length} บรรทัด)'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  // --- Sleep Timer Dialog ---
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

  // --- Dialog สร้าง Playlist ใหม่ ---
  void _showCreatePlaylistDialog(BuildContext context, {SongItem? initialSong}) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8)),
            SizedBox(width: 10),
            Text('สร้างเพลย์ลิสต์ใหม่',
                style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ตั้งชื่อเพลย์ลิสต์ (เช่น T, เพลงโปรด)',
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF12121A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                final created = await widget.audioHandler.createCustomPlaylist(name);
                if (initialSong != null) {
                  await widget.audioHandler.addSongToCustomPlaylist(created.id, initialSong.id);
                }
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('สร้างเพลย์ลิสต์ "$name" สำเร็จ!'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('สร้าง'),
          ),
        ],
      ),
    );
  }

  // --- Dialog เปลี่ยนชื่อ Playlist ---
  void _showRenamePlaylistDialog(BuildContext context, CustomPlaylist playlist) {
    final textController = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('เปลี่ยนชื่อเพลย์ลิสต์',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF12121A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isNotEmpty) {
                await widget.audioHandler.renameCustomPlaylist(playlist.id, newName);
                if (context.mounted) {
                  Navigator.pop(ctx);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  // --- Dialog ยืนยันลบเพลงออกจากเครื่องถาวร ---
  void _confirmDeleteSongFromDevice(BuildContext context, SongItem song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('ลบเพลงออกจากเครื่อง',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'คุณแน่ใจหรือไม่ว่าต้องการลบเพลง "${song.title}" ออกจากเครื่องอย่างถาวร?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.audioHandler.removeSongFromMaster(song.id);
              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('ลบเพลง "${song.title}" ออกจากเครื่องแล้ว'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ลบเพลง'),
          ),
        ],
      ),
    );
  }

  // --- Sheet เลือกเพลงเข้าสู่ Custom Playlist ---
  void _showAddSongsToPlaylistPicker(BuildContext context, CustomPlaylist playlist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF181824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StreamBuilder<List<SongItem>>(
          stream: widget.audioHandler.masterLibraryStream,
          builder: (context, snapMaster) {
            final masterSongs = snapMaster.data ?? [];

            return FractionallySizedBox(
              heightFactor: 0.75,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
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
                          'เลือกเพลงเข้า "${playlist.name}"',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF282838), height: 1),
                  Expanded(
                    child: masterSongs.isEmpty
                        ? const Center(
                            child: Text('ไม่มีเพลงในรายการดาวน์โหลด',
                                style: TextStyle(color: Color(0xFF64748B))),
                          )
                        : ListView.builder(
                            itemCount: masterSongs.length,
                            itemBuilder: (context, idx) {
                              final song = masterSongs[idx];
                              final isAlreadyIn = playlist.songIds.contains(song.id);

                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222230),
                                    borderRadius: BorderRadius.circular(8),
                                    image: song.coverArt != null
                                        ? DecorationImage(
                                            image: MemoryImage(song.coverArt!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: song.coverArt == null
                                      ? const Icon(Icons.music_note_rounded,
                                          color: Color(0xFF6366F1), size: 20)
                                      : null,
                                ),
                                title: Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white)),
                                subtitle: Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                trailing: isAlreadyIn
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: Color(0xFF10B981), size: 24)
                                    : IconButton(
                                        icon: const Icon(Icons.add_circle_outline_rounded,
                                            color: Color(0xFF818CF8), size: 24),
                                        onPressed: () async {
                                          await widget.audioHandler
                                              .addSongToCustomPlaylist(playlist.id, song.id);
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('เพิ่ม "${song.title}" เข้าแล้ว!'),
                                                backgroundColor: const Color(0xFF10B981),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Sheet เพิ่มเพลงเข้า Playlist ---
  void _showAddToPlaylistDialog(BuildContext context, SongItem song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StreamBuilder<List<CustomPlaylist>>(
          stream: widget.audioHandler.customPlaylistsStream,
          builder: (context, snap) {
            final playlists = snap.data ?? [];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'เพิ่มเพลงเข้าเพลย์ลิสต์',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCreatePlaylistDialog(context, initialSong: song);
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('สร้างใหม่'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF818CF8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'เลือกเพลย์ลิสต์สำหรับ: ${song.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                  const Divider(color: Color(0xFF2E2E3A), height: 20),
                  if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'ยังไม่มีเพลย์ลิสต์ กด "+ สร้างใหม่" เพื่อเริ่มต้น',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        itemBuilder: (context, idx) {
                          final pl = playlists[idx];
                          final hasSong = pl.songIds.contains(song.id);

                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF282836),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.queue_music_rounded,
                                  color: Color(0xFF818CF8), size: 20),
                            ),
                            title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${pl.songIds.length} เพลง',
                                style: const TextStyle(
                                    color: Color(0xFF64748B), fontSize: 12)),
                            trailing: hasSong
                                ? const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF10B981), size: 22)
                                : const Icon(Icons.add_circle_outline_rounded,
                                    color: Color(0xFF818CF8), size: 22),
                            onTap: () async {
                              if (hasSong) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('เพลงนี้อยู่ใน "${pl.name}" แล้ว'),
                                    backgroundColor: const Color(0xFF1E293B),
                                  ),
                                );
                              } else {
                                await widget.audioHandler.addSongToCustomPlaylist(pl.id, song.id);
                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('เพิ่มเข้า "${pl.name}" สำเร็จ!'),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Options Menu ของเพลง ---
  void _showSongOptions(
    BuildContext context,
    SongItem song,
    int index, {
    bool isCustomPlaylist = false,
    CustomPlaylist? playlist,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF222230),
                        borderRadius: BorderRadius.circular(8),
                        image: song.coverArt != null
                            ? DecorationImage(
                                image: MemoryImage(song.coverArt!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: song.coverArt == null
                          ? const Icon(Icons.music_note_rounded, color: Color(0xFF6366F1))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF262636), height: 1),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8)),
                title: const Text('เพิ่มเข้าเพลย์ลิสต์อื่น...', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToPlaylistDialog(context, song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_rounded, color: Color(0xFF818CF8)),
                title: const Text('เลือกไฟล์เนื้อเพลง .lrc ให้เพลงนี้',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleImportLrc(song);
                },
              ),
              if (isCustomPlaylist && playlist != null)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  title: const Text('นำออกจากเพลย์ลิสต์นี้',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.audioHandler.removeSongFromCustomPlaylist(playlist.id, song.id);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('ลบเพลงนี้ออกจากเครื่อง',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteSongFromDevice(context, song);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistMenu(BuildContext context, CustomPlaylist pl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white),
              title: const Text('เปลี่ยนชื่อเพลย์ลิสต์', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenamePlaylistDialog(context, pl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('ลบเพลย์ลิสต์', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                widget.audioHandler.deleteCustomPlaylist(pl.id);
                if (_activeCustomPlaylistId == pl.id) {
                  setState(() => _activeCustomPlaylistId = null);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isViewingDownloaded && _activeCustomPlaylistId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isViewingDownloaded || _activeCustomPlaylistId != null) {
          setState(() {
            _isViewingDownloaded = false;
            _activeCustomPlaylistId = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D11),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _isViewingDownloaded || _activeCustomPlaylistId != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  onPressed: () {
                    setState(() {
                      _isViewingDownloaded = false;
                      _activeCustomPlaylistId = null;
                    });
                  },
                )
              : StreamBuilder<int?>(
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
                      tooltip: isActive ? 'ตั้งเวลาปิดเพลง' : 'ตั้งเวลาปิดเพลง',
                      onPressed: () => _showSleepTimerDialog(context),
                    );
                  },
                ),
          title: StreamBuilder<List<CustomPlaylist>>(
            stream: widget.audioHandler.customPlaylistsStream,
            builder: (context, snap) {
              String titleText = 'เพลย์ลิสต์';
              if (_isViewingDownloaded) {
                titleText = 'ดาวน์โหลด';
              } else if (_activeCustomPlaylistId != null) {
                final lists = snap.data ?? widget.audioHandler.customPlaylists;
                final found = lists.where((p) => p.id == _activeCustomPlaylistId).firstOrNull;
                titleText = found?.name ?? 'เพลย์ลิสต์';
              }
              return Text(
                titleText,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              );
            },
          ),
          actions: [
            if (_isViewingDownloaded || _activeCustomPlaylistId != null) ...[
              if (_activeCustomPlaylistId != null)
                StreamBuilder<List<CustomPlaylist>>(
                  stream: widget.audioHandler.customPlaylistsStream,
                  builder: (context, snap) {
                    final lists = snap.data ?? widget.audioHandler.customPlaylists;
                    final activePl = lists.where((p) => p.id == _activeCustomPlaylistId).firstOrNull;
                    if (activePl == null) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              color: Color(0xFF818CF8), size: 24),
                          tooltip: 'เพิ่มเพลงเข้าเพลย์ลิสต์นี้',
                          onPressed: () => _showAddSongsToPlaylistPicker(context, activePl),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                          onPressed: () => _showPlaylistMenu(context, activePl),
                        ),
                      ],
                    );
                  },
                ),
            ] else ...[
              // ปุ่มสร้างเพลย์ลิสต์
              ElevatedButton.icon(
                onPressed: () => _showCreatePlaylistDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('สร้างเพลย์ลิสต์'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF242436),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
              const SizedBox(width: 6),
              // ปุ่มดาวน์โหลดออนไลน์
              IconButton(
                icon: const Icon(Icons.cloud_download_rounded, color: Color(0xFF818CF8), size: 22),
                tooltip: 'ดาวน์โหลดจากลิงก์',
                onPressed: () => DownloadDialog.show(context, widget.audioHandler),
              ),
              // ปุ่มเลือกเพลงจากเครื่อง
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
                tooltip: 'เพิ่มเพลงจากเครื่อง',
                onPressed: _handleImportSongs,
              ),
            ],
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: SafeArea(
          child: MiniPlayer(audioHandler: widget.audioHandler),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isViewingDownloaded) {
      return _buildDownloadedDetailView();
    }
    if (_activeCustomPlaylistId != null) {
      return _buildCustomPlaylistDetailView(_activeCustomPlaylistId!);
    }
    return _buildSpotifyPlaylistsGridView();
  }

  // ==========================================
  // หน้าหลัก: รวม Playlist สไตล์ Spotify 2-Column Grid
  // ==========================================
  Widget _buildSpotifyPlaylistsGridView() {
    return StreamBuilder<List<CustomPlaylist>>(
      stream: widget.audioHandler.customPlaylistsStream,
      builder: (context, snapPlaylists) {
        final customLists = snapPlaylists.data ?? [];

        return StreamBuilder<List<SongItem>>(
          stream: widget.audioHandler.masterLibraryStream,
          builder: (context, snapMaster) {
            final downloadedSongs = snapMaster.data ?? [];

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.8,
                  children: [
                    // 🌟 การ์ดที่ 1: "ดาวน์โหลด" (เสมือน "เพลงที่ถูกใจ" ของ Spotify)
                    _buildSpotifyCard(
                      title: 'ดาวน์โหลด',
                      subtitle: '${downloadedSongs.length} เพลง',
                      leadingWidget: Container(
                        width: 56,
                        height: double.infinity,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                          gradient: LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.download_done_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _isViewingDownloaded = true;
                        });
                      },
                    ),

                    // 🌟 การ์ดเพลย์ลิสต์ที่ผู้ใช้สร้าง (เช่น T, เพลงโปรด)
                    ...customLists.map((pl) {
                      return _buildSpotifyCard(
                        title: pl.name,
                        subtitle: '${pl.songIds.length} เพลง',
                        leadingWidget: Container(
                          width: 56,
                          height: double.infinity,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                            color: Color(0xFF28283C),
                          ),
                          child: const Icon(
                            Icons.queue_music_rounded,
                            color: Color(0xFF818CF8),
                            size: 26,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _activeCustomPlaylistId = pl.id;
                          });
                        },
                        onLongPress: () {
                          _showPlaylistMenu(context, pl);
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  // การ์ดปุ่มเพลย์ลิสต์ ดีไซน์กะทัดรัดแบบ Spotify
  Widget _buildSpotifyCard({
    required String title,
    required String subtitle,
    required Widget leadingWidget,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Material(
      color: const Color(0xFF22222E),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: Colors.white10,
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // หน้าดูเพลงใน Playlist "ดาวน์โหลด"
  // ==========================================
  Widget _buildDownloadedDetailView() {
    return StreamBuilder<List<SongItem>>(
      stream: widget.audioHandler.masterLibraryStream,
      builder: (context, snapMaster) {
        final downloadedSongs = snapMaster.data ?? [];

        return Column(
          children: [
            // Action Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.download_done_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${downloadedSongs.length} เพลงที่โหลดไว้',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                  ),
                  ElevatedButton.icon(
                    onPressed: downloadedSongs.isEmpty
                        ? null
                        : () => widget.audioHandler.playAllMasterSongs(),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('เล่นทั้งหมด'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: 1),

            Expanded(
              child: downloadedSongs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_download_outlined,
                              size: 48, color: Color(0xFF334155)),
                          const SizedBox(height: 12),
                          const Text('ยังไม่มีเพลงที่ดาวน์โหลดไว้',
                              style: TextStyle(color: Color(0xFF64748B))),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => DownloadDialog.show(context, widget.audioHandler),
                                icon: const Icon(Icons.link_rounded),
                                label: const Text('วางลิงก์ดาวน์โหลด'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: _handleImportSongs,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('เลือกจากเครื่อง'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF818CF8),
                                  side: const BorderSide(color: Color(0xFF4338CA)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: downloadedSongs.length,
                      itemBuilder: (context, idx) {
                        final song = downloadedSongs[idx];
                        return ListTile(
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E28),
                              borderRadius: BorderRadius.circular(8),
                              image: song.coverArt != null
                                  ? DecorationImage(
                                      image: MemoryImage(song.coverArt!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: song.coverArt == null
                                ? const Icon(Icons.music_note_rounded,
                                    color: Color(0xFF6366F1), size: 22)
                                : null,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                            onPressed: () => _showSongOptions(context, song, idx),
                          ),
                          onTap: () {
                            widget.audioHandler.playAllMasterSongs(initialIndex: idx);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // หน้าดูเพลงใน Custom Playlist (เช่น T)
  // ==========================================
  Widget _buildCustomPlaylistDetailView(String playlistId) {
    return StreamBuilder<List<CustomPlaylist>>(
      stream: widget.audioHandler.customPlaylistsStream,
      builder: (context, snapPlaylists) {
        final playlists = snapPlaylists.data ?? widget.audioHandler.customPlaylists;
        final pl = playlists.where((p) => p.id == playlistId).firstOrNull;
        if (pl == null) {
          return const Center(
            child: Text('ไม่พบเพลย์ลิสต์นี้', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        return StreamBuilder<List<SongItem>>(
          stream: widget.audioHandler.masterLibraryStream,
          builder: (context, snapMaster) {
            final masterSongs = snapMaster.data ?? [];
            final songsInPlaylist = <SongItem>[];
            for (var sid in pl.songIds) {
              final found = masterSongs.where((s) => s.id == sid).firstOrNull;
              if (found != null) songsInPlaylist.add(found);
            }

            return Column(
              children: [
                // Action Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFF28283C),
                        ),
                        child: const Icon(Icons.queue_music_rounded, color: Color(0xFF818CF8), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('${songsInPlaylist.length} เพลง',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                      ),
                      ElevatedButton.icon(
                        onPressed: songsInPlaylist.isEmpty
                            ? null
                            : () => widget.audioHandler.playCustomPlaylist(pl),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('เล่น'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF1E293B), height: 1),

                Expanded(
                  child: songsInPlaylist.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.queue_music_outlined,
                                  size: 48, color: Color(0xFF334155)),
                              const SizedBox(height: 12),
                              const Text('เพลย์ลิสต์นี้ยังไม่มีเพลง',
                                  style: TextStyle(color: Color(0xFF64748B))),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => _showAddSongsToPlaylistPicker(context, pl),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('เลือกเพลงเข้าเพลย์ลิสต์นี้'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: songsInPlaylist.length,
                          itemBuilder: (context, idx) {
                            final song = songsInPlaylist[idx];
                            return Dismissible(
                              key: Key('${pl.id}_${song.id}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.red.withValues(alpha: 0.8),
                                child: const Icon(Icons.delete_outline, color: Colors.white),
                              ),
                              onDismissed: (_) async {
                                await widget.audioHandler.removeSongFromCustomPlaylist(pl.id, song.id);
                              },
                              child: ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E28),
                                    borderRadius: BorderRadius.circular(8),
                                    image: song.coverArt != null
                                        ? DecorationImage(
                                            image: MemoryImage(song.coverArt!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: song.coverArt == null
                                      ? const Icon(Icons.music_note_rounded,
                                          color: Color(0xFF6366F1), size: 22)
                                      : null,
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                                  onPressed: () => _showSongOptions(context, song, idx,
                                      isCustomPlaylist: true, playlist: pl),
                                ),
                                onTap: () {
                                  widget.audioHandler.playCustomPlaylist(pl, initialIndex: idx);
                                },
                              ),
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
}
