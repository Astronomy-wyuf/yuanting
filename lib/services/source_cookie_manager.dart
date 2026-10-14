import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

/// 书源请求的 Cookie 管理拦截器。
///
/// - 每个书源一个 [PersistCookieJar]，存储在 `<root>/<sourceId>/`，
///   避免多个源的同名 Cookie（如 `token`）互相覆盖；
/// - 通过请求 options 上的 `sourceId` 额外字段（[kSourceIdKey]）选择 jar；
///   未标记 sourceId 的请求（如图片探测）落到 [fallbackJar]；
/// - 与 dio_cookie_manager 的 CookieManager 行为保持一致（同样的
///   Set-Cookie 拆分正则与 Cookie 头合并策略）。
class SourceScopedCookieManager extends Interceptor {
  SourceScopedCookieManager({
    required Future<String> Function() resolveRootDir,
    required this.fallbackJar,
  }) : _resolveRootDir = resolveRootDir;

  /// Cookie 存储根目录解析器（每书源一个子目录）。
  final Future<String> Function() _resolveRootDir;
  Future<String>? _rootDirFuture;

  /// 未携带 sourceId 的请求使用的 jar（内存态）。
  final CookieJar fallbackJar;

  static const String kSourceIdKey = 'sourceId';

  final Map<String, PersistCookieJar> _jars = {};

  Future<String> _rootDir() => _rootDirFuture ??= _resolveRootDir();

  /// 与 dio_cookie_manager 相同的 Set-Cookie 拆分正则：
  /// 逗号后跟「非分号序列 + =」才视为新 Cookie，避免截断 expires 日期。
  static final RegExp _setCookieReg = RegExp('(?<=)(,)(?=[^;]+?=)');

  /// 取（或创建）某书源的持久化 jar。目录形如 `<rootDir>/<sourceId>/`。
  Future<PersistCookieJar> jarFor(String sourceId) async {
    final existing = _jars[sourceId];
    if (existing != null) return existing;
    final root = await _rootDir();
    final safeId = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final jar = PersistCookieJar(
      // 会话 Cookie 也落盘：书源会话（验证码、登录态）跨重启才有效。
      persistSession: true,
      storage: FileStorage('$root/$safeId'),
    );
    _jars[sourceId] = jar;
    return jar;
  }

  /// 删除某书源的全部持久化 Cookie（书源删除时调用）。
  Future<void> clearFor(String sourceId) async {
    final jar = _jars.remove(sourceId);
    if (jar != null) {
      await jar.deleteAll();
    }
    final root = await _rootDir();
    final safeId = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final dir = Directory('$root/$safeId');
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Cookie? _fromSetCookieValue(String value) {
    try {
      return Cookie.fromSetCookieValue(value);
    } on HttpException catch (_) {
      return null; // 忽略无法解析的 Cookie（与官方 ignoreInvalidCookies 一致）
    }
  }

  String _mergeCookies(List<Cookie> cookies) {
    // 路径长的排前面（与官方 CookieManager 一致）。
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) return 0;
      if (a.path == null) return -1;
      if (b.path == null) return 1;
      return b.path!.length.compareTo(a.path!.length);
    });
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<CookieJar> _jarForOptions(RequestOptions options) async {
    final sourceId = options.extra[kSourceIdKey] as String?;
    if (sourceId == null || sourceId.isEmpty) return fallbackJar;
    return jarFor(sourceId);
  }

  Future<void> _saveCookies(Response response) async {
    final setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null || setCookies.isEmpty) return;

    final cookies = setCookies
        .map((str) => str.split(_setCookieReg))
        .expand((cookie) => cookie)
        .where((cookie) => cookie.isNotEmpty)
        .map(_fromSetCookieValue)
        .whereType<Cookie>()
        .toList();
    if (cookies.isEmpty) return;

    final jar = await _jarForOptions(response.requestOptions);
    // Spec: https://www.rfc-editor.org/rfc/rfc7231#section-7.1.2
    final originalUri = response.requestOptions.uri;
    final realUri = originalUri.resolveUri(response.realUri);
    await jar.saveFromResponse(realUri, cookies);

    // followRedirects=false 的 3xx 响应：把 Cookie 同时记到跳转目标。
    final statusCode = response.statusCode ?? 0;
    final locations = response.headers[HttpHeaders.locationHeader] ?? const [];
    if (statusCode >= 300 && statusCode < 400 && locations.isNotEmpty) {
      await Future.wait(locations.map(
        (location) =>
            jar.saveFromResponse(originalUri.resolve(location), cookies),
      ));
    }
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final jar = await _jarForOptions(options);
      final saved = await jar.loadForRequest(options.uri);
      final manual = options.headers[HttpHeaders.cookieHeader] as String?;
      final manualCookies = (manual ?? '')
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(_fromSetCookieValue)
          .whereType<Cookie>()
          .toList();
      final merged = _mergeCookies([...manualCookies, ...saved]);
      options.headers[HttpHeaders.cookieHeader] =
          merged.isNotEmpty ? merged : null;
      handler.next(options);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: e,
          message: '加载书源 Cookie 失败',
          stackTrace: s,
        ),
        true,
      );
    }
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      await _saveCookies(response);
      handler.next(response);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.unknown,
          error: e,
          message: '保存书源 Cookie 失败',
          stackTrace: s,
        ),
        true,
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null) {
      handler.next(err);
      return;
    }
    try {
      await _saveCookies(response);
      handler.next(err);
    } catch (_) {
      handler.next(err);
    }
  }
}
