import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/song_item.dart';
import '../services/audio_handler.dart';
import '../services/online_downloader_service.dart';

class DownloadDialog extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const DownloadDialog({super.key, required this.audioHandler});

  static Future<void> show(BuildContext context, MyAudioHandler audioHandler) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DownloadDialog(audioHandler: audioHandler),
    );
  }

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String _statusText = '';
  double _progress = 0.0;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _urlController.text = data!.text!.trim();
        _errorMessage = null;
      });
    }
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'กรุณาวางลิงก์เพลงก่อน');
      return;
    }

    if (!OnlineDownloaderService.isSupportedUrl(url)) {
      setState(() => _errorMessage = 'รองรับเฉพาะลิงก์ YouTube และ Spotify เท่านั้น');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusText = 'กำลังตรวจสอบลิงก์...';
      _progress = 0.05;
    });

    try {
      final meta = await OnlineDownloaderService.extractMetadata(url);
      setState(() {
        _statusText = 'พบเพลง: ${meta.title} - ${meta.artist}';
        _progress = 0.15;
      });

      final SongItem downloadedSong = await OnlineDownloaderService.downloadTrack(
        meta,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _statusText = status;
              _progress = progress;
            });
          }
        },
      );

      // เพิ่มเพลงเข้าสู่คิวและเริ่มเล่นทันที
      widget.audioHandler.addSong(downloadedSong);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ดาวน์โหลด "${downloadedSong.title}" สำเร็จ! (${downloadedSong.lyrics.isNotEmpty ? "มีเนื้อเพลงซิงค์" : "ไม่มีเนื้อเพลง"})',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.cloud_download_rounded, color: Color(0xFF818CF8), size: 24),
              SizedBox(width: 10),
              Text(
                'ดาวน์โหลดจากลิงก์',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'วางลิงก์จาก YouTube หรือ Spotify เพื่อดูดเพลงและเนื้อเพลงซิงค์ .lrc อัตโนมัติ',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),

          // ช่องใส่ URL
          TextField(
            controller: _urlController,
            enabled: !_isLoading,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'วางลิงก์ YouTube หรือ Spotify ที่นี่...',
              hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF1E1E28),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded, color: Color(0xFF818CF8)),
                tooltip: 'วางจากคลิปบอร์ด',
                onPressed: _isLoading ? null : _handlePaste,
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],

          if (_isLoading) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF2E2E3A),
                color: const Color(0xFF6366F1),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ปุ่มดาวน์โหลด
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _startDownload,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(
                _isLoading ? 'กำลังประมวลผล...' : 'เริ่มดาวน์โหลดเพลง',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
