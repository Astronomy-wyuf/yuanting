import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../services/storage_service.dart';

class BookRepository {
  Future<Database> get _db async => StorageService.instance.database;

  /// 书架列表（最近更新优先）
  Future<List<Book>> listShelf() async {
    final db = await _db;
    final rows = await db.query('books', orderBy: 'updated_at DESC');
    return rows.map((r) => Book.fromMap(r)).toList();
  }

  /// 书架按最近收听排序（无收听记录的排后）
  Future<List<Book>> listShelfByLastPlay() async {
    final books = await listShelf();
    books.sort((a, b) {
      final at = a.lastPlayTime?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastPlayTime?.millisecondsSinceEpoch ?? 0;
      if (at != bt) return bt.compareTo(at);
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return books;
  }

  /// 最近收听过的一本书（用于启动恢复迷你条）
  Future<Book?> getLastPlayed() async {
    final books = await listShelfByLastPlay();
    for (final b in books) {
      if (b.lastPlayTime != null) return b;
    }
    return null;
  }

  Future<Book?> get(String id) async {
    final db = await _db;
    final rows = await db.query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  Future<Book?> getByTitle(String title) async {
    final db = await _db;
    final rows = await db.query('books', where: 'title = ?', whereArgs: [title], limit: 1);
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  Future<void> upsert(Book book) async {
    final db = await _db;
    await db.insert('books', book.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
    await db.delete('play_progress', where: 'book_id = ?', whereArgs: [id]);
    // 保留 chapters 缓存：移出书架后仍可从详情/搜索再播，不必重新抓目录
  }

  /// 移出书架（与 [delete] 相同；语义名供调用方区分）
  Future<void> removeFromShelf(String id) => delete(id);

  Future<void> saveChapters(String bookId, List<Chapter> chapters) async {
    final db = await _db;
    final batch = db.batch();
    batch.delete('chapters', where: 'book_id = ?', whereArgs: [bookId]);
    for (final ch in chapters) {
      batch.insert('chapters', ch.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Chapter>> getChapters(String bookId) async {
    final db = await _db;
    final rows =
        await db.query('chapters', where: 'book_id = ?', whereArgs: [bookId], orderBy: 'idx ASC');
    return rows.map((r) => Chapter.fromMap(r)).toList();
  }

  /// 更新最近播放状态
  Future<void> updatePlayState(String bookId, String chapterId) async {
    final db = await _db;
    await db.update(
      'books',
      {
        'last_play_chapter_id': chapterId,
        'last_play_time': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }
}
