/// 书架书籍（也用于播放会话的瞬时对象）
class Book {
  /// 主键：`${sourceId}::${sourceBookId}`，未入书架的瞬时书籍同样使用此规则生成
  final String id;
  final String sourceId;
  final String sourceBookId;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? description;

  /// 书籍详情页地址（用于章节抓取的上下文）
  final String detailUrl;
  final DateTime addedAt;
  final DateTime updatedAt;
  final String? lastPlayChapterId;
  final DateTime? lastPlayTime;
  final int? totalChapters;

  /// 书籍级片头跳过秒数；null = 使用书源默认，书源未配置则用全局默认
  final int? skipIntro;

  /// 书籍级片尾跳过秒数；null = 使用书源默认
  final int? skipOutro;

  const Book({
    required this.id,
    required this.sourceId,
    required this.sourceBookId,
    required this.title,
    this.author,
    this.coverUrl,
    this.description,
    required this.detailUrl,
    required this.addedAt,
    required this.updatedAt,
    this.lastPlayChapterId,
    this.lastPlayTime,
    this.totalChapters,
    this.skipIntro,
    this.skipOutro,
  });

  static String buildId(String sourceId, String sourceBookId) => '$sourceId::$sourceBookId';

  static const Object _unset = Object();

  Book copyWith({
    String? id,
    String? sourceId,
    String? sourceBookId,
    String? title,
    Object? author = _unset,
    Object? coverUrl = _unset,
    Object? description = _unset,
    String? detailUrl,
    DateTime? addedAt,
    DateTime? updatedAt,
    Object? lastPlayChapterId = _unset,
    Object? lastPlayTime = _unset,
    Object? totalChapters = _unset,
    Object? skipIntro = _unset,
    Object? skipOutro = _unset,
  }) {
    return Book(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceBookId: sourceBookId ?? this.sourceBookId,
      title: title ?? this.title,
      author: identical(author, _unset) ? this.author : author as String?,
      coverUrl: identical(coverUrl, _unset) ? this.coverUrl : coverUrl as String?,
      description:
          identical(description, _unset) ? this.description : description as String?,
      detailUrl: detailUrl ?? this.detailUrl,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPlayChapterId: identical(lastPlayChapterId, _unset)
          ? this.lastPlayChapterId
          : lastPlayChapterId as String?,
      lastPlayTime:
          identical(lastPlayTime, _unset) ? this.lastPlayTime : lastPlayTime as DateTime?,
      totalChapters: identical(totalChapters, _unset)
          ? this.totalChapters
          : totalChapters as int?,
      skipIntro: identical(skipIntro, _unset) ? this.skipIntro : skipIntro as int?,
      skipOutro: identical(skipOutro, _unset) ? this.skipOutro : skipOutro as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'source_id': sourceId,
        'source_book_id': sourceBookId,
        'title': title,
        'author': author,
        'cover_url': coverUrl,
        'description': description,
        'detail_url': detailUrl,
        'added_at': addedAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'last_play_chapter_id': lastPlayChapterId,
        'last_play_time': lastPlayTime?.millisecondsSinceEpoch,
        'total_chapters': totalChapters,
        'skip_intro': skipIntro,
        'skip_outro': skipOutro,
      };

  factory Book.fromMap(Map<String, dynamic> map) => Book(
        id: map['id'] as String,
        sourceId: map['source_id'] as String,
        sourceBookId: map['source_book_id'] as String? ?? '',
        title: map['title'] as String? ?? '未命名',
        author: map['author'] as String?,
        coverUrl: map['cover_url'] as String?,
        description: map['description'] as String?,
        detailUrl: map['detail_url'] as String? ?? '',
        addedAt: DateTime.fromMillisecondsSinceEpoch((map['added_at'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((map['updated_at'] as num?)?.toInt() ?? 0),
        lastPlayChapterId: map['last_play_chapter_id'] as String?,
        lastPlayTime: map['last_play_time'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((map['last_play_time'] as num).toInt()),
        totalChapters: (map['total_chapters'] as num?)?.toInt(),
        skipIntro: (map['skip_intro'] as num?)?.toInt(),
        skipOutro: (map['skip_outro'] as num?)?.toInt(),
      );
}
