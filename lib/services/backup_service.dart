import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/book_source.dart';
import '../models/play_progress.dart';
import '../repositories/book_repository.dart';
import '../repositories/progress_repository.dart';
import '../repositories/source_repository.dart';

/// 本地备份（JSON 文件）：书架 + 播放进度 + 书源规则。
///
/// 文件格式：
/// ```json
/// {
///   "format": "yuanting-backup",
///   "version": 1,
///   "exportedAt": "2026-01-01T00:00:00",
///   "books":   [ {...Book.toMap 加 backupProgress} ],
///   "sources": [ {...BookSource.toMap} ]
/// }
/// ```
class BackupService {
  final BookRepository bookRepo;
  final ProgressRepository progressRepo;
  final SourceRepository sourceRepo;

  BackupService({
    required this.bookRepo,
    required this.progressRepo,
    required this.sourceRepo,
  });

  static const _format = 'yuanting-backup';
  static const _version = 1;

  // ---------------- 导出 ----------------

  /// 生成备份数据（也用于预览统计）
  Future<Map<String, dynamic>> buildPayload() async {
    final books = await bookRepo.listShelf();
    final sources = await sourceRepo.list();
    final bookMaps = <Map<String, dynamic>>[];
    for (final b in books) {
      final m = Map<String, dynamic>.from(b.toMap());
      // 附带该书全部播放进度，恢复时一并还原
      final progress = await progressRepo.listForBook(b.id);
      m['backupProgress'] =
          progress.map((e) => e.toMap()).toList();
      bookMaps.add(m);
    }
    return {
      'format': _format,
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': bookMaps,
      'sources': sources.map((s) => s.toMap()).toList(),
    };
  }

  /// 导出到用户选择的文件；返回保存路径（取消返回 null）
  Future<String?> exportToFile() async {
    final payload = await buildPayload();
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final stamp = DateTime.now();
    final suggested = 'yuanting_backup_'
        '${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}'
        '_${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}'
        '.json';

    final result = await FilePicker.platform.saveFile(
      fileName: suggested,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
    if (result == null) return null;
    // 移动端 saveFile 不写 bytes 时需手动落盘
    final file = File(result);
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsString(json);
    }
    return result;
  }

  // ---------------- 恢复 ----------------

  /// 从备份 JSON 恢复。返回统计；抛异常表示文件无效。
  Future<BackupStats> restoreFromMap(Map<String, dynamic> data) async {
    if (data['format'] != _format) {
      throw const FormatException('不是源听备份文件（format 不匹配）');
    }
    final booksRaw = data['books'];
    final sourcesRaw = data['sources'];
    if (booksRaw is! List || sourcesRaw is! List) {
      throw const FormatException('备份缺少 books / sources 字段');
    }

    var bookCount = 0;
    var progressCount = 0;
    var sourceCount = 0;

    for (final raw in sourcesRaw) {
      if (raw is! Map) continue;
      try {
        final source = BookSource.fromMap(Map<String, dynamic>.from(raw));
        await sourceRepo.upsert(source);
        sourceCount++;
      } catch (_) {}
    }

    for (final raw in booksRaw) {
      if (raw is! Map) continue;
      try {
        final map = Map<String, dynamic>.from(raw);
        final progressRaw = map.remove('backupProgress');
        final book = Book.fromMap(map);
        await bookRepo.upsert(book);
        bookCount++;
        if (progressRaw is List) {
          for (final pr in progressRaw) {
            if (pr is! Map) continue;
            try {
              await progressRepo
                  .save(PlayProgress.fromMap(Map<String, dynamic>.from(pr)));
              progressCount++;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return BackupStats(
      books: bookCount,
      progress: progressCount,
      sources: sourceCount,
    );
  }

  /// 从用户选择的文件恢复
  Future<BackupStats?> restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final path = result?.files.single.path;
    String text;
    if (result?.files.single.bytes != null &&
        result!.files.single.bytes!.isNotEmpty) {
      text = utf8.decode(result.files.single.bytes!, allowMalformed: true);
    } else if (path != null) {
      text = await File(path).readAsString();
    } else {
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('备份内容必须是 JSON 对象');
    }
    return restoreFromMap(Map<String, dynamic>.from(decoded));
  }

  /// 默认备份目录（应用文档目录 backups/，供「分享到本机」场景参考）
  Future<Directory> defaultBackupDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(doc.path, 'backups'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}

/// 恢复统计
class BackupStats {
  final int books;
  final int progress;
  final int sources;

  const BackupStats({
    required this.books,
    required this.progress,
    required this.sources,
  });

  String get label =>
      '书架 $books 本 · 进度 $progress 条 · 书源 $sources 个';
}

