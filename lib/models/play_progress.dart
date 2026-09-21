/// 播放进度（每章一条记录）
class PlayProgress {
  final String chapterId;
  final String bookId;

  /// 当前播放位置（秒）
  final double currentTime;

  /// 章节总时长（秒）
  final double duration;
  final DateTime updatedAt;

  const PlayProgress({
    required this.chapterId,
    required this.bookId,
    required this.currentTime,
    required this.duration,
    required this.updatedAt,
  });

  PlayProgress copyWith({
    String? chapterId,
    String? bookId,
    double? currentTime,
    double? duration,
    DateTime? updatedAt,
  }) {
    return PlayProgress(
      chapterId: chapterId ?? this.chapterId,
      bookId: bookId ?? this.bookId,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 是否已基本听完（用于「继续收听」时自动跳到下一集）
  bool get isNearlyFinished =>
      duration > 0 && currentTime >= duration - 2;

  Map<String, dynamic> toMap() => {
        'chapter_id': chapterId,
        'book_id': bookId,
        'current_time': currentTime,
        'duration': duration,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory PlayProgress.fromMap(Map<String, dynamic> map) => PlayProgress(
        chapterId: map['chapter_id'] as String,
        bookId: map['book_id'] as String,
        currentTime: (map['current_time'] as num?)?.toDouble() ?? 0,
        duration: (map['duration'] as num?)?.toDouble() ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['updated_at'] as num?)?.toInt() ?? 0),
      );
}
