import 'dart:typed_data';

/// 搜索验证码挑战（站点返回人机验证页时抛出 / 挂在搜索状态上）
class SearchCaptchaChallenge {
  /// 触发验证码的请求页（用于拼相对 action / Referer）
  final String pageUrl;

  /// 验证码图片绝对地址
  final String imageUrl;

  /// 与 Cookie 会话一致拉取的图片字节（可空，UI 可再刷新）
  final Uint8List? imageBytes;

  /// POST 提交地址（已解析为绝对 URL）
  final String submitUrl;

  final String submitMethod;

  /// 表单 body 模板，可用 {{code}} / {{keyword}} / {{query}}
  final String bodyTemplate;

  /// 提交时附加的 headers（已渲染）
  final Map<String, String> headers;

  const SearchCaptchaChallenge({
    required this.pageUrl,
    required this.imageUrl,
    required this.submitUrl,
    required this.bodyTemplate,
    this.imageBytes,
    this.submitMethod = 'POST',
    this.headers = const {},
  });

  SearchCaptchaChallenge copyWith({Uint8List? imageBytes}) {
    return SearchCaptchaChallenge(
      pageUrl: pageUrl,
      imageUrl: imageUrl,
      imageBytes: imageBytes ?? this.imageBytes,
      submitUrl: submitUrl,
      submitMethod: submitMethod,
      bodyTemplate: bodyTemplate,
      headers: headers,
    );
  }
}

/// 书源搜索需要用户完成验证码
class SourceCaptchaRequiredException implements Exception {
  final SearchCaptchaChallenge challenge;

  SourceCaptchaRequiredException(this.challenge);

  @override
  String toString() => '需要验证码才能继续搜索';
}
