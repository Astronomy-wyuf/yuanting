import 'package:sqflite/sqflite.dart';

import '../models/download_task.dart';
import '../services/storage_service.dart';

class DownloadRepository {
  Future<Database> get _db async => StorageService.instance.database;

  Future<List<DownloadTask>> list() async {
    final db = await _db;
    final rows = await db.query('download_tasks', orderBy: 'created_at DESC');
    return rows.map((r) => DownloadTask.fromMap(r)).toList();
  }

  Future<DownloadTask?> get(String id) async {
    final db = await _db;
    final rows = await db.query('download_tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return DownloadTask.fromMap(rows.first);
  }

  Future<DownloadTask?> getByChapter(String chapterId) async {
    final db = await _db;
    final rows =
        await db.query('download_tasks', where: 'chapter_id = ?', whereArgs: [chapterId], limit: 1);
    if (rows.isEmpty) return null;
    return DownloadTask.fromMap(rows.first);
  }

  Future<List<DownloadTask>> listByBook(String bookId) async {
    final db = await _db;
    final rows = await db.query('download_tasks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
    return rows.map((r) => DownloadTask.fromMap(r)).toList();
  }

  Future<void> save(DownloadTask task) async {
    final db = await _db;
    await db.insert('download_tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('download_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('download_tasks');
  }
}
