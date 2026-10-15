import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../utils/constants.dart';

/// sqflite 数据库统一入口。
/// Schema 共 5 张表：book_sources / books / chapters / play_progress / download_tasks。
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  Database? _db;

  /// 测试注入点：设置后 [database] 直接返回该实例（仅供测试使用）
  @visibleForTesting
  static Database? instanceOverrideForTest;

  Future<Database> get database async {
    final override = instanceOverrideForTest;
    if (override != null) return override;
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, AppConstants.dbFileName);
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 后续升 version 时在此按 oldVersion 逐步迁移，禁止改动已发布的 [onCreate]。
  ///
  /// ALTER 语句对「列已存在」容错：真实设备上可能出现版本号未推进
  /// 但列已写入的中间态（升级中断 / 覆盖安装时序），此时直接重跑
  /// ALTER 会抛 duplicate column 导致数据库永远打不开（App 全功能瘫痪）。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _safeAddColumn(db, 'book_sources', 'remote_url', 'TEXT');
    }
    if (oldVersion < 3) {
      // P1：书架分组 / 更新红点 / 书源订阅
      await _safeAddColumn(
          db, 'books', 'play_state', 'INTEGER NOT NULL DEFAULT 0');
      await _safeAddColumn(
          db, 'books', 'new_chapters', 'INTEGER NOT NULL DEFAULT 0');
      await _safeAddColumn(db, 'book_sources', 'auto_update',
          'INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// ADD COLUMN，若列已存在则跳过（查 PRAGMA table_info 判断）。
  Future<void> _safeAddColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final rows =
        await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((r) => r['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE book_sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL DEFAULT 1,
        author TEXT,
        description TEXT,
        rule_json TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        imported_at INTEGER NOT NULL,
        remote_url TEXT,
        auto_update INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        source_book_id TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL,
        author TEXT,
        cover_url TEXT,
        description TEXT,
        detail_url TEXT NOT NULL DEFAULT '',
        added_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_play_chapter_id TEXT,
        last_play_time INTEGER,
        total_chapters INTEGER,
        skip_intro INTEGER,
        skip_outro INTEGER,
        play_state INTEGER NOT NULL DEFAULT 0,
        new_chapters INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        idx INTEGER NOT NULL,
        title TEXT NOT NULL,
        audio_url TEXT NOT NULL,
        duration INTEGER,
        size INTEGER,
        pub_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE play_progress (
        chapter_id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        current_time REAL NOT NULL,
        duration REAL NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE download_tasks (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        book_title TEXT NOT NULL DEFAULT '',
        chapter_title TEXT NOT NULL DEFAULT '',
        url TEXT NOT NULL,
        local_path TEXT,
        status TEXT NOT NULL,
        progress INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        error TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_books_source ON books(source_id)');
    await db.execute('CREATE INDEX idx_chapters_book ON chapters(book_id)');
    await db.execute('CREATE INDEX idx_progress_book ON play_progress(book_id)');
    await db.execute('CREATE INDEX idx_downloads_status ON download_tasks(status)');
    await db.execute('CREATE INDEX idx_downloads_chapter ON download_tasks(chapter_id)');
  }
}
