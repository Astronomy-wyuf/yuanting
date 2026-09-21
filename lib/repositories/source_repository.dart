import 'package:sqflite/sqflite.dart';

import '../models/book_source.dart';
import '../services/storage_service.dart';

class SourceRepository {
  Future<Database> get _db async => StorageService.instance.database;

  Future<List<BookSource>> list() async {
    final db = await _db;
    final rows = await db.query('book_sources', orderBy: 'imported_at ASC');
    return rows.map((r) => BookSource.fromMap(r)).toList();
  }

  Future<BookSource?> get(String id) async {
    final db = await _db;
    final rows = await db.query('book_sources', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BookSource.fromMap(rows.first);
  }

  Future<BookSource?> getByUrl(String url) async {
    if (url.isEmpty) return null;
    final db = await _db;
    final rows = await db.query('book_sources', where: 'url = ?', whereArgs: [url], limit: 1);
    if (rows.isEmpty) return null;
    return BookSource.fromMap(rows.first);
  }

  Future<void> upsert(BookSource source) async {
    final db = await _db;
    await db.insert('book_sources', source.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final db = await _db;
    await db.update('book_sources', {'enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('book_sources', where: 'id = ?', whereArgs: [id]);
  }
}
