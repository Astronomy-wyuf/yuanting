import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book_source.dart';
import '../models/search_captcha.dart';
import '../models/search_record.dart';
import '../repositories/source_repository.dart';
import '../services/settings_service.dart';
import '../services/source_engine.dart';
import 'app_providers.dart';

enum SourceSearchStatus {
  idle,
  loading,
  done,
  error,
  loadingMore,
  needsCaptcha,
}

class SourceSearchState {
  final BookSource source;
  final SourceSearchStatus status;
  final List<SearchRecord> results;
  final String? error;
  final int page;
  final bool hasMore;
  final SearchCaptchaChallenge? captcha;

  const SourceSearchState({
    required this.source,
    this.status = SourceSearchStatus.idle,
    this.results = const [],
    this.error,
    this.page = 1,
    this.hasMore = true,
    this.captcha,
  });

  SourceSearchState copyWith({
    SourceSearchStatus? status,
    List<SearchRecord>? results,
    String? error,
    int? page,
    bool? hasMore,
    SearchCaptchaChallenge? captcha,
    bool clearCaptcha = false,
    bool clearError = false,
  }) {
    return SourceSearchState(
      source: source,
      status: status ?? this.status,
      results: results ?? this.results,
      error: clearError ? null : (error ?? this.error),
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      captcha: clearCaptcha ? null : (captcha ?? this.captcha),
    );
  }
}

/// 聚合搜索：并行搜多源 + 历史记录 + 分页加载更多
class AudiobookSearchController extends ChangeNotifier {
  final SourceEngine engine;
  final SourceRepository repository;
  final AppSettingsService settings;

  String query = '';
  Map<String, SourceSearchState> bySource = {};
  List<String> history = [];
  int _searchGen = 0;

  AudiobookSearchController({
    required this.engine,
    required this.repository,
    required this.settings,
  }) {
    history = List<String>.from(settings.searchHistory);
  }

  bool get isSearching => bySource.values.any(
        (s) =>
            s.status == SourceSearchStatus.loading ||
            s.status == SourceSearchStatus.loadingMore,
      );

  bool get isLoadingMore => bySource.values.any(
        (s) => s.status == SourceSearchStatus.loadingMore,
      );

  bool get hasMoreAny => bySource.values.any(
        (s) =>
            s.hasMore &&
            (s.status == SourceSearchStatus.done ||
                s.status == SourceSearchStatus.loadingMore),
      );

  int get totalResults =>
      bySource.values.fold(0, (sum, s) => sum + s.results.length);

  bool get needsCaptchaAny => bySource.values.any(
        (s) => s.status == SourceSearchStatus.needsCaptcha && s.captcha != null,
      );

  List<SourceSearchState> get captchaStates => bySource.values
      .where(
        (s) => s.status == SourceSearchStatus.needsCaptcha && s.captcha != null,
      )
      .toList();

  /// 多源结果打平为一列表（轮询交错，避免某一源独占前几屏）
  List<SearchRecord> get flatResults {
    final queues = bySource.values
        .where((s) => s.results.isNotEmpty)
        .map((s) => List<SearchRecord>.from(s.results))
        .toList();
    if (queues.isEmpty) return const [];
    if (queues.length == 1) return queues.first;

    final out = <SearchRecord>[];
    var remaining = true;
    while (remaining) {
      remaining = false;
      for (final q in queues) {
        if (q.isEmpty) continue;
        remaining = true;
        out.add(q.removeAt(0));
      }
    }
    return out;
  }

  /// 各源加载更多（并行）；无更多则空操作
  Future<void> loadMoreAll() async {
    final ids = bySource.entries
        .where(
          (e) =>
              e.value.hasMore &&
              e.value.status == SourceSearchStatus.done &&
              query.isNotEmpty,
        )
        .map((e) => e.key)
        .toList();
    if (ids.isEmpty) return;
    await Future.wait(ids.map(loadMore));
  }

  Future<void> refreshHistory() async {
    history = List<String>.from(settings.searchHistory);
    notifyListeners();
  }

  Future<void> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return;
    query = q;
    final gen = ++_searchGen;
    await settings.addSearchHistory(q);
    history = List<String>.from(settings.searchHistory);

    final enabled = (await repository.list()).where((s) => s.enabled).toList();
    if (gen != _searchGen) return;
    bySource = {
      for (final s in enabled)
        s.id: SourceSearchState(
          source: s,
          status: SourceSearchStatus.loading,
        ),
    };
    notifyListeners();

    await Future.wait(
      enabled.map((source) => _searchOne(source, q, page: 1, gen: gen)),
    );
  }

  Future<void> loadMore(String sourceId) async {
    final state = bySource[sourceId];
    if (state == null ||
        query.isEmpty ||
        !state.hasMore ||
        state.status == SourceSearchStatus.loading ||
        state.status == SourceSearchStatus.loadingMore) {
      return;
    }
    final gen = _searchGen;
    bySource[sourceId] =
        state.copyWith(status: SourceSearchStatus.loadingMore);
    notifyListeners();
    await _searchOne(
      state.source,
      query,
      page: state.page + 1,
      append: true,
      gen: gen,
    );
  }

  /// 只重搜某一个源（分栏里点重试，不连带其它源）
  Future<void> retrySource(String sourceId) async {
    final state = bySource[sourceId];
    if (state == null || query.isEmpty) return;
    final gen = _searchGen;
    bySource[sourceId] = SourceSearchState(
      source: state.source,
      status: SourceSearchStatus.loading,
    );
    notifyListeners();
    await _searchOne(state.source, query, page: 1, gen: gen);
  }

  Future<void> _searchOne(
    BookSource source,
    String q, {
    required int page,
    bool append = false,
    required int gen,
  }) async {
    try {
      final searchRule =
          (source.rule['search'] as Map?)?.cast<String, dynamic>() ?? const {};
      final urlTpl = _searchUrlTemplateForPaging(searchRule, q);
      final supportsPage = urlTpl.contains('{{page}}');
      // 无分页模板时 page>1 直接视为没有更多
      if (page > 1 && !supportsPage) {
        if (gen != _searchGen || query != q) return;
        final prev = bySource[source.id];
        if (prev != null) {
          bySource[source.id] = prev.copyWith(
            status: SourceSearchStatus.done,
            hasMore: false,
          );
          notifyListeners();
        }
        return;
      }

      final results = await engine
          .search(source, q, page: page)
          .timeout(const Duration(seconds: 25));
      if (gen != _searchGen || query != q) return;
      final prev = bySource[source.id];
      final prevIds = {
        for (final r in prev?.results ?? const <SearchRecord>[])
          '${r.sourceId}::${r.sourceBookId}',
      };
      final fresh = append
          ? results
              .where((r) => !prevIds.contains('${r.sourceId}::${r.sourceBookId}'))
              .toList()
          : results;
      final merged = append
          ? [...(prev?.results ?? const <SearchRecord>[]), ...fresh]
          : results;
      final hasMore = supportsPage && fresh.isNotEmpty;
      bySource[source.id] = SourceSearchState(
        source: source,
        status: SourceSearchStatus.done,
        results: merged,
        page: page,
        hasMore: hasMore,
      );
    } on SourceCaptchaRequiredException catch (e) {
      if (gen != _searchGen || query != q) return;
      bySource[source.id] = SourceSearchState(
        source: source,
        status: SourceSearchStatus.needsCaptcha,
        captcha: e.challenge,
        page: page,
        hasMore: false,
        results: append ? (bySource[source.id]?.results ?? const []) : const [],
      );
    } catch (e) {
      if (gen != _searchGen || query != q) return;
      final prev = bySource[source.id];
      if (append && prev != null) {
        bySource[source.id] = prev.copyWith(
          status: SourceSearchStatus.done,
          error: e is TimeoutException ? '加载更多超时' : e.toString(),
        );
      } else {
        bySource[source.id] = SourceSearchState(
          source: source,
          status: SourceSearchStatus.error,
          error: e is TimeoutException ? '搜索超时' : e.toString(),
        );
      }
    }
    if (gen == _searchGen) notifyListeners();
  }

  String _searchUrlTemplateForPaging(
    Map<String, dynamic> searchRule,
    String q,
  ) {
    final map = searchRule['keywordMap'];
    final mapped = map is Map
        ? (map[q.trim()] ?? map[q.trim().toLowerCase()])?.toString()
        : null;
    final mapUrl = (searchRule['keywordMapUrl'] as String?)?.trim() ?? '';
    if (mapUrl.isNotEmpty &&
        (mapped != null || RegExp(r'^\d+$').hasMatch(q.trim()))) {
      return mapUrl;
    }
    return searchRule['url'] as String? ?? '';
  }

  /// 用户提交某源验证码后继续搜索。
  Future<void> submitCaptcha(String sourceId, String code) async {
    final state = bySource[sourceId];
    final challenge = state?.captcha;
    if (state == null || challenge == null || query.isEmpty) return;
    final gen = _searchGen;
    final q = query;
    bySource[sourceId] = state.copyWith(
      status: SourceSearchStatus.loading,
      clearError: true,
    );
    notifyListeners();
    try {
      final results = await engine
          .submitSearchCaptcha(
            state.source,
            challenge,
            code,
            keyword: q,
            page: state.page < 1 ? 1 : state.page,
          )
          .timeout(const Duration(seconds: 25));
      if (gen != _searchGen || query != q) return;
      final searchRule =
          (state.source.rule['search'] as Map?)?.cast<String, dynamic>() ??
              const {};
      final supportsPage =
          _searchUrlTemplateForPaging(searchRule, q).contains('{{page}}');
      bySource[sourceId] = SourceSearchState(
        source: state.source,
        status: SourceSearchStatus.done,
        results: results,
        page: state.page < 1 ? 1 : state.page,
        hasMore: supportsPage && results.isNotEmpty,
      );
    } on SourceCaptchaRequiredException catch (e) {
      if (gen != _searchGen || query != q) return;
      bySource[sourceId] = SourceSearchState(
        source: state.source,
        status: SourceSearchStatus.needsCaptcha,
        captcha: e.challenge,
        page: state.page,
        error: '验证码错误，请重试',
      );
    } catch (e) {
      if (gen != _searchGen || query != q) return;
      bySource[sourceId] = SourceSearchState(
        source: state.source,
        status: SourceSearchStatus.needsCaptcha,
        captcha: challenge,
        page: state.page,
        error: e is TimeoutException ? '提交超时' : e.toString(),
      );
    }
    if (gen == _searchGen) notifyListeners();
  }

  Future<void> refreshCaptcha(String sourceId) async {
    final state = bySource[sourceId];
    final challenge = state?.captcha;
    if (state == null || challenge == null) return;
    try {
      final bytes = await engine.refreshCaptchaImage(challenge);
      bySource[sourceId] = state.copyWith(
        captcha: challenge.copyWith(imageBytes: bytes),
        clearError: true,
      );
      notifyListeners();
    } catch (e) {
      bySource[sourceId] = state.copyWith(error: '刷新验证码失败: $e');
      notifyListeners();
    }
  }

  Future<void> removeHistory(String keyword) async {
    await settings.removeSearchHistory(keyword);
    history = List<String>.from(settings.searchHistory);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await settings.clearSearchHistory();
    history = [];
    notifyListeners();
  }

  void clear() {
    query = '';
    bySource = {};
    notifyListeners();
  }
}

final searchControllerProvider =
    ChangeNotifierProvider<AudiobookSearchController>((ref) {
  return AudiobookSearchController(
    engine: ref.watch(sourceEngineProvider),
    repository: ref.watch(sourceRepositoryProvider),
    settings: ref.watch(settingsServiceProvider),
  );
});
