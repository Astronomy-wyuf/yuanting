/// 章节音频
class Chapter {
  /// 主键：`${bookId}::${index}`
  final String id;
  final String bookId;
  final int index;
  final String title;

  /// 音频地址（对 direct 书源即最终播放地址；
  /// 对需要二次解析的书源，此字段为章节页地址，播放前经 audio 规则解析）
  final String audioUrl;

  /// 时长（秒），可空
  final int? duration;

  /// 文件大小（字节），可空
  final int? size;
  final String? pubDate;

  const Chapter({
    required this.id,
    required this.bookId,
    required this.index,
    required this.title,
    required this.audioUrl,
    this.duration,
    this.size,
    this.pubDate,
  });

  static String buildId(String bookId, int index) => '$bookId::$index';

  Chapter copyWith({
    String? id,
    String? bookId,
    int? index,
    String? title,
    String? audioUrl,
    int? duration,
    int? size,
    String? pubDate,
  }) {
    return Chapter(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      index: index ?? this.index,
      title: title ?? this.title,
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      pubDate: pubDate ?? this.pubDate,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'book_id': bookId,
        'idx': index,
        'title': title,
        'audio_url': audioUrl,
        'duration': duration,
        'size': size,
        'pub_date': pubDate,
      };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
        id: map['id'] as String,
        bookId: map['book_id'] as String,
        index: (map['idx'] as num?)?.toInt() ?? 0,
        title: map['title'] as String? ?? '',
        audioUrl: map['audio_url'] as String? ?? '',
        duration: (map['duration'] as num?)?.toInt(),
        size: (map['size'] as num?)?.toInt(),
        pubDate: map['pub_date'] as String?,
      );
}
