/// 音频相关工具函数
class AudioUtils {
  AudioUtils._();

  /// 将秒数格式化为 "mm:ss" 或 "h:mm:ss"
  static String formatSeconds(double seconds) {
    if (seconds.isNaN || seconds < 0) seconds = 0;
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 格式化 Duration
  static String formatDuration(Duration d) => formatSeconds(d.inSeconds.toDouble());

  /// 格式化字节数
  static String formatBytes(int bytes) {
    if (bytes < 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
