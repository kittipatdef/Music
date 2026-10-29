import 'package:flutter/material.dart';
import '../models/playlist_model.dart';
import '../models/song_item.dart';
import '../services/audio_handler.dart';
import 'download_dialog.dart';

/// Bottom Sheet สำหรับจัดการรายการเพลง (Now Playing Queue) และเพลย์ลิสต์หลายรายการ (Multiple Custom Playlists)
class PlaylistBottomSheet extends StatefulWidget {
  final MyAudioHandler audioHandler;
  final VoidCallback onImportSongs;
  final Function(SongItem) onImportLrc;

  const PlaylistBottomSheet({
    super.key,
    required this.audioHandler,
    required this.onImportSongs,
    required this.onImportLrc,
  });

  static void show(
    BuildContext context, {
    required MyAudioHandler audioHandler,
    required VoidCallback onImportSongs,
    required Function(SongItem) onImportLrc,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: PlaylistBottomSheet(
          audioHandler: audioHandler,
          onImportSongs: onImportSongs,
          onImportLrc: onImportLrc,
        ),
      ),
    );
  }

  @override
  State<PlaylistBottomSheet> createState() => _PlaylistBottomSheetState();
}

class _PlaylistBottomSheetState extends State<PlaylistBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CustomPlaylist? _selectedPlaylistDetail;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Dialog สร้าง Playlist ใหม่ ---
  void _showCreatePlaylistDialog(BuildContext context, {SongItem? initialSong}) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8)),
            SizedBox(width: 10),
            Text('สร้างเพลย์ลิสต์ใหม่', style: TextStyle(fontSize: 18, color: Colors.white)),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ชื่อเพลย์ลิสต์ (เช่น เพลงโปรด, ฟังสบาย)',
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF101016),
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
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('เปลี่ยนชื่อเพลย์ลิสต์', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF101016),
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
                  setState(() {
                    if (_selectedPlaylistDetail?.id == playlist.id) {
                      _selectedPlaylistDetail = _selectedPlaylistDetail?.copyWith(name: newName);
                    }
                  });
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

  // --- Dialog เพิ่มเพลงเข้า Playlist ---
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
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
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
                  const SizedBox(height: 6),
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
                              child: const Icon(Icons.queue_music_rounded, color: Color(0xFF818CF8), size: 20),
                            ),
                            title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${pl.songIds.length} เพลง',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                            trailing: hasSong
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22)
                                : const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF818CF8), size: 22),
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
  void _showSongOptions(BuildContext context, SongItem song, int index, {bool isInCustomPlaylist = false, CustomPlaylist? playlist}) {
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
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
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
                title: const Text('เพิ่มเข้าเพลย์ลิสต์...', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToPlaylistDialog(context, song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_rounded, color: Color(0xFF818CF8)),
                title: const Text('เลือกไฟล์เนื้อเพลง .lrc ให้เพลงนี้', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onImportLrc(song);
                },
              ),
              if (isInCustomPlaylist && playlist != null)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  title: const Text('นำออกจากเพลย์ลิสต์นี้', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.audioHandler.removeSongFromCustomPlaylist(playlist.id, song.id);
                    setState(() {
                      _selectedPlaylistDetail = widget.audioHandler.customPlaylists
                          .where((p) => p.id == playlist.id)
                          .firstOrNull;
                    });
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('ลบออกจากคิวเล่นปัจจุบัน', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.audioHandler.removeSongAtIndex(index);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // หากกำลังเจาะจงดูรายละเอียดเพลย์ลิสต์ใดเพลย์ลิสต์หนึ่ง
    if (_selectedPlaylistDetail != null) {
      return _buildPlaylistDetailView(_selectedPlaylistDetail!);
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        // Handle bar
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF334155),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),

        // Tabs: คิวเล่นปัจจุบัน & เพลย์ลิสต์ของฉัน
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFF6366F1),
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  tabs: const [
                    Tab(text: 'คิวเล่นปัจจุบัน'),
                    Tab(text: 'เพลย์ลิสต์ของฉัน'),
                  ],
                ),
              ),
              // ปุ่มดาวน์โหลดออนไลน์
              IconButton(
                icon: const Icon(Icons.cloud_download_rounded, color: Color(0xFF818CF8), size: 22),
                tooltip: 'ดาวน์โหลดจากลิงก์',
                onPressed: () {
                  Navigator.pop(context);
                  DownloadDialog.show(context, widget.audioHandler);
                },
              ),
              // ปุ่มเลือกเพลงจากเครื่อง
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
                tooltip: 'เพิ่มเพลงจากเครื่อง',
                onPressed: () {
                  Navigator.pop(context);
                  widget.onImportSongs();
                },
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E293B), height: 1),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildQueueView(),
              _buildMyPlaylistsView(),
            ],
          ),
        ),
      ],
    );
  }

  // --- มุมมอง Tab 1: คิวเพลงปัจจุบัน ---
  Widget _buildQueueView() {
    return StreamBuilder<List<SongItem>>(
      stream: widget.audioHandler.playlistStream,
      builder: (context, snapshot) {
        final playlist = snapshot.data ?? [];

        if (playlist.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.music_off_outlined, color: Color(0xFF475569), size: 48),
                const SizedBox(height: 12),
                const Text('ไม่มีเพลงในคิวปัจจุบัน', style: TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onImportSongs();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่มเพลงจากเครื่อง'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF818CF8)),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: playlist.length,
          itemBuilder: (context, idx) {
            final item = playlist[idx];
            final isPlayingThis = widget.audioHandler.currentIndex == idx;

            return Dismissible(
              key: Key(item.id + idx.toString()),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red.withValues(alpha: 0.8),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) {
                widget.audioHandler.removeSongAtIndex(idx);
              },
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFF1E1E28),
                    image: item.coverArt != null
                        ? DecorationImage(
                            image: MemoryImage(item.coverArt!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: item.coverArt == null
                      ? Icon(
                          isPlayingThis ? Icons.volume_up_rounded : Icons.music_note_rounded,
                          color: isPlayingThis ? const Color(0xFF6366F1) : const Color(0xFF475569),
                          size: 20,
                        )
                      : null,
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
                  onPressed: () => _showSongOptions(context, item, idx),
                  tooltip: 'ตัวเลือกเพิ่มเติม',
                ),
                onTap: () {
                  widget.audioHandler.playSongAtIndex(idx);
                  Navigator.pop(context);
                },
              ),
            );
          },
        );
      },
    );
  }

  // --- มุมมอง Tab 2: เพลย์ลิสต์ของฉัน (My Playlists) ---
  Widget _buildMyPlaylistsView() {
    return StreamBuilder<List<CustomPlaylist>>(
      stream: widget.audioHandler.customPlaylistsStream,
      builder: (context, snapPlaylists) {
        final customLists = snapPlaylists.data ?? [];

        return StreamBuilder<List<SongItem>>(
          stream: widget.audioHandler.masterLibraryStream,
          builder: (context, snapMaster) {
            final masterSongs = snapMaster.data ?? [];

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ปุ่มสร้าง Playlist ใหม่
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ElevatedButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('สร้างเพลย์ลิสต์ใหม่'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF28283C),
                      foregroundColor: const Color(0xFF818CF8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // Item 1: เพลงทั้งหมดในคลัง (All Songs)
                Card(
                  color: const Color(0xFF181824),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 26),
                    ),
                    title: const Text('เพลงทั้งหมดในคลัง (All Songs)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text('${masterSongs.length} เพลง',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    trailing: ElevatedButton.icon(
                      onPressed: masterSongs.isEmpty
                          ? null
                          : () {
                              widget.audioHandler.playAllMasterSongs();
                              Navigator.pop(context);
                            },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('เล่นทั้งหมด'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),

                if (customLists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.library_music_outlined, size: 42, color: Color(0xFF334155)),
                          SizedBox(height: 10),
                          Text('ยังไม่มีเพลย์ลิสต์ที่คุณสร้าง',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                          SizedBox(height: 4),
                          Text('กดปุ่ม "+ สร้างเพลย์ลิสต์ใหม่" ด้านบนเพื่อเริ่มจัดหมวดหมู่เพลง',
                              style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                else
                  ...customLists.map((pl) {
                    return Card(
                      color: const Color(0xFF181824),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF252538),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.queue_music_rounded, color: Color(0xFF818CF8), size: 26),
                        ),
                        title: Text(
                          pl.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          '${pl.songIds.length} เพลง',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill_rounded,
                                  color: Color(0xFF6366F1), size: 36),
                              tooltip: 'เล่นเพลย์ลิสต์นี้',
                              onPressed: pl.songIds.isEmpty
                                  ? null
                                  : () {
                                      widget.audioHandler.playCustomPlaylist(pl);
                                      Navigator.pop(context);
                                    },
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                              color: const Color(0xFF1F1F2E),
                              onSelected: (val) {
                                if (val == 'rename') {
                                  _showRenamePlaylistDialog(context, pl);
                                } else if (val == 'delete') {
                                  widget.audioHandler.deleteCustomPlaylist(pl.id);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('เปลี่ยนชื่อ', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      SizedBox(width: 8),
                                      Text('ลบเพลย์ลิสต์', style: TextStyle(color: Colors.redAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedPlaylistDetail = pl;
                          });
                        },
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  // --- มุมมองดูเพลงในเพลย์ลิสต์ที่เลือก (Playlist Detail View) ---
  Widget _buildPlaylistDetailView(CustomPlaylist pl) {
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
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header ย้อนกลับและชื่อเพลย์ลิสต์
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedPlaylistDetail = null;
                      });
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pl.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text('${songsInPlaylist.length} เพลง',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: songsInPlaylist.isEmpty
                        ? null
                        : () {
                            widget.audioHandler.playCustomPlaylist(pl);
                            Navigator.pop(context);
                          },
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
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.queue_music_outlined, size: 48, color: Color(0xFF334155)),
                          SizedBox(height: 12),
                          Text('เพลย์ลิสต์นี้ยังไม่มีเพลง',
                              style: TextStyle(color: Color(0xFF64748B))),
                          SizedBox(height: 8),
                          Text(
                            'คุณสามารถกด ⋮ ที่เพลงในคิว แล้วเลือก "เพิ่มเข้าเพลย์ลิสต์..." ได้',
                            style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: songsInPlaylist.length,
                      itemBuilder: (context, idx) {
                        final song = songsInPlaylist[idx];
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
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
                                    color: Color(0xFF6366F1), size: 20)
                                : null,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
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
                                isInCustomPlaylist: true, playlist: pl),
                          ),
                          onTap: () {
                            widget.audioHandler.playCustomPlaylist(pl, initialIndex: idx);
                            Navigator.pop(context);
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
}
