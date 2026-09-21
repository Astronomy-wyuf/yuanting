/// 下载任务状态
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed;

  String get label {
    switch (this) {
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
    }
  }

  static DownloadStatus fromString(String? s) {
    switch (s) {
      case 'pending':
        return DownloadStatus.pending;
      case 'downloading':
        return DownloadStatus.downloading;
      case 'paused':
        return DownloadStatus.paused;
      case 'completed':
        return DownloadStatus.completed;
      case 'failed':
        return DownloadStatus.failed;
      default:
        return DownloadStatus.pending;
    }
  }
}

/// 下载任务
class DownloadTask {
  /// copyWith 哨兵：传入可清空的可空字段
  static const Object unset = Object();

  final String id;
  final String chapterId;
  final String bookId;

  /// 冗余展示字段（下载列表 UI 直接显示，不再回查书籍表）
  final String bookTitle;
  final String chapterTitle;

  /// 下载源地址
  final String url;

  /// 本地保存路径
  final String? localPath;
  final DownloadStatus status;

  /// 0~100
  final int progress;
  final int? totalBytes;
  final int downloadedBytes;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? error;

  const DownloadTask({
    required this.id,
    required this.chapterId,
    required this.bookId,
    required this.bookTitle,
    required this.chapterTitle,
    required this.url,
    this.localPath,
    required this.status,
    this.progress = 0,
    this.totalBytes,
    this.downloadedBytes = 0,
    required this.createdAt,
    this.completedAt,
    this.error,
  });

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.pending;

  DownloadTask copyWith({
    String? id,
    String? chapterId,
    String? bookId,
    String? bookTitle,
    String? chapterTitle,
    String? url,
    String? localPath,
    DownloadStatus? status,
    int? progress,
    Object? totalBytes = unset,
    int? downloadedBytes,
    DateTime? createdAt,
    Object? completedAt = unset,
    Object? error = unset,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      bookId: bookId ?? this.bookId,
      bookTitle: bookTitle ?? this.bookTitle,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalBytes: identical(totalBytes, unset)
          ? this.totalBytes
          : totalBytes as int?,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      createdAt: createdAt ?? this.createdAt,
      completedAt: identical(completedAt, unset)
          ? this.completedAt
          : completedAt as DateTime?,
      error: identical(error, unset) ? this.error : error as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'chapter_id': chapterId,
        'book_id': bookId,
        'book_title': bookTitle,
        'chapter_title': chapterTitle,
        'url': url,
        'local_path': localPath,
        'status': status.name,
        'progress': progress,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'completed_at': completedAt?.millisecondsSinceEpoch,
        'error': error,
      };

  factory DownloadTask.fromMap(Map<String, dynamic> map) => DownloadTask(
        id: map['id'] as String,
        chapterId: map['chapter_id'] as String,
        bookId: map['book_id'] as String,
        bookTitle: map['book_title'] as String? ?? '',
        chapterTitle: map['chapter_title'] as String? ?? '',
        url: map['url'] as String? ?? '',
        localPath: map['local_path'] as String?,
        status: DownloadStatus.fromString(map['status'] as String?),
        progress: (map['progress'] as num?)?.toInt() ?? 0,
        totalBytes: (map['total_bytes'] as num?)?.toInt(),
        downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['created_at'] as num?)?.toInt() ?? 0),
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (map['completed_at'] as num).toInt()),
        error: map['error'] as String?,
      );
}

/// 按书籍聚合的下载摘要（一级列表）
class DownloadBookGroup {
  final String bookId;
  final String bookTitle;
  final List<DownloadTask> tasks;

  const DownloadBookGroup({
    required this.bookId,
    required this.bookTitle,
    required this.tasks,
  });

  int get total => tasks.length;
  int get done =>
      tasks.where((t) => t.status == DownloadStatus.completed).length;
  int get active => tasks.where((t) => t.isActive).length;
  int get failed =>
      tasks.where((t) => t.status == DownloadStatus.failed).length;
  int get paused =>
      tasks.where((t) => t.status == DownloadStatus.paused).length;
  int get bytes => tasks.fold(0, (s, t) => s + t.downloadedBytes);
  double get progressRatio => total == 0 ? 0 : done / total;

  bool get hasActive => active > 0;
  bool get hasFailed => failed > 0;
  bool get allPausedOrDone =>
      tasks.every((t) =>
          t.status == DownloadStatus.paused ||
          t.status == DownloadStatus.completed);
}
