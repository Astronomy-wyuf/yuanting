import 'book.dart';

/// 搜索结果条目
class SearchRecord {
  final String sourceId;
  final String sourceName;

  /// 站内书籍标识（书源 fields 中的 bookId / id 字段）
  final String sourceBookId;
  final String title;
  final String? author;

  /// 播音 / 主播（书源 fields.narrator 或 teller）
  final String? narrator;
  final String? coverUrl;
  final String detailUrl;

  /// 分类名（可选）
  final String? category;

  /// 章节数展示（可选，字符串即可）
  final String? chapterCount;

  const SearchRecord({
    required this.sourceId,
    required this.sourceName,
    required this.sourceBookId,
    required this.title,
    this.author,
    this.narrator,
    this.coverUrl,
    this.detailUrl = '',
    this.category,
    this.chapterCount,
  });

  /// 用列表字段拼瞬时 Book，详情页再后台补全简介等。
  Book toBook() {
    final now = DateTime.now();
    final total = int.tryParse(
      (chapterCount ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    );
    return Book(
      id: Book.buildId(sourceId, sourceBookId),
      sourceId: sourceId,
      sourceBookId: sourceBookId,
      title: title,
      author: author,
      coverUrl: coverUrl,
      detailUrl: detailUrl,
      addedAt: now,
      updatedAt: now,
      totalChapters: total != null && total > 0 ? total : null,
    );
  }

  /// 副标题：作者 · 播音（缺省自动省略；分类另字段展示）
  String get subtitleLine {
    final a = author?.trim();
    final n = narrator?.trim();
    final parts = <String>[
      if (a != null && a.isNotEmpty) a,
      if (n != null && n.isNotEmpty && n != a) '播$n',
    ];
    if (parts.isEmpty) {
      final c = category?.trim();
      if (c != null && c.isNotEmpty) return c;
      return '有声';
    }
    return parts.join(' · ');
  }

  /// 作者行（可空）
  String? get authorLine {
    final a = author?.trim();
    return (a != null && a.isNotEmpty) ? a : null;
  }

  /// 播音行（可空；与作者相同时仍返回，便于 UI 标注「播」）
  String? get narratorLine {
    final n = narrator?.trim();
    return (n != null && n.isNotEmpty) ? n : null;
  }

  SearchRecord copyWith({
    String? sourceId,
    String? sourceName,
    String? sourceBookId,
    String? title,
    String? author,
    String? narrator,
    String? coverUrl,
    String? detailUrl,
    String? category,
    String? chapterCount,
  }) {
    return SearchRecord(
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sourceBookId: sourceBookId ?? this.sourceBookId,
      title: title ?? this.title,
      author: author ?? this.author,
      narrator: narrator ?? this.narrator,
      coverUrl: coverUrl ?? this.coverUrl,
      detailUrl: detailUrl ?? this.detailUrl,
      category: category ?? this.category,
      chapterCount: chapterCount ?? this.chapterCount,
    );
  }
}
