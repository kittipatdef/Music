/// โมเดลสำหรับเพลย์ลิสต์ที่ผู้ใช้สร้างขึ้นเอง (Custom Playlist)
class CustomPlaylist {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<String> songIds;

  CustomPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.songIds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'songIds': songIds,
      };

  factory CustomPlaylist.fromJson(Map<String, dynamic> json) => CustomPlaylist(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled Playlist',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        songIds: (json['songIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );

  CustomPlaylist copyWith({
    String? name,
    List<String>? songIds,
  }) {
    return CustomPlaylist(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      songIds: songIds ?? this.songIds,
    );
  }
}
