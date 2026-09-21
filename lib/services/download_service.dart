import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../models/download_task.dart';
import '../repositories/download_repository.dart';
import '../services/settings_service.dart';
import '../utils/constants.dart';

/// 下载服务：音频下载到应用文档目录 downloads/ 子目录。
/// - 全局并发限制（默认 2）
/// - 流式写入 + Range 断点续传
/// - 存储上限 / 仅 Wi‑Fi
class DownloadService extends ChangeNotifier {
  static const int maxConcurrent = 2;

  final DownloadRepository repository;
  final AppSettingsService settings;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (code) => code != null && code < 400,
  ));
  final _uuid = const Uuid();
  final Map<String, CancelToken> _tokens = {};
  final Set<String> _running = {};

  List<DownloadTask> tasks = [];

  /// 可选：开下 / 继续前刷新时效直链
  Future<String> Function(DownloadTask task)? urlResolver;

  DownloadService({
    required this.repository,
    required this.settings,
    this.urlResolver,
  });

  int get maxStorageMB => settings.downloadMaxStorageMB;

  bool get wifiOnlyDownload => settings.wifiOnlyDownload;

  int get activeCount =>
      tasks.where((t) => t.isActive).length;

  List<DownloadBookGroup> bookGroups() {
    final map = <String, List<DownloadTask>>{};
    for (final t in tasks) {
      map.putIfAbsent(t.bookId, () => []).add(t);
    }
    return [
      for (final e in map.entries)
        DownloadBookGroup(
          bookId: e.key,
          bookTitle: e.value.first.bookTitle,
          tasks: e.value,
        ),
    ];
  }

  Future<Directory> _downloadDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(doc.path, AppConstants.downloadDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    tasks = await repository.list();
    var dirty = false;
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].status == DownloadStatus.downloading ||
          tasks[i].status == DownloadStatus.pending) {
        tasks[i] = tasks[i].copyWith(status: DownloadStatus.paused, error: null);
        dirty = true;
      }
    }
    if (dirty) {
      for (final t in tasks) {
        await repository.save(t);
      }
    }
    notifyListeners();
  }

  DownloadTask? taskForChapter(String chapterId) {
    for (final t in tasks) {
      if (t.chapterId == chapterId) return t;
    }
    return null;
  }

  List<DownloadTask> tasksForBook(String bookId) =>
      tasks.where((t) => t.bookId == bookId).toList();

  Future<int> usedBytes() async {
    final dir = await _downloadDir();
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<String?> _wifiGateMessage() async {
    if (!wifiOnlyDownload) return null;
    final results = await Connectivity().checkConnectivity();
    final ok = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    if (ok) return null;
    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return '当前无网络，无法下载';
    }
    return '已开启「仅 Wi‑Fi 下载」，请连接 Wi‑Fi 后再试';
  }

  /// 启动章节下载；成功返回空串，门禁失败返回提示
  Future<String> start(Book book, Chapter chapter) async {
    final existing = taskForChapter(chapter.id);
    if (existing != null &&
        existing.status != DownloadStatus.failed &&
        existing.status != DownloadStatus.paused) {
      if (existing.status == DownloadStatus.completed) {
        return '该章节已下载完成';
      }
      return '该章节已在下载列表中';
    }

    final wifiMsg = await _wifiGateMessage();
    if (wifiMsg != null) return wifiMsg;

    if (existing != null &&
        (existing.status == DownloadStatus.failed ||
            existing.status == DownloadStatus.paused)) {
      final withUrl = existing.copyWith(
        url: chapter.audioUrl,
        status: DownloadStatus.pending,
        error: null,
        progress: existing.status == DownloadStatus.failed
            ? 0
            : existing.progress,
        downloadedBytes: existing.status == DownloadStatus.failed
            ? 0
            : existing.downloadedBytes,
        totalBytes: existing.status == DownloadStatus.failed
            ? null
            : existing.totalBytes,
      );
      for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id == existing.id) {
          tasks[i] = withUrl;
          break;
        }
      }
      await repository.save(withUrl);
      notifyListeners();
      _schedule();
      return '';
    }

    final maxMb = maxStorageMB;
    final maxBytes = maxMb * 1024 * 1024;
    final used = await usedBytes();
    if (used >= maxBytes) {
      return '下载存储已达上限（${maxMb}MB），请先清理已下载内容';
    }

    final dir = await _downloadDir();
    final ext = _extensionOf(chapter.audioUrl);
    final safeId = chapter.id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final filePath = p.join(dir.path, '$safeId$ext');

    final task = DownloadTask(
      id: _uuid.v4(),
      chapterId: chapter.id,
      bookId: chapter.bookId.isNotEmpty ? chapter.bookId : book.id,
      bookTitle: book.title,
      chapterTitle: chapter.title,
      url: chapter.audioUrl,
      localPath: filePath,
      status: DownloadStatus.pending,
      createdAt: DateTime.now(),
    );
    tasks.insert(0, task);
    await repository.save(task);
    notifyListeners();
    _schedule();
    return '';
  }

  /// 批量入队；返回成功加入数与首个门禁错误
  Future<({int added, String? error})> startMany(
    Book book,
    List<Chapter> chapters,
  ) async {
    var added = 0;
    for (final ch in chapters) {
      final existing = taskForChapter(ch.id);
      if (existing != null &&
          existing.status != DownloadStatus.failed &&
          existing.status != DownloadStatus.paused) {
        continue;
      }
      final msg = await start(book, ch);
      if (msg.isNotEmpty) {
        return (added: added, error: msg);
      }
      added++;
    }
    return (added: added, error: null);
  }

  void pause(String taskId) {
    final task = tasks.cast<DownloadTask?>().firstWhere(
          (t) => t?.id == taskId,
          orElse: () => null,
        );
    if (task == null) return;
    if (task.status == DownloadStatus.pending) {
      _updateTask(taskId, status: DownloadStatus.paused, error: null);
      return;
    }
    _tokens[taskId]?.cancel('用户暂停');
  }

  void pauseAll() {
    for (final t in List<DownloadTask>.from(tasks)) {
      if (t.isActive) pause(t.id);
    }
  }

  void pauseBook(String bookId) {
    for (final t in List<DownloadTask>.from(tasks)) {
      if (t.bookId == bookId && t.isActive) pause(t.id);
    }
  }

  Future<String?> resume(String taskId) async {
    DownloadTask? found;
    for (final t in tasks) {
      if (t.id == taskId) found = t;
    }
    if (found == null) return null;
    var task = found;
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.pending) {
      return null;
    }
    final wifiMsg = await _wifiGateMessage();
    if (wifiMsg != null) {
      _updateTask(task.id, status: DownloadStatus.paused, error: wifiMsg);
      return wifiMsg;
    }

    final resolver = urlResolver;
    if (resolver != null) {
      try {
        final fresh = await resolver(task);
        if (fresh.trim().isNotEmpty && fresh != task.url) {
          if (task.localPath != null) {
            final f = File(task.localPath!);
            if (await f.exists()) {
              try {
                await f.delete();
              } catch (_) {}
            }
          }
          task = task.copyWith(
            url: fresh,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: null,
            error: null,
          );
          for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id == task.id) {
              tasks[i] = task;
              break;
            }
          }
          await repository.save(task);
        }
      } catch (e) {
        _updateTask(
          task.id,
          status: DownloadStatus.failed,
          error: '刷新下载地址失败: $e',
        );
        return '刷新下载地址失败: $e';
      }
    }

    _updateTask(task.id, status: DownloadStatus.pending, error: null);
    _schedule();
    return null;
  }

  Future<String?> resumeBook(String bookId) async {
    String? firstError;
    for (final t in List<DownloadTask>.from(tasks)) {
      if (t.bookId != bookId) continue;
      if (t.status != DownloadStatus.paused &&
          t.status != DownloadStatus.failed) {
        continue;
      }
      final msg = await resume(t.id);
      firstError ??= msg;
    }
    return firstError;
  }

  Future<void> delete(String taskId) async {
    _tokens[taskId]?.cancel('删除任务');
    _tokens.remove(taskId);
    _running.remove(taskId);
    final task = tasks.where((t) => t.id == taskId).toList();
    tasks.removeWhere((t) => t.id == taskId);
    if (task.isNotEmpty && task.first.localPath != null) {
      final f = File(task.first.localPath!);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await repository.delete(taskId);
    notifyListeners();
    _schedule();
  }

  Future<void> deleteBook(String bookId) async {
    final ids =
        tasks.where((t) => t.bookId == bookId).map((t) => t.id).toList();
    for (final id in ids) {
      await delete(id);
    }
  }

  Future<void> deleteAll() async {
    final ids = tasks.map((t) => t.id).toList();
    for (final id in ids) {
      _tokens[id]?.cancel('清空下载');
    }
    _tokens.clear();
    _running.clear();
    for (final t in tasks) {
      if (t.localPath != null) {
        final f = File(t.localPath!);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
    tasks.clear();
    await repository.deleteAll();
    notifyListeners();
  }

  void _schedule() {
    while (_running.length < maxConcurrent) {
      DownloadTask? next;
      for (final t in tasks) {
        if (t.status == DownloadStatus.pending && !_running.contains(t.id)) {
          next = t;
          break;
        }
      }
      if (next == null) break;
      _running.add(next.id);
      unawaited(_run(next).whenComplete(() {
        _running.remove(next!.id);
        _schedule();
      }));
    }
  }

  Future<void> _run(DownloadTask task) async {
    _updateTask(task.id, status: DownloadStatus.downloading, error: null);
    final token = CancelToken();
    _tokens[task.id] = token;
    IOSink? sink;
    try {
      var current = task;
      final resolver = urlResolver;
      if (resolver != null) {
        try {
          final fresh = await resolver(task);
          if (fresh.trim().isNotEmpty && fresh != task.url) {
            current = task.copyWith(url: fresh, error: null);
            for (var i = 0; i < tasks.length; i++) {
              if (tasks[i].id == task.id) {
                tasks[i] = current;
                break;
              }
            }
            await repository.save(current);
            notifyListeners();
          }
        } catch (e) {
          _updateTask(task.id,
              status: DownloadStatus.failed,
              error:
                  '解析地址失败: ${e.toString().replaceFirst('Exception: ', '')}');
          return;
        }
      }

      // 暂停可能发生在解析阶段
      final still = tasks.cast<DownloadTask?>().firstWhere(
            (t) => t?.id == task.id,
            orElse: () => null,
          );
      if (still == null || still.status == DownloadStatus.paused) return;

      final file = File(current.localPath!);
      int startByte = 0;
      if (await file.exists() && await file.length() > 0) {
        startByte = await file.length();
      }

      final res = await _dio.get<ResponseBody>(
        current.url,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          headers: startByte > 0 ? {'range': 'bytes=$startByte-'} : null,
        ),
      );

      final resume = res.statusCode == 206;
      if (!resume && await file.exists()) {
        await file.delete();
        startByte = 0;
      }

      final contentLength =
          int.tryParse(res.headers.value('content-length') ?? '');
      final totalBytes = (contentLength != null && contentLength > 0)
          ? contentLength + (resume ? startByte : 0)
          : null;

      var received = resume ? startByte : 0;
      sink = file.openWrite(mode: resume ? FileMode.append : FileMode.write);
      var lastEmit = DateTime.now();

      await for (final chunk in res.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastEmit) >= AppConstants.downloadEmitInterval) {
          lastEmit = now;
          final progress = totalBytes != null && totalBytes > 0
              ? (received * 100 ~/ totalBytes).clamp(0, 99)
              : 0;
          _updateTask(task.id,
              progress: progress,
              downloadedBytes: received,
              totalBytes: totalBytes);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received <= 0) {
        throw DioException(
          requestOptions: RequestOptions(path: current.url),
          error: '下载数据为空',
        );
      }
      _updateTask(
        task.id,
        status: DownloadStatus.completed,
        progress: 100,
        downloadedBytes: received,
        totalBytes: totalBytes ?? received,
        completedAt: DateTime.now(),
        error: null,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _updateTask(task.id, status: DownloadStatus.paused, error: null);
      } else {
        _updateTask(task.id,
            status: DownloadStatus.failed, error: e.message ?? '网络错误');
      }
    } catch (e) {
      _updateTask(task.id, status: DownloadStatus.failed, error: e.toString());
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      _tokens.remove(task.id);
    }
  }

  void _updateTask(
    String id, {
    DownloadStatus? status,
    int? progress,
    int? downloadedBytes,
    Object? totalBytes = DownloadTask.unset,
    DateTime? completedAt,
    Object? error = DownloadTask.unset,
  }) {
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].id == id) {
        tasks[i] = tasks[i].copyWith(
          status: status,
          progress: progress,
          downloadedBytes: downloadedBytes,
          totalBytes: identical(totalBytes, DownloadTask.unset)
              ? DownloadTask.unset
              : totalBytes,
          completedAt: completedAt,
          error: error,
        );
        unawaited(repository.save(tasks[i]));
        break;
      }
    }
    notifyListeners();
  }

  String _extensionOf(String url) {
    final clean = url.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot >= 0 && clean.length - dot <= 6) {
      final ext = clean.substring(dot).toLowerCase();
      if (RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext)) return ext;
    }
    return '.mp3';
  }
}
