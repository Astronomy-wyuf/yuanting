import 'package:sqflite/sqflite.dart';

import '../models/play_progress.dart';
import '../services/storage_service.dart';

class ProgressRepository {
  Future<Database> get _db async => StorageService.instance.database;

  Future<PlayProgress?> get(String chapterId) async {
    final db = await _db;
    final rows =
        await db.query('play_progress', where: 'chapter_id = ?', whereArgs: [chapterId], limit: 1);
    if (rows.isEmpty) return null;
    return PlayProgress.fromMap(rows.first);
  }

  /// 书籍最近一次播放进度（按更新时间倒序第一条）
  Future<PlayProgress?> getLatestForBook(String bookId) async {
    final db = await _db;
    final rows = await db.query('play_progress',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'updated_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return PlayProgress.fromMap(rows.first);
  }

  Future<void> save(PlayProgress progress) async {
    final db = await _db;
    await db.insert('play_progress', progress.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
