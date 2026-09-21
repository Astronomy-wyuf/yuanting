import 'book.dart';
import 'book_source.dart';
import '../services/settings_service.dart';

/// 片头片尾跳过配置（秒）
class SkipConfig {
  /// 片头跳过秒数
  final int intro;

  /// 片尾跳过秒数（距结尾不足该秒数时自动切下一集）
  final int outro;

  const SkipConfig({this.intro = 0, this.outro = 0});

  bool get isEmpty => intro <= 0 && outro <= 0;

  /// 三级配置优先级：书籍级 > 书源级 > 全局默认
  /// - 书籍级：Book.skipIntro / skipOutro（null 表示未设置）
  /// - 书源级：rule.skip.intro / outro
  /// - 全局：AppSettings.defaultSkipIntro / defaultSkipOutro
  static SkipConfig effective(Book? book, BookSource? source, AppSettingsService settings) {
    final ruleSkip = (source?.rule['skip'] as Map?)?.cast<String, dynamic>();
    final sourceIntro = (ruleSkip?['intro'] as num?)?.toInt();
    final sourceOutro = (ruleSkip?['outro'] as num?)?.toInt();
    return SkipConfig(
      intro: book?.skipIntro ?? sourceIntro ?? settings.defaultSkipIntro,
      outro: book?.skipOutro ?? sourceOutro ?? settings.defaultSkipOutro,
    );
  }
}
