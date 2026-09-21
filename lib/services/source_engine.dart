import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import '../models/search_captcha.dart';
import '../models/search_record.dart';
import '../utils/json_path.dart';
import '../utils/rule_parser.dart';
import 'source_auth_bootstrap.dart';
import 'source_auth_cache.dart';
import 'source_crypto.dart';

/// 书源规则引擎：搜索 / 详情 / 章节 / 音频解析（含可选声明式加解密）。
class SourceEngine {
  final Dio _dio;
  final SourceAuthCache? authCache;

  SourceEngine({Dio? dio, this.authCache})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (code) => code != null && code < 400,
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            )) {
    _dio.interceptors.add(CookieManager(CookieJar()));
  }

  /// 校验书源规则 JSON，返回错误信息列表（空列表 = 校验通过）
  List<String> validate(Map<String, dynamic> raw) {
    final errors = <String>[];
    final site = raw['site'];
    if (site is! Map) {
      errors.add('缺少 site 对象');
    } else {
      if ((site['name'] as String?)?.isEmpty ?? true) {
        errors.add('site.name 不能为空');
      }
      if ((site['url'] as String?)?.isEmpty ?? true) {
        errors.add('site.url 不能为空');
      }
    }
    final search = raw['search'];
    if (search is! Map) {
      errors.add('缺少 search 对象');
    } else {
      if (((search['url'] as String?) ?? '').isEmpty) {
        errors.add('search.url 不能为空');
      }
      final parser = search['parser'];
      if (parser is! Map || ((parser['type'] as String?) ?? '').isEmpty) {
        errors.add('search.parser.type 不能为空');
      }
    }
    final chapters = raw['chapters'];
    if (chapters is! Map) {
      errors.add('缺少 chapters 对象');
    } else {
      final parser = chapters['parser'];
      if (parser is! Map || ((parser['type'] as String?) ?? '').isEmpty) {
        errors.add('chapters.parser.type 不能为空');
      }
    }

    final audio = raw['audio'];
    if (audio is Map) {
      final a = audio.cast<String, dynamic>();
      if (a.containsKey('parser') && a.containsKey('responseParse')) {
        errors.add('audio 勿同时声明 parser 与 responseParse');
      }
      final body = jsonEncode(a);
      if (body.contains('{{chapterIndex}}') && a['chapterIndexBase'] == null) {
        errors.add('使用 {{chapterIndex}} 时必须声明 audio.chapterIndexBase');
      }
      if (body.contains('{{token}}') && raw['auth'] is! Map) {
        errors.add('使用 {{token}} 时必须配置 auth');
      }
      final policy = (a['resolvePolicy'] as String?)?.toLowerCase();
      final hasCrypto = a['requestCrypto'] != null ||
          (a['responseParse'] as Map?)?['decrypt'] != null;
      if (policy == 'eager' && hasCrypto) {
        errors.add('加密音频不可使用 resolvePolicy: eager');
      }
      if (a['cachePlayUrl'] == true && hasCrypto) {
        errors.add('加密/签名直链禁止 cachePlayUrl: true');
      }
      try {
        SourceCrypto.validatePipeline(
          (a['requestCrypto'] as Map?)?.cast<String, dynamic>(),
          path: 'audio.requestCrypto',
        );
        final rp = (a['responseParse'] as Map?)?.cast<String, dynamic>();
        SourceCrypto.validatePipeline(
          (rp?['decrypt'] as Map?)?.cast<String, dynamic>(),
          path: 'audio.responseParse.decrypt',
        );
      } on SourceCryptoException catch (e) {
        errors.add(e.message);
      }
    }

    final auth = raw['auth'];
    if (auth is Map) {
      final acquire = auth['acquire'];
      if (acquire is! Map) {
        errors.add('auth.acquire 必须为对象');
      } else {
        try {
          SourceCrypto.validatePipeline(
            (acquire['requestCrypto'] as Map?)?.cast<String, dynamic>(),
            path: 'auth.acquire.requestCrypto',
          );
          final rp =
              (acquire['responseParse'] as Map?)?.cast<String, dynamic>();
          SourceCrypto.validatePipeline(
            (rp?['decrypt'] as Map?)?.cast<String, dynamic>(),
            path: 'auth.acquire.responseParse.decrypt',
          );
        } on SourceCryptoException catch (e) {
          errors.add(e.message);
        }
      }
    }
    return errors;
  }

  Future<List<SearchRecord>> search(
    BookSource source,
    String keyword, {
    int page = 1,
  }) async {
    final searchRule = _section(source.rule, 'search');
    final prepared = _prepareSearchRequest(searchRule, keyword, page: page);
    final url = prepared.url;
    final context = prepared.context;
    final body = await _fetchText(url, searchRule, context: context);
    await _throwIfCaptcha(source, searchRule, body, pageUrl: url, context: context);
    return _mapSearchRecords(source, searchRule, body, context);
  }

  /// 刷新验证码图片（同 Cookie 会话）。
  Future<Uint8List> refreshCaptchaImage(SearchCaptchaChallenge challenge) async {
    final bust = '${challenge.imageUrl}'
        '${challenge.imageUrl.contains('?') ? '&' : '?'}get=${DateTime.now().millisecondsSinceEpoch}';
    return _fetchBytes(
      bust,
      headers: {
        'Referer': challenge.pageUrl,
        ...challenge.headers,
      },
    );
  }

  /// 提交验证码；成功返回搜索结果，仍需验证则再次抛 [SourceCaptchaRequiredException]。
  Future<List<SearchRecord>> submitSearchCaptcha(
    BookSource source,
    SearchCaptchaChallenge challenge,
    String code, {
    required String keyword,
    int page = 1,
  }) async {
    final searchRule = _section(source.rule, 'search');
    final prepared = _prepareSearchRequest(searchRule, keyword, page: page);
    final context = <String, dynamic>{
      ...prepared.context,
      'code': code.trim(),
      'pageUrl': challenge.pageUrl,
    };
    final section = <String, dynamic>{
      ...searchRule,
      'url': challenge.submitUrl,
      'method': challenge.submitMethod,
      'body': challenge.bodyTemplate,
      'headers': {
        ...?(searchRule['headers'] as Map?)?.map((k, v) => MapEntry('$k', v)),
        ...challenge.headers,
        'Referer': challenge.pageUrl,
      },
    };
    final body = await _fetchText(challenge.submitUrl, section, context: context);
    await _throwIfCaptcha(
      source,
      searchRule,
      body,
      pageUrl: challenge.pageUrl,
      context: context,
    );
    return _mapSearchRecords(source, searchRule, body, context);
  }

  Future<Book> getDetail(BookSource source, SearchRecord record) async {
    final detailRule = _sectionOrNull(source.rule, 'detail');
    final now = DateTime.now();
    final bookId = Book.buildId(source.id, record.sourceBookId);
    final detailUrl0 = detailRule?['url'] as String?;
    if (detailRule == null || detailUrl0 == null || detailUrl0.isEmpty) {
      return Book(
        id: bookId,
        sourceId: source.id,
        sourceBookId: record.sourceBookId,
        title: record.title,
        author: record.author,
        coverUrl: record.coverUrl,
        detailUrl: record.detailUrl,
        addedAt: now,
        updatedAt: now,
      );
    }
    final context = _idContext(
      record.sourceBookId,
      detailUrl: record.detailUrl,
      title: record.title,
    );
    final url =
        renderTemplate(detailRule['url'] as String? ?? record.detailUrl, context);
    final body = await _fetchText(url, detailRule, context: context);
    final items = RuleParser.parse(
      body,
      (detailRule['parser'] as Map?)?.cast<String, dynamic>() ?? {},
      context: context,
    );
    final f = items.isNotEmpty ? items.first : <String, String>{};
    return Book(
      id: bookId,
      sourceId: source.id,
      sourceBookId: record.sourceBookId,
      title: f['title']?.isNotEmpty == true ? f['title']! : record.title,
      author: f['author']?.isNotEmpty == true ? f['author']! : record.author,
      coverUrl: f['coverUrl']?.isNotEmpty == true ? f['coverUrl']! : record.coverUrl,
      description: f['description'],
      detailUrl: f['detailUrl']?.isNotEmpty == true
          ? f['detailUrl']!
          : record.detailUrl,
      addedAt: now,
      updatedAt: now,
    );
  }

  Future<List<Chapter>> getChapters(BookSource source, Book book) async {
    final chaptersRule = Map<String, dynamic>.from(_section(source.rule, 'chapters'));

    final bookKey = _resolveBookKey(
      source,
      fallback: book.sourceBookId,
      detailUrl: book.detailUrl,
      title: book.title,
    );
    final context = _idContext(
      bookKey,
      detailUrl: book.detailUrl,
      title: book.title,
    );
    _prepareAuthContext(source, context);

    final body = await _requestSection(
      source,
      chaptersRule,
      context,
      fallbackUrl: book.detailUrl,
    );
    final items = RuleParser.parse(
      body,
      (chaptersRule['parser'] as Map).cast<String, dynamic>(),
      context: context,
    );
    final allowEmpty = _allowsEmptyChapterAudio(source);
    final chapters = <Chapter>[];
    for (final f in items) {
      final audioUrl = f['audioUrl'] ?? '';
      if (audioUrl.isEmpty && !allowEmpty) continue;
      final title = f['title']?.isNotEmpty == true
          ? f['title']!
          : '第 ${chapters.length + 1} 集';
      final resolvedAudio = audioUrl.isEmpty
          ? 'lazy://$bookKey/${chapters.length}'
          : _absoluteUrl(audioUrl, book.detailUrl);
      chapters.add(Chapter(
        id: Chapter.buildId(book.id, chapters.length),
        bookId: book.id,
        index: chapters.length,
        title: title,
        audioUrl: resolvedAudio,
        duration: int.tryParse(f['duration'] ?? ''),
        size: int.tryParse(f['size'] ?? ''),
        pubDate: f['pubDate'],
      ));
    }
    if (chapters.isEmpty) throw SourceRuleException('章节解析结果为空');
    return chapters;
  }

  /// 解析章节音频直链（支持 POST + 声明式加解密 + auth）。
  Future<String> resolveAudio(
    BookSource source,
    Chapter chapter, {
    Book? book,
  }) async {
    final audioRule = _sectionOrNull(source.rule, 'audio');
    if (audioRule == null) return chapter.audioUrl;

    final bookKey = _resolveBookKey(
      source,
      fallback: book?.sourceBookId ??
          (chapter.bookId.contains('::')
              ? chapter.bookId.split('::').skip(1).join('::')
              : chapter.bookId),
      detailUrl: book?.detailUrl ?? '',
      title: book?.title ?? '',
    );
    final indexBase = (audioRule['chapterIndexBase'] as num?)?.toInt() ?? 0;
    final chapterIndex = indexBase == 1 ? chapter.index + 1 : chapter.index;

    final context = _idContext(
      bookKey,
      detailUrl: book?.detailUrl ?? '',
      title: book?.title ?? '',
    );
    context['chapterTitle'] = chapter.title;
    context['chapterIndex'] = chapterIndex;
    context['url'] = chapter.audioUrl;
    _prepareAuthContext(source, context);
    _putToken(context, await _ensureGuestToken(source, context));

    final audioSection = Map<String, dynamic>.from(audioRule);

    final parser = (audioSection['parser'] as Map?)?.cast<String, dynamic>();
    final type = parser?['type'] as String?;
    final hasTokenEndpoint =
        ((audioSection['url'] as String?) ?? '').isNotEmpty ||
            (audioSection['urls'] is List &&
                (audioSection['urls'] as List).isNotEmpty);
    final hasCrypto = audioSection['requestCrypto'] != null ||
        (audioSection['responseParse'] as Map?)?['decrypt'] != null;

    // 旧路径：无独立 url、无 crypto → GET chapter.audioUrl + parser
    if (!hasTokenEndpoint && !hasCrypto) {
      if (parser == null || type == 'direct') return chapter.audioUrl;
      final pageBody =
          await _fetchText(chapter.audioUrl, audioSection, context: context);
      final items = RuleParser.parse(pageBody, parser, context: context);
      final resolved = items.isNotEmpty
          ? (items.first['audioUrl'] ?? items.first['url'] ?? '')
          : '';
      if (resolved.isEmpty) {
        throw SourceRuleException('音频直链解析失败: ${chapter.title}');
      }
      return _absoluteUrl(resolved, chapter.audioUrl);
    }

    final text = await _requestSection(
      source,
      audioSection,
      context,
      fallbackUrl: chapter.audioUrl.startsWith('lazy://')
          ? null
          : chapter.audioUrl,
    );
    final playUrl = _extractAudioUrl(text, audioSection, context);
    if (playUrl.isEmpty) {
      throw SourceRuleException('音频直链解析失败: ${chapter.title}');
    }
    return playUrl;
  }

  bool needsAudioResolve(BookSource source) {
    final audioRule = _sectionOrNull(source.rule, 'audio');
    if (audioRule == null) return false;
    if (audioRule['requestCrypto'] != null) return true;
    if ((audioRule['responseParse'] as Map?)?['decrypt'] != null) return true;
    if (((audioRule['url'] as String?) ?? '').isNotEmpty) return true;
    final type = (audioRule['parser'] as Map?)?['type'] as String?;
    return type != null && type != 'direct';
  }

  /// 签名/加密直链必须现取；旧二次解析默认可 eager。
  bool isLazyAudioResolve(BookSource source) {
    final audio = _sectionOrNull(source.rule, 'audio');
    if (audio == null) return false;
    final policy = (audio['resolvePolicy'] as String?)?.toLowerCase();
    if (policy == 'lazy') return true;
    if (policy == 'eager') return false;
    return audio['requestCrypto'] != null ||
        (audio['responseParse'] as Map?)?['decrypt'] != null ||
        audio['cachePlayUrl'] == false;
  }

  // ---------------- 内部实现 ----------------

  bool _allowsEmptyChapterAudio(BookSource source) {
    final audio = _sectionOrNull(source.rule, 'audio');
    if (audio == null) return false;
    return ((audio['url'] as String?) ?? '').isNotEmpty ||
        audio['requestCrypto'] != null ||
        (audio['responseParse'] as Map?)?['decrypt'] != null;
  }

  Future<String?> _ensureGuestToken(
    BookSource source,
    Map<String, dynamic> context,
  ) async {
    final auth = _sectionOrNull(source.rule, 'auth');
    if (auth == null) return null;
    final authId = (auth['id'] as String?) ?? 'guest';
    final cached = authCache?.get(source.id, authId);
    if (cached != null && cached.isNotEmpty) return cached;

    final acquire = (auth['acquire'] as Map?)?.cast<String, dynamic>();
    if (acquire == null) {
      throw SourceRuleException('auth.acquire 未配置，无法获取 token');
    }
    _prepareAuthContext(source, context);
    final section = Map<String, dynamic>.from(acquire);
    final text = await _requestSection(source, section, context);
    final tokenField = (auth['tokenField'] as String?) ?? 'token';
    String token = '';
    final rp = (acquire['responseParse'] as Map?)?.cast<String, dynamic>();
    if (rp != null) {
      final map = _parseResponseObject(text, rp, context);
      token = stringifyValue(
        map[tokenField] ?? map['token'] ?? '',
      );
    } else {
      try {
        final json = jsonDecode(text);
        if (json is Map) {
          token = stringifyValue(
            json[tokenField] ?? json['token'] ?? '',
          );
        }
      } catch (_) {}
    }
    if (token.isEmpty) {
      throw SourceRuleException('auth 未解析到令牌字段「$tokenField」');
    }
    final ttl = (auth['cacheTtlSec'] as num?)?.toInt() ?? 3600;
    await authCache?.set(source.id, authId, token, ttlSec: ttl);
    return token;
  }

  void _prepareAuthContext(BookSource source, Map<String, dynamic> context) {
    final auth = _sectionOrNull(source.rule, 'auth');
    SourceAuthBootstrap.apply(auth, context);
  }

  /// 书籍主键：`variables.bookId` → 从详情地址猜测 → [fallback]
  String _resolveBookKey(
    BookSource source, {
    required String fallback,
    String detailUrl = '',
    String title = '',
  }) {
    final ctx = {
      'detailUrl': detailUrl,
      'bookId': fallback,
      'title': title,
    };
    return _resolveRuleVariable(source, 'bookId', ctx) ??
        _guessBookId(detailUrl) ??
        fallback;
  }

  Map<String, dynamic> _idContext(
    String bookKey, {
    String detailUrl = '',
    String title = '',
  }) =>
      {
        'bookId': bookKey,
        'detailUrl': detailUrl,
        'title': title,
      };

  void _putToken(Map<String, dynamic> context, String? token) {
    context['token'] = token ?? '';
  }

  String? _resolveRuleVariable(
    BookSource source,
    String name,
    Map<String, dynamic> context,
  ) {
    final vars = (source.rule['variables'] as Map?)?.cast<String, dynamic>();
    final spec = vars?[name];
    if (spec is! Map) return null;
    final from = spec['from'] as String?;
    final regex = spec['regex'] as String?;
    final capture = (spec['capture'] as num?)?.toInt() ?? 1;
    if (from == null || regex == null) return null;
    final input = stringifyValue(context[from]);
    if (input.isEmpty) return null;
    final m = RegExp(regex).firstMatch(input);
    if (m == null) return null;
    if (capture <= m.groupCount) return m.group(capture);
    return m.group(0);
  }

  String? _guessBookId(String detailUrl) {
    if (detailUrl.isEmpty) return null;
    final album = RegExp(r'albums?/(\d+)').firstMatch(detailUrl);
    if (album != null) return album.group(1);
    final htmlId = RegExp(r'/(\d+)\.html(?:$|[?#])').firstMatch(detailUrl);
    return htmlId?.group(1);
  }

  /// search.keywordMap：把展示名映射成栏目 ID。
  String _mapSearchKeyword(Map<String, dynamic> searchRule, String query) {
    final map = searchRule['keywordMap'];
    if (map is! Map || query.isEmpty) return query;
    final hit = map[query] ?? map[query.toLowerCase()];
    return hit?.toString() ?? query;
  }

  bool _shouldUseKeywordMapMiss(
    Map<String, dynamic> searchRule,
    String query,
    String pathKeyword,
  ) {
    final map = searchRule['keywordMap'];
    if (map is! Map || map.isEmpty) return false;
    if (query.isEmpty) return false;
    // 已映射，或用户直接输入栏目数字 ID
    if (pathKeyword != query) return false;
    if (RegExp(r'^\d+$').hasMatch(query)) return false;
    return true;
  }

  ({String url, Map<String, dynamic> context, bool viaCategory})
      _prepareSearchRequest(
    Map<String, dynamic> searchRule,
    String keyword, {
    int page = 1,
  }) {
    final query = keyword.trim();
    final pathKeyword = _mapSearchKeyword(searchRule, query);
    final mapHit = pathKeyword != query;
    final numericId = RegExp(r'^\d+$').hasMatch(query);
    final mapUrl = (searchRule['keywordMapUrl'] as String?)?.trim() ?? '';
    final viaCategory = (mapHit || numericId) && mapUrl.isNotEmpty;

    var urlTemplate = searchRule['url'] as String? ?? '';
    var encodeKeyword = searchRule['encodeKeyword'] != false;
    if (viaCategory) {
      urlTemplate = mapUrl;
      encodeKeyword = false;
    } else if (_shouldUseKeywordMapMiss(searchRule, query, pathKeyword)) {
      final miss = (searchRule['keywordMapMissUrl'] as String?)?.trim() ?? '';
      if (miss.isNotEmpty) urlTemplate = miss;
    }

    final context = <String, dynamic>{
      'query': query,
      'keyword': encodeKeyword
          ? Uri.encodeQueryComponent(pathKeyword)
          : pathKeyword,
      'page': page,
    };
    final url = renderTemplate(urlTemplate, context);
    if (url.isEmpty) throw SourceRuleException('书源未配置搜索地址');
    return (url: url, context: context, viaCategory: viaCategory);
  }

  List<SearchRecord> _mapSearchRecords(
    BookSource source,
    Map<String, dynamic> searchRule,
    String body,
    Map<String, dynamic> context,
  ) {
    final items = RuleParser.parse(
      body,
      (searchRule['parser'] as Map).cast<String, dynamic>(),
      context: context,
    );
    final records = <SearchRecord>[];
    final siteUrl = source.url;
    for (final f in items) {
      var detailUrl = f['detailUrl'] ?? '';
      if (detailUrl.isNotEmpty) {
        detailUrl = _absoluteUrl(detailUrl, siteUrl);
      }
      var bookId = f['bookId'] ?? '';
      if (bookId.isEmpty) {
        bookId = _resolveBookKey(
          source,
          fallback: detailUrl,
          detailUrl: detailUrl,
          title: f['title'] ?? '',
        );
      }
      if (bookId.isEmpty && detailUrl.isEmpty) continue;
      var cover = f['coverUrl'] ?? '';
      if (cover.isNotEmpty) {
        cover = _absoluteUrl(cover, siteUrl);
      }
      records.add(SearchRecord(
        sourceId: source.id,
        sourceName: source.name,
        sourceBookId: bookId.isNotEmpty ? bookId : detailUrl,
        title: f['title']?.isNotEmpty == true ? f['title']! : '未命名',
        author: f['author'],
        narrator: f['narrator'],
        coverUrl: cover.isNotEmpty ? cover : null,
        detailUrl: detailUrl,
        category: f['category'],
        chapterCount: f['chapterTotal'],
      ));
    }
    return records;
  }

  bool _looksLikeCaptcha(Map<String, dynamic>? captchaRule, String body) {
    if (captchaRule == null || captchaRule.isEmpty) return false;
    final needles = <String>[];
    final one = captchaRule['detectContains'];
    if (one is String && one.isNotEmpty) needles.add(one);
    if (one is List) {
      for (final e in one) {
        final s = e.toString();
        if (s.isNotEmpty) needles.add(s);
      }
    }
    if (needles.isEmpty) return false;
    return needles.any(body.contains);
  }

  Future<void> _throwIfCaptcha(
    BookSource source,
    Map<String, dynamic> searchRule,
    String body, {
    required String pageUrl,
    required Map<String, dynamic> context,
  }) async {
    final captchaRule =
        (searchRule['captcha'] as Map?)?.cast<String, dynamic>();
    if (!_looksLikeCaptcha(captchaRule, body)) return;
    final challenge = await _buildCaptchaChallenge(
      source,
      searchRule,
      captchaRule ?? const {},
      body,
      pageUrl: pageUrl,
      context: context,
    );
    throw SourceCaptchaRequiredException(challenge);
  }

  Future<SearchCaptchaChallenge> _buildCaptchaChallenge(
    BookSource source,
    Map<String, dynamic> searchRule,
    Map<String, dynamic> captchaRule,
    String body, {
    required String pageUrl,
    required Map<String, dynamic> context,
  }) async {
    final doc = html_parser.parse(body);
    var imagePath = (captchaRule['imageUrl'] as String?)?.trim() ?? '';
    final imgSel = (captchaRule['imageSelector'] as String?)?.trim();
    if (imgSel != null && imgSel.isNotEmpty) {
      // 支持 `img.captcha @src`
      final at = imgSel.lastIndexOf('@');
      final sel = at >= 0 ? imgSel.substring(0, at).trim() : imgSel;
      final attr = at >= 0 ? imgSel.substring(at + 1).trim() : 'src';
      final el = doc.querySelector(sel);
      final fromDom = el?.attributes[attr]?.trim() ?? '';
      if (fromDom.isNotEmpty) imagePath = fromDom;
    }
    final imageUrl =
        imagePath.isEmpty ? '' : _absoluteUrl(imagePath, pageUrl);

    var action = (captchaRule['submitUrl'] as String?)?.trim() ?? '';
    if (action.contains('{{')) {
      action = renderTemplate(action, {...context, 'pageUrl': pageUrl});
    }
    final actionSel =
        (captchaRule['formActionSelector'] as String?)?.trim() ?? 'form @action';
    if (action.isEmpty || action == '{{pageUrl}}') {
      final at = actionSel.lastIndexOf('@');
      final sel = at >= 0 ? actionSel.substring(0, at).trim() : 'form';
      final attr = at >= 0 ? actionSel.substring(at + 1).trim() : 'action';
      final form = doc.querySelector(sel.isEmpty ? 'form' : sel);
      final fromForm = form?.attributes[attr]?.trim() ?? '';
      action = fromForm.isNotEmpty ? fromForm : pageUrl;
    }
    final submitUrl = _absoluteUrl(action, pageUrl);

    final bodyTemplate = (captchaRule['body'] as String?)?.trim() ?? '';
    final method =
        ((captchaRule['submitMethod'] as String?) ?? 'POST').toUpperCase();

    final headers = <String, String>{};
    final rawHeaders = searchRule['headers'] as Map?;
    if (rawHeaders != null) {
      for (final e in rawHeaders.entries) {
        headers[e.key.toString()] =
            renderTemplate(e.value.toString(), context);
      }
    }
    headers['Referer'] = pageUrl;

    Uint8List? bytes;
    if (imageUrl.isNotEmpty) {
      try {
        bytes = await _fetchBytes(imageUrl, headers: headers);
      } catch (_) {}
    }

    return SearchCaptchaChallenge(
      pageUrl: pageUrl,
      imageUrl: imageUrl,
      imageBytes: bytes,
      submitUrl: submitUrl,
      submitMethod: method,
      bodyTemplate: bodyTemplate,
      headers: headers,
    );
  }

  Future<Uint8List> _fetchBytes(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final res = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
      ),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }

  Future<String> _requestSection(
    BookSource source,
    Map<String, dynamic> section,
    Map<String, dynamic> context, {
    String? fallbackUrl,
  }) async {
    final urls = <String>[];
    final single = renderTemplate(section['url'] as String? ?? '', context);
    if (single.isNotEmpty) urls.add(single);
    final list = section['urls'];
    if (list is List) {
      for (final u in list) {
        final t = renderTemplate(u.toString(), context);
        if (t.isNotEmpty && !urls.contains(t)) urls.add(t);
      }
    }
    if (urls.isEmpty && fallbackUrl != null && fallbackUrl.isNotEmpty) {
      urls.add(fallbackUrl);
    }
    if (urls.isEmpty) {
      throw SourceRuleException('请求地址为空');
    }

    Object? lastError;
    for (final url in urls) {
      try {
        return await _fetchText(url, section, context: context);
      } catch (e) {
        lastError = e;
      }
    }
    throw SourceRuleException('全部端点失败: $lastError');
  }

  Future<String> _fetchText(
    String url,
    Map<String, dynamic> section, {
    Map<String, dynamic>? context,
  }) async {
    final ctx = context ?? <String, dynamic>{};
    final method = ((section['method'] as String?) ?? 'GET').toUpperCase();
    final rawHeaders =
        (section['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
            {};
    final headers = <String, String>{};
    for (final e in rawHeaders.entries) {
      headers[e.key] = renderTemplate(e.value.toString(), ctx);
    }

    var bodyTemplate = section['body'] as String?;
    String? body;
    if (bodyTemplate != null) {
      body = renderTemplate(bodyTemplate, ctx);
      final reqCrypto =
          (section['requestCrypto'] as Map?)?.cast<String, dynamic>();
      if (reqCrypto != null) {
        body = await SourceCrypto.encrypt(body, reqCrypto);
      }
    }

    final bodyEncoding =
        ((section['bodyEncoding'] as String?) ?? 'plain').toLowerCase();
    final charset = ((section['charset'] as String?) ?? 'utf-8').toLowerCase();

    String? contentType;
    if (body != null) {
      if (headers.containsKey('Content-Type') ||
          headers.containsKey('content-type')) {
        contentType = null; // 已在 headers
      } else if (bodyEncoding == 'raw') {
        contentType = 'text/plain';
      } else {
        contentType = 'application/x-www-form-urlencoded';
      }
    }

    final res = await _dio.request<List<int>>(
      url,
      data: body,
      options: Options(
        method: method == 'POST' ? 'POST' : 'GET',
        headers: headers,
        responseType: ResponseType.bytes,
        contentType: contentType,
      ),
    );
    final bytes = res.data ?? <int>[];
    final text = decodeCharset(bytes, charset);
    return _maybeDecryptResponse(text, section, ctx);
  }

  Future<String> _maybeDecryptResponse(
    String text,
    Map<String, dynamic> section,
    Map<String, dynamic> context,
  ) async {
    final rp = (section['responseParse'] as Map?)?.cast<String, dynamic>();
    final decrypt = (rp?['decrypt'] as Map?)?.cast<String, dynamic>();
    if (decrypt == null) return text;

    String cipherOuter = text;
    final payloadPath = rp?['payloadPath'] as String?;
    if (payloadPath != null && payloadPath.isNotEmpty) {
      try {
        final json = jsonDecode(text);
        final v = readJsonPath(json, payloadPath);
        cipherOuter = stringifyValue(v);
      } catch (e) {
        throw SourceCryptoException(
          'protocol_changed',
          '无法从响应提取密文（$payloadPath）: $e',
        );
      }
    }
    if (cipherOuter.isEmpty) {
      throw SourceCryptoException('protocol_changed', '响应密文为空');
    }
    try {
      return await SourceCrypto.decrypt(cipherOuter, decrypt);
    } on SourceCryptoException {
      // 配置了 decrypt 但响应已是明文 JSON 时回退
      final t = text.trimLeft();
      if (t.startsWith('{') || t.startsWith('[')) return text;
      rethrow;
    }
  }

  String _extractAudioUrl(
    String text,
    Map<String, dynamic> audioRule,
    Map<String, dynamic> context,
  ) {
    final rp = (audioRule['responseParse'] as Map?)?.cast<String, dynamic>();
    if (rp != null) {
      final audioPath = rp['audioUrl'] as String?;
      if (audioPath != null && audioPath.startsWith(r'$')) {
        try {
          final json = jsonDecode(text);
          final v = readJsonPath(json, audioPath);
          final s = stringifyValue(v);
          if (s.isNotEmpty) return s;
        } catch (_) {}
      }
      final map = _parseResponseObject(text, rp, context);
      final s = map['audioUrl'] ?? '';
      if (s.isNotEmpty) return s;
    }
    final parser = (audioRule['parser'] as Map?)?.cast<String, dynamic>();
    if (parser != null) {
      final items = RuleParser.parse(text, parser, context: context);
      if (items.isNotEmpty) {
        return items.first['audioUrl'] ?? '';
      }
    }
    return '';
  }

  Map<String, String> _parseResponseObject(
    String text,
    Map<String, dynamic> rp,
    Map<String, dynamic> context,
  ) {
    final mode = (rp['mode'] as String?) ?? 'json';
    if (mode == 'json' || mode == 'direct') {
      try {
        final json = jsonDecode(text);
        final fields = <String, dynamic>{
          ...((rp['fields'] as Map?)?.cast<String, dynamic>() ?? {}),
        };
        for (final key in ['token', 'audioUrl']) {
          final v = rp[key];
          if (v is String && v.isNotEmpty && !fields.containsKey(key)) {
            fields[key] = v;
          }
        }
        final out = <String, String>{};
        if (fields.isEmpty && json is Map) {
          for (final e in json.entries) {
            out[e.key.toString()] = stringifyValue(e.value);
          }
          return out;
        }
        for (final e in fields.entries) {
          final path = e.value.toString();
          if (path.startsWith(r'$')) {
            out[e.key] = stringifyValue(readJsonPath(json, path));
          } else {
            out[e.key] = renderTemplate(path, {
              ...context,
              if (json is Map)
                ...Map<String, dynamic>.from(
                  json.map((k, v) => MapEntry(k.toString(), v)),
                ),
            });
          }
        }
        final audioPath = rp['audioUrl'] as String?;
        if (audioPath != null &&
            audioPath.startsWith(r'$') &&
            (out['audioUrl'] ?? '').isEmpty) {
          out['audioUrl'] = stringifyValue(readJsonPath(json, audioPath));
        }
        return out;
      } catch (_) {
        return {};
      }
    }
    final parser = {
      'type': mode,
      'listSelector': rp['listSelector'],
      'fields': rp['fields'] ?? {},
    };
    final items = RuleParser.parse(
      text,
      parser.cast<String, dynamic>(),
      context: context,
    );
    return items.isNotEmpty ? items.first : {};
  }

  Map<String, dynamic> _section(Map<String, dynamic> rule, String key) {
    final s = rule[key];
    if (s is Map) return s.cast<String, dynamic>();
    throw SourceRuleException('书源规则缺少 $key 配置');
  }

  Map<String, dynamic>? _sectionOrNull(Map<String, dynamic> rule, String key) {
    final s = rule[key];
    if (s is Map) return s.cast<String, dynamic>();
    return null;
  }

  static String decodeCharset(List<int> bytes, String charset) {
    late final String text;
    switch (charset) {
      case 'utf-8':
      case 'utf8':
        text = utf8.decode(bytes, allowMalformed: true);
        break;
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        text = gbk.decode(bytes);
        break;
      case 'big5':
        text = utf8.decode(bytes, allowMalformed: true);
        break;
      default:
        text = utf8.decode(bytes, allowMalformed: true);
    }
    // 部分站点 JSON 带 UTF-8 BOM，jsonDecode 会失败
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  static String _absoluteUrl(String url, String baseUrl) {
    if (url.isEmpty ||
        url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('lazy://')) {
      return url;
    }
    try {
      final base = Uri.parse(baseUrl);
      if (url.startsWith('//')) return '${base.scheme}:$url';
      // `?scheckAC=check` 这类相对查询串
      if (url.startsWith('?') || url.startsWith('#')) {
        return base.resolve(url).toString();
      }
      if (url.startsWith('/')) {
        return '${base.scheme}://${base.host}'
            '${base.hasPort && base.port != 80 && base.port != 443 ? ':${base.port}' : ''}'
            '$url';
      }
      final basePath = base.path.substring(0, base.path.lastIndexOf('/') + 1);
      return base.resolve(basePath + url).toString();
    } catch (_) {
      return url;
    }
  }
}
