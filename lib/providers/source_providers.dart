import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book_source.dart';
import '../repositories/source_repository.dart';
import '../services/source_engine.dart';
import '../utils/text_file_codec.dart';
import 'app_providers.dart';

/// 书源导入结果
class SourceImportResult {
  final int okCount;
  final List<String> errors;
  const SourceImportResult({required this.okCount, required this.errors});

  bool get success => okCount > 0 && errors.isEmpty;
}

/// 书源列表控制器：导入 / 启用禁用 / 编辑 / 删除
class SourcesController extends ChangeNotifier {
  final SourceRepository repository;
  final SourceEngine engine;

  List<BookSource> sources = [];
  bool loading = false;

  SourcesController({
    required this.repository,
    required this.engine,
  });

  List<BookSource> get enabledSources => sources.where((s) => s.enabled).toList();

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      sources = await repository.list();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 从文本导入书源（支持单个 JSON 对象或 JSON 数组），按 url 去重更新
  Future<SourceImportResult> importFromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const SourceImportResult(okCount: 0, errors: ['内容为空']);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      return SourceImportResult(okCount: 0, errors: ['JSON 解析失败: $e']);
    }
    final list = decoded is List ? decoded : [decoded];
    final errors = <String>[];
    var ok = 0;
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) {
        errors.add('第 ${i + 1} 项不是 JSON 对象');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final validateErrors = engine.validate(map);
      if (validateErrors.isNotEmpty) {
        final name = (map['site'] as Map?)?['name'] ?? '第 ${i + 1} 项';
        errors.add('「$name」校验失败: ${validateErrors.join('；')}');
        continue;
      }
      var source = BookSource.fromRuleJson(map);
      // 按 url 去重：已存在同 url 书源则更新规则
      final existed = await repository.getByUrl(source.url);
      if (existed != null) {
        source = source.copyWith(
            id: existed.id, enabled: existed.enabled, importedAt: existed.importedAt);
      }
      await repository.upsert(source);
      ok++;
    }
    if (ok > 0) await load();
    return SourceImportResult(okCount: ok, errors: errors);
  }

  /// 从网络 URL 下载书源 JSON（单个对象或数组），再走 [importFromText]
  Future<SourceImportResult> importFromUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return const SourceImportResult(okCount: 0, errors: ['请输入书源链接']);
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return const SourceImportResult(
        okCount: 0,
        errors: ['请输入有效的 http(s) 链接'],
      );
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.bytes,
        validateStatus: (code) => code != null && code < 400,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ));
      final resp = await dio.getUri(uri);
      final data = resp.data;
      if (data is! List<int> || data.isEmpty) {
        return const SourceImportResult(okCount: 0, errors: ['下载内容为空']);
      }
      final text = decodeTextFileBytes(data);
      if (text.trim().isEmpty) {
        return const SourceImportResult(
          okCount: 0,
          errors: ['下载内容无法解码为文本'],
        );
      }
      return importFromText(text);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final detail = e.message ?? e.type.name;
      return SourceImportResult(
        okCount: 0,
        errors: [
          code != null ? '下载失败 HTTP $code：$detail' : '下载失败：$detail',
        ],
      );
    } catch (e) {
      return SourceImportResult(okCount: 0, errors: ['下载失败: $e']);
    }
  }

  Future<void> toggle(BookSource source) async {
    await repository.setEnabled(source.id, !source.enabled);
    await load();
  }

  /// 用编辑后的规则 JSON 覆盖书源
  Future<List<String>> updateRule(BookSource source, String ruleText) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(ruleText.trim());
    } catch (e) {
      return ['JSON 解析失败: $e'];
    }
    if (decoded is! Map) return ['规则必须是一个 JSON 对象'];
    final map = Map<String, dynamic>.from(decoded);
    final errors = engine.validate(map);
    if (errors.isNotEmpty) return errors;
    final updated = BookSource.fromRuleJson(map, id: source.id);
    await repository.upsert(updated.copyWith(
        enabled: source.enabled, importedAt: source.importedAt));
    await load();
    return const [];
  }

  Future<void> delete(BookSource source) async {
    await repository.delete(source.id);
    await load();
  }
}

final sourcesControllerProvider =
    ChangeNotifierProvider<SourcesController>((ref) {
  return SourcesController(
    repository: ref.watch(sourceRepositoryProvider),
    engine: ref.watch(sourceEngineProvider),
  );
});
