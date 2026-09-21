# 源听（YuanTing）

Flutter 听书 / 广播剧聚合播放器。通过自定义 JSON 书源聚合搜索、浏览与播放。

**自定义书源 · 聚合听书**

## 功能

- 书架续听、发现浏览、跨源搜索
- 书源管理（粘贴 / 文件 / 网络导入）
- 后台播放、断点续播、倍速、睡眠定时
- 片头片尾跳过、离线下载（断点续传）

## 环境

- Flutter SDK **3.22+**
- Android SDK 34 + JDK 17
- iOS 需 macOS + Xcode 15+

## 运行

```bash
flutter pub get
flutter run
```

### Android

```bash
flutter build apk --split-per-abi
```

### iOS

```bash
cd ios && pod install && cd ..
flutter build ipa
```

## 书源规则（简要）

```jsonc
{
  "site": { "name": "源名称", "url": "https://example.com", "version": 1 },
  "search": {
    "url": "https://example.com/search?q={{keyword}}&p={{page}}",
    "parser": {
      "type": "json",
      "listSelector": "$.items",
      "fields": { "bookId": "$.id", "title": "$.title" }
    }
  },
  "chapters": {
    "url": "https://example.com/book/{{bookId}}",
    "parser": {
      "type": "html",
      "listSelector": "ul.chapter-list li",
      "fields": { "title": "a @text", "audioUrl": "a @href" }
    }
  },
  "audio": { "parser": { "type": "direct" } }
}
```

在「书源管理」中粘贴、选文件或通过 URL 导入即可。字段说明见 [书源规则.md](书源规则.md)。

## 许可

仅供学习交流使用。请自行保证所使用书源与内容的合法性。
